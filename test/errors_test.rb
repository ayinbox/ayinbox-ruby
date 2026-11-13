# frozen_string_literal: true

require_relative "test_helper"

class ErrorsTest < Minitest::Test
  include FixtureHelpers

  CASES = [
    ["400_bad_request.json", 400, Ayinbox::BadRequestError, "bad_request"],
    ["400_invalid_cursor.json", 400, Ayinbox::BadRequestError, "bad_request"],
    ["401_unauthorized.json", 401, Ayinbox::AuthenticationError, "unauthorized"],
    ["401_api_key_holder_left.json", 401, Ayinbox::AuthenticationError, "api_key_holder_left"],
    ["402_insufficient_credits.json", 402, Ayinbox::PaymentRequiredError, "insufficient_credits"],
    ["403_forbidden.json", 403, Ayinbox::PermissionDeniedError, "forbidden"],
    ["403_api_key_mailbox_limited.json", 403, Ayinbox::PermissionDeniedError, "api_key_mailbox_limited"],
    ["404_not_found.json", 404, Ayinbox::NotFoundError, "not_found"],
    ["409_conflict.json", 409, Ayinbox::ConflictError, "conflict"],
    ["409_idempotency_outcome_unknown.json", 409, Ayinbox::ConflictError, "idempotency_outcome_unknown"],
    ["409_idempotent_secret_withheld.json", 409, Ayinbox::ConflictError, "idempotent_secret_withheld"],
    ["422_unprocessable.json", 422, Ayinbox::UnprocessableError, "unprocessable"],
    ["429_api_key_rate_limited.json", 429, Ayinbox::RateLimitError, "rate_limit_exceeded"],
    ["500_internal_error.json", 500, Ayinbox::InternalServerError, "internal_error"],
    ["503_service_unavailable.json", 503, Ayinbox::ServiceUnavailableError, "service_unavailable"]
  ].freeze

  CASES.each do |file, status, klass, code|
    define_method("test_maps_#{file.sub('.json', '')}") do
      stub_request(:get, "#{BASE}/campaigns/x").to_return(error_response(file, status))
      err = assert_raises(klass) { new_client(max_retries: 0).campaigns.get("x") }
      assert_kind_of Ayinbox::APIError, err
      assert_equal status, err.status
      assert_equal code, err.code
      assert_equal "req-fixture-0001", err.request_id
      assert_equal fixture_json("errors/#{file}")["message"], err.message
      refute_includes err.to_s, KEY
    end
  end

  def test_validation_parent_class
    assert Ayinbox::BadRequestError < Ayinbox::InvalidRequestError
    assert Ayinbox::UnprocessableError < Ayinbox::InvalidRequestError
  end

  def test_api_key_rate_limit_reads_retry_after_from_body
    stub_request(:get, "#{BASE}/me").to_return(error_response("429_api_key_rate_limited.json", 429))
    err = assert_raises(Ayinbox::RateLimitError) { new_client(max_retries: 0).me.get }
    assert_equal 12.0, err.retry_after
  end

  def test_category_429_without_code_or_request_id
    stub_request(:get, "#{BASE}/me").to_return(
      status: 429, body: fixture("errors/429_category_rate_limited.json"),
      headers: { "Content-Type" => "application/json", "X-Request-Id" => "req-header-9" }
    )
    err = assert_raises(Ayinbox::RateLimitError) { new_client(max_retries: 0).me.get }
    assert_equal "rate_limit_exceeded", err.code
    assert_equal "req-header-9", err.request_id
    assert_equal 12, err.retry_after
  end

  def test_non_json_body_uses_default_code
    stub_request(:get, "#{BASE}/me").to_return(status: 502, body: "<html>bad gateway</html>")
    err = assert_raises(Ayinbox::InternalServerError) { new_client(max_retries: 0).me.get }
    assert_equal "internal_error", err.code
    assert_equal "<html>bad gateway</html>", err.body
  end

  def test_connection_error
    stub_request(:get, "#{BASE}/me").to_raise(Errno::ECONNREFUSED)
    assert_raises(Ayinbox::APIConnectionError) { new_client(max_retries: 0).me.get }
  end

  def test_timeout_error
    stub_request(:get, "#{BASE}/me").to_timeout
    assert_raises(Ayinbox::TimeoutError) { new_client(max_retries: 0).me.get }
  end
end
