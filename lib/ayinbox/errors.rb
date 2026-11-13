# frozen_string_literal: true

require "json"
require "time"

module Ayinbox
  # Base class for every error this library raises.
  class Error < StandardError; end

  # Raised when the client is built without an API key.
  class ConfigurationError < Error; end

  # Raised when a webhook signature does not verify.
  class SignatureVerificationError < Error; end

  # The request did not get an HTTP answer (DNS, TLS, refused connection, reset).
  class APIConnectionError < Error; end

  # The request timed out before an answer arrived.
  class TimeoutError < APIConnectionError; end

  # The API answered with a non-2xx status.
  class APIError < Error
    attr_reader :status, :code, :reason, :request_id, :body, :headers

    def initialize(message = nil, status: nil, code: nil, reason: nil, request_id: nil, body: nil, headers: {})
      super(message)
      @status = status
      @code = code
      @reason = reason
      @request_id = request_id
      @body = body
      @headers = headers || {}
    end

    def inspect
      "#<#{self.class.name} status=#{status.inspect} code=#{code.inspect} request_id=#{request_id.inspect} " \
        "message=#{message.inspect}>"
    end
  end

  # Parent of the two validation errors (400 and 422).
  class InvalidRequestError < APIError; end
  class BadRequestError < InvalidRequestError; end
  class UnprocessableError < InvalidRequestError; end
  class AuthenticationError < APIError; end
  class PaymentRequiredError < APIError; end
  class PermissionDeniedError < APIError; end
  class NotFoundError < APIError; end
  class ConflictError < APIError; end

  # 429. retry_after is in seconds, or nil when the server gave none.
  class RateLimitError < APIError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **kwargs)
      super(message, **kwargs)
      @retry_after = retry_after
    end
  end

  # Parent of every 5xx error.
  class ServerError < APIError; end
  class InternalServerError < ServerError; end

  # 503. retry_after is in seconds, or nil.
  class ServiceUnavailableError < ServerError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **kwargs)
      super(message, **kwargs)
      @retry_after = retry_after
    end
  end

  # Builds the typed error for a non-2xx answer.
  module ErrorParser
    DEFAULT_CODES = {
      400 => "bad_request", 401 => "unauthorized", 402 => "insufficient_credits",
      403 => "forbidden", 404 => "not_found", 409 => "conflict", 422 => "unprocessable",
      429 => "rate_limit_exceeded", 500 => "internal_error", 501 => "not_implemented",
      503 => "service_unavailable"
    }.freeze

    CLASSES = {
      400 => BadRequestError, 401 => AuthenticationError, 402 => PaymentRequiredError,
      403 => PermissionDeniedError, 404 => NotFoundError, 409 => ConflictError,
      422 => UnprocessableError, 429 => RateLimitError, 503 => ServiceUnavailableError
    }.freeze

    module_function

    def build(status, headers, raw_body)
      body = parse_json(raw_body)
      hash = body.is_a?(Hash) ? body : {}
      code = string_or_nil(hash["code"])
      if code.nil?
        err = string_or_nil(hash["error"])
        code = err if err&.match?(/\A[a-z0-9_]+\z/)
      end
      code ||= DEFAULT_CODES[status] || (status >= 500 ? "internal_error" : "error")
      message = string_or_nil(hash["message"]) || (raw_body.to_s.empty? ? "HTTP #{status}" : raw_body.to_s[0, 500])
      request_id = string_or_nil(hash["request_id"]) || headers["x-request-id"]
      klass = CLASSES[status] || (status >= 500 ? InternalServerError : APIError)
      kwargs = {
        status: status, code: code, reason: string_or_nil(hash["reason"]), request_id: request_id,
        body: body.nil? ? raw_body : body, headers: headers
      }
      kwargs[:retry_after] = retry_after(headers, hash) if klass <= RateLimitError || klass <= ServiceUnavailableError
      klass.new(message, **kwargs)
    end

    def retry_after(headers, hash)
      from_header = parse_retry_after(headers["retry-after"])
      return from_header if from_header
      return hash["retry_after"].to_f if hash["retry_after"].is_a?(Numeric)
      return (hash["retry_after_ms"].to_f / 1000).ceil if hash["retry_after_ms"].is_a?(Numeric)

      nil
    end

    def parse_retry_after(value)
      return nil if value.nil? || value.to_s.strip.empty?

      v = value.to_s.strip
      return v.to_f if v.match?(/\A\d+(\.\d+)?\z/)

      delta = Time.httpdate(v) - Time.now
      delta.negative? ? 0.0 : delta
    rescue ArgumentError
      nil
    end

    def parse_json(raw)
      return nil if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    def string_or_nil(value)
      value.is_a?(String) && !value.empty? ? value : nil
    end
  end
end
