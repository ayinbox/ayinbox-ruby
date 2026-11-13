# frozen_string_literal: true

require_relative "test_helper"

class RetryTest < Minitest::Test
  include FixtureHelpers

  def test_retries_503_then_succeeds
    stub_request(:get, "#{BASE}/me")
      .to_return(error_response("503_service_unavailable.json", 503))
      .then.to_return(ok("me.json"))
    client = new_client
    assert_equal fixture_json("me.json")["user_id"], client.me.get["user_id"]
    assert_equal 1, @sleeps.size
    assert_operator @sleeps.first, :<=, 0.5
  end

  def test_retries_429_honouring_retry_after
    stub_request(:get, "#{BASE}/campaigns/x")
      .to_return(error_response("429_api_key_rate_limited.json", 429, "Retry-After" => "3"))
      .then.to_return(ok("campaign.json"))
    client = new_client
    client.campaigns.get("x")
    assert_equal [3.0], @sleeps
  end

  def test_retry_after_is_capped
    stub_request(:get, "#{BASE}/me")
      .to_return(error_response("429_api_key_rate_limited.json", 429, "Retry-After" => "9999"))
      .then.to_return(ok("me.json"))
    client = new_client
    client.me.get
    assert_equal [120.0], @sleeps
  end

  def test_gives_up_after_max_retries
    stub = stub_request(:get, "#{BASE}/me").to_return(error_response("503_service_unavailable.json", 503))
    assert_raises(Ayinbox::ServiceUnavailableError) { new_client(max_retries: 2).me.get }
    assert_requested stub, times: 3
  end

  def test_does_not_retry_500
    stub = stub_request(:get, "#{BASE}/me").to_return(error_response("500_internal_error.json", 500))
    assert_raises(Ayinbox::InternalServerError) { new_client.me.get }
    assert_requested stub, times: 1
  end

  def test_no_retry_of_keyless_post_on_503
    stub = stub_request(:post, "#{BASE}/campaigns").to_return(error_response("503_service_unavailable.json", 503))
    assert_raises(Ayinbox::ServiceUnavailableError) { new_client.campaigns.create({ name: "Q4" }) }
    assert_requested stub, times: 1
  end

  def test_no_retry_of_keyless_post_on_connection_error
    stub = stub_request(:post, "#{BASE}/contacts").to_raise(Errno::ECONNRESET)
    assert_raises(Ayinbox::APIConnectionError) { new_client.contacts.create({ email: "a@example.com" }) }
    assert_requested stub, times: 1
  end

  def test_keyless_post_is_retried_on_429
    stub = stub_request(:post, "#{BASE}/campaigns")
           .to_return(error_response("429_category_rate_limited.json", 429))
           .then.to_return(ok("campaign.json"))
    new_client.campaigns.create({ name: "Q4" })
    assert_requested stub, times: 2
    assert_equal [12.0], @sleeps
  end

  def test_post_with_key_is_retried_with_same_key
    stub = stub_request(:post, "#{BASE}/campaigns")
           .with(headers: { "Idempotency-Key" => "create-q4" })
           .to_return(error_response("503_service_unavailable.json", 503))
           .then.to_return(ok("campaign.json"))
    new_client.campaigns.create({ name: "Q4" }, idempotency_key: "create-q4")
    assert_requested stub, times: 2
  end

  def test_never_retries_idempotency_outcome_unknown
    stub = stub_request(:post, "#{BASE}/campaigns")
           .to_return(error_response("409_idempotency_outcome_unknown.json", 409))
    assert_raises(Ayinbox::ConflictError) { new_client.campaigns.create({ name: "Q4" }, idempotency_key: "k") }
    assert_requested stub, times: 1
  end

  def test_read_only_search_post_is_retried_without_key
    stub = stub_request(:post, "#{BASE}/contacts/search")
           .to_return(error_response("503_service_unavailable.json", 503))
           .then.to_return(ok("contacts_list.json"))
    new_client.contacts.list
    assert_requested stub, times: 2
  end

  def test_max_retries_zero_disables
    stub = stub_request(:get, "#{BASE}/me").to_return(error_response("503_service_unavailable.json", 503))
    assert_raises(Ayinbox::ServiceUnavailableError) { new_client(max_retries: 0).me.get }
    assert_requested stub, times: 1
  end
end
