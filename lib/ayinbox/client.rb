# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "openssl"

module Ayinbox
  # Sends one HTTP request with Net::HTTP. Replace it through Client.new(transport:)
  # with any object answering #call(method, uri, headers, body, timeout) => [status, headers, body].
  class NetHTTPTransport
    def call(method, uri, headers, body, timeout)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout if http.respond_to?(:write_timeout=)
      req = Net::HTTPGenericRequest.new(method, !body.nil?, method != "HEAD", uri.request_uri, headers)
      req.body = body unless body.nil?
      res = http.start { |h| h.request(req) }
      out_headers = {}
      res.each_header { |k, v| out_headers[k.downcase] = v }
      [res.code.to_i, out_headers, res.body.to_s]
    end
  end

  # The AY Inbox API client.
  class Client
    DEFAULT_BASE_URL = "https://api.ayinbox.com/v1"
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 2
    RETRY_AFTER_CAP = 120.0
    BACKOFF_BASE = 0.5
    BACKOFF_CAP = 8.0
    RETRYABLE_STATUSES = [429, 502, 503, 504].freeze
    REQUEST_OPTIONS = %i[idempotency_key timeout headers].freeze

    CONNECTION_ERRORS = [
      SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, EOFError
    ].freeze
    TIMEOUT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout].tap do |list|
      list << Net::WriteTimeout if defined?(Net::WriteTimeout)
    end.freeze

    attr_reader :base_url, :timeout, :max_retries

    def initialize(api_key: nil, base_url: nil, timeout: DEFAULT_TIMEOUT, max_retries: DEFAULT_MAX_RETRIES,
                   transport: nil, sleeper: nil)
      @api_key = api_key || ENV.fetch("AYINBOX_API_KEY", nil)
      if @api_key.nil? || @api_key.to_s.strip.empty?
        raise ConfigurationError, "No API key. Pass api_key: or set AYINBOX_API_KEY."
      end

      env_base = ENV.fetch("AYINBOX_BASE_URL", nil)
      env_base = nil if env_base && env_base.strip.empty?
      @base_url = (base_url || env_base || DEFAULT_BASE_URL).to_s.sub(%r{/+\z}, "")
      @timeout = timeout
      @max_retries = [max_retries.to_i, 0].max
      @transport = transport || NetHTTPTransport.new
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect} api_key=[REDACTED]>"
    end
    alias to_s inspect

    def me
      @me ||= Resources::Me.new(self)
    end

    def campaigns
      @campaigns ||= Resources::Campaigns.new(self)
    end

    def contacts
      @contacts ||= Resources::Contacts.new(self)
    end

    def mailboxes
      @mailboxes ||= Resources::Mailboxes.new(self)
    end

    def unibox
      @unibox ||= Resources::Unibox.new(self)
    end

    def webhooks
      Webhooks
    end

    # Calls any route. Returns the decoded JSON, nil for an empty body, or the raw string for non-JSON.
    def request(method, path, query: nil, body: nil, idempotency_key: nil, headers: nil, timeout: nil)
      perform(method, path, query: query, body: body, idempotency_key: idempotency_key,
                            headers: headers, timeout: timeout)
    end

    # Walks every page of a paginated route and yields each row. Returns an Enumerator without a block.
    def paginate(method, path, query: nil, body: nil, headers: nil, timeout: nil, &block)
      first = fetch_page(method, path, query: query, body: body, headers: headers, timeout: timeout)
      first.auto_paging_each(&block)
    end

    # @api private
    def fetch_page(method, path, query: nil, body: nil, headers: nil, timeout: nil)
      verb = method.to_s.upcase
      query = (query || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v }
      result = perform(verb, path, query: query, body: body, headers: headers, timeout: timeout,
                                   read_only: true)
      fetch = lambda do |cursor|
        fetch_page(verb, path, query: query.merge("cursor" => cursor), body: body,
                               headers: headers, timeout: timeout)
      end
      Page.new(result, fetch)
    end

    # @api private
    def perform(method, path, query: nil, body: nil, idempotency_key: nil, headers: nil, timeout: nil,
                read_only: false)
      verb = method.to_s.upcase
      uri = build_uri(path, query)
      payload = body.nil? ? nil : JSON.generate(body)
      req_headers = build_headers(payload, idempotency_key, headers)
      may_retry_unsafe = read_only || !idempotency_key.nil? || !%w[POST PATCH].include?(verb)
      attempt = 0
      loop do
        begin
          status, res_headers, raw = @transport.call(verb, uri, req_headers, payload, timeout || @timeout)
        rescue *TIMEOUT_ERRORS => e
          raise TimeoutError, "Request timed out: #{e.class}" unless may_retry_unsafe && attempt < @max_retries

          wait(attempt, nil)
          attempt += 1
          next
        rescue *CONNECTION_ERRORS => e
          raise APIConnectionError, "Connection failed: #{e.class}" unless may_retry_unsafe && attempt < @max_retries

          wait(attempt, nil)
          attempt += 1
          next
        end
        res_headers = normalize_headers(res_headers)
        return decode(raw, res_headers) if status >= 200 && status < 300

        error = ErrorParser.build(status, res_headers, raw.to_s)
        retryable = RETRYABLE_STATUSES.include?(status) && (status == 429 || may_retry_unsafe) &&
                    error.code != "idempotency_outcome_unknown"
        raise error unless retryable && attempt < @max_retries

        wait(attempt, error.respond_to?(:retry_after) ? error.retry_after : nil)
        attempt += 1
      end
    end

    private

    def build_uri(path, query)
      p = path.to_s
      p = "/#{p}" unless p.start_with?("/")
      url = @base_url + p
      pairs = []
      (query || {}).each do |k, v|
        next if v.nil?

        value = v.is_a?(Array) ? v.join(",") : v.to_s
        pairs << [k.to_s, value]
      end
      url += (url.include?("?") ? "&" : "?") + URI.encode_www_form(pairs) unless pairs.empty?
      URI.parse(url)
    end

    def build_headers(payload, idempotency_key, extra)
      h = {
        "Authorization" => "Bearer #{@api_key}",
        "User-Agent" => "ayinbox-ruby/#{VERSION}",
        "Accept" => "application/json"
      }
      h["Content-Type"] = "application/json" unless payload.nil?
      h["Idempotency-Key"] = idempotency_key.to_s unless idempotency_key.nil?
      (extra || {}).each do |k, v|
        h.delete_if { |existing, _| existing.casecmp?(k.to_s) }
        h[k.to_s] = v.to_s
      end
      h
    end

    def normalize_headers(headers)
      out = {}
      (headers || {}).each { |k, v| out[k.to_s.downcase] = v.is_a?(Array) ? v.join(", ") : v.to_s }
      out
    end

    def decode(raw, headers)
      return nil if raw.nil? || raw.empty?

      type = headers["content-type"].to_s
      return raw unless type.empty? || type.include?("json")

      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end

    def wait(attempt, retry_after)
      seconds = if retry_after
                  [retry_after.to_f, RETRY_AFTER_CAP].min
                else
                  rand * [BACKOFF_CAP, BACKOFF_BASE * (2**attempt)].min
                end
      @sleeper.call(seconds)
    end
  end
end
