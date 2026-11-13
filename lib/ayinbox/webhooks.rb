# frozen_string_literal: true

require "json"
require "openssl"

module Ayinbox
  # Verifies the X-Ayinbox-Signature header on webhook deliveries.
  module Webhooks
    SIGNATURE_HEADER = "X-Ayinbox-Signature"
    DEFAULT_TOLERANCE = 300

    module_function

    # True when the header carries a valid v1 signature of payload within the tolerance.
    # payload must be the raw request body, before any JSON parsing.
    def verify_signature(payload, header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
      return false if header.nil? || secret.nil? || secret.to_s.empty?

      timestamp, signatures = parse_header(header.to_s)
      return false if timestamp.nil? || signatures.empty?
      return false if tolerance.to_i <= 0 || (now.to_i - timestamp).abs > tolerance.to_i

      expected = compute_signature(payload, timestamp, secret)
      signatures.any? { |sig| secure_equal?(expected, sig) }
    end

    # Verifies, then parses the payload. Raises SignatureVerificationError when it does not verify.
    def construct_event(payload, header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
      unless verify_signature(payload, header, secret, tolerance: tolerance, now: now)
        raise SignatureVerificationError, "Webhook signature did not verify"
      end

      JSON.parse(payload.to_s)
    end

    # Lowercase hex HMAC-SHA256 of "<timestamp>.<payload>" keyed with the whole secret, whsec_ prefix included.
    def compute_signature(payload, timestamp, secret)
      body = payload.to_s.dup.force_encoding(Encoding::BINARY)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "#{timestamp}.".b + body)
    end

    def parse_header(header)
      timestamp = nil
      signatures = []
      header.split(",").each do |part|
        key, value = part.strip.split("=", 2)
        next if value.nil?

        case key
        when "t" then timestamp = Integer(value, 10) if value.match?(/\A\d+\z/)
        when "v1" then signatures << value
        end
      end
      [timestamp, signatures]
    end

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize

      result = 0
      left.bytes.zip(right.bytes) { |a, b| result |= a ^ b }
      result.zero?
    end
  end
end
