# frozen_string_literal: true

require "erb"

module Ayinbox
  module Resources
    # Shared plumbing for resource classes.
    class Base
      def initialize(client)
        @client = client
      end

      private

      # Splits per-call options (idempotency_key, timeout, headers) from the rest.
      def split_options(opts)
        opts = (opts || {}).each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
        unknown = opts.keys - Client::REQUEST_OPTIONS
        raise ArgumentError, "Unknown request option(s): #{unknown.join(', ')}" unless unknown.empty?

        opts
      end

      def get(path, query = nil, opts = {})
        o = split_options(opts)
        @client.perform("GET", path, query: query, timeout: o[:timeout], headers: o[:headers])
      end

      def write(method, path, body, opts)
        o = split_options(opts)
        @client.perform(method, path, body: body, idempotency_key: o[:idempotency_key],
                                      timeout: o[:timeout], headers: o[:headers])
      end

      def page(method, path, query: nil, body: nil, opts: {})
        o = split_options(opts)
        @client.fetch_page(method, path, query: query, body: body, timeout: o[:timeout], headers: o[:headers])
      end

      def seg(value)
        raise ArgumentError, "id is required" if value.nil? || value.to_s.empty?

        ERB::Util.url_encode(value.to_s)
      end
    end

    # GET /me
    class Me < Base
      # The identity behind the credential. Needs no scope.
      def get(opts = {})
        super("/me", nil, opts)
      end
    end

    # /campaigns
    class Campaigns < Base
      # One page of campaigns. params: q, status, folder, cursor, limit.
      def list(params = {}, opts = {})
        page("GET", "/campaigns", query: params, opts: opts)
      end

      def get(id, opts = {})
        super("/campaigns/#{seg(id)}", nil, opts)
      end

      # Creates a draft campaign. Never sends mail.
      def create(params, opts = {})
        write("POST", "/campaigns", params, opts)
      end

      # Pauses an active campaign (POST /campaigns/{id}/stop). Sends nothing.
      def pause(id, opts = {})
        write("POST", "/campaigns/#{seg(id)}/stop", nil, opts)
      end
    end

    # /contacts
    class Contacts < Base
      QUERY_KEYS = %w[cursor limit category].freeze

      # One page of contacts (POST /contacts/search). cursor, limit and category go in the
      # query string; every other key is a search filter sent as the body.
      def list(params = {}, opts = {})
        query = {}
        body = {}
        (params || {}).each do |k, v|
          QUERY_KEYS.include?(k.to_s) ? query[k.to_s] = v : body[k.to_s] = v
        end
        page("POST", "/contacts/search", query: query, body: body, opts: opts)
      end

      def get(id, opts = {})
        super("/contacts/#{seg(id)}", nil, opts)
      end

      # Upserts one contact (a Hash) or many (an Array). Always returns an Array.
      def create(contact_or_contacts, opts = {})
        write("POST", "/contacts", contact_or_contacts, opts)
      end

      def update(id, params, opts = {})
        write("PATCH", "/contacts/#{seg(id)}", params, opts)
      end

      # Returns nil (204).
      def delete(id, opts = {})
        write("DELETE", "/contacts/#{seg(id)}", nil, opts)
      end
    end

    # /emails
    class Mailboxes < Base
      # One page of mailboxes. params: q, tag, cursor, limit.
      def list(params = {}, opts = {})
        page("GET", "/emails", query: params, opts: opts)
      end
    end

    # /unibox
    class Unibox < Base
      # One page of conversations, newest message per thread. params: see the API reference.
      def list_threads(params = {}, opts = {})
        page("GET", "/unibox", query: params, opts: opts)
      end

      # One page of a thread's messages. params: email_id, limit, cursor.
      def get_thread(thread_id, params = {}, opts = {})
        raise ArgumentError, "thread_id is required" if thread_id.nil? || thread_id.to_s.empty?

        query = { "thread_id" => thread_id.to_s }
        (params || {}).each { |k, v| query[k.to_s] = v }
        page("GET", "/unibox/thread", query: query, opts: opts)
      end
    end
  end
end
