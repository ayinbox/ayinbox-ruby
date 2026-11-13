# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  include FixtureHelpers

  def test_sends_auth_user_agent_and_accept
    stub = stub_request(:get, "#{BASE}/me")
           .with(headers: { "Authorization" => "Bearer #{KEY}", "User-Agent" => "ayinbox-ruby/#{Ayinbox::VERSION}",
                            "Accept" => "application/json" })
           .to_return(ok("me.json"))
    me = new_client.me.get
    assert_requested stub
    assert_equal fixture_json("me.json")["email"], me["email"]
  end

  def test_reads_key_and_base_url_from_env
    ENV["AYINBOX_API_KEY"] = "aybox_from_env"
    ENV["AYINBOX_BASE_URL"] = "https://env.test/v1/"
    stub = stub_request(:get, "https://env.test/v1/me")
           .with(headers: { "Authorization" => "Bearer aybox_from_env" }).to_return(ok("me.json"))
    client = Ayinbox::Client.new
    assert_equal "https://env.test/v1", client.base_url
    client.me.get
    assert_requested stub
  ensure
    ENV.delete("AYINBOX_API_KEY")
    ENV.delete("AYINBOX_BASE_URL")
  end

  def test_missing_key_raises
    ENV.delete("AYINBOX_API_KEY")
    assert_raises(Ayinbox::ConfigurationError) { Ayinbox::Client.new }
  end

  def test_inspect_redacts_key
    refute_includes new_client.inspect, KEY
  end

  def test_generic_request_with_query_body_and_headers
    stub = stub_request(:post, "#{BASE}/suppressions?x=1")
           .with(body: { "entries" => [{ "value" => "a@example.com" }] },
                 headers: { "Idempotency-Key" => "k1", "X-Request-Id" => "mine", "Content-Type" => "application/json" })
           .to_return(status: 200, body: '{"added":1,"skipped":[]}', headers: JSON_HEADERS)
    out = new_client.request("POST", "/suppressions", query: { x: 1 }, body: { entries: [{ value: "a@example.com" }] },
                                                      idempotency_key: "k1", headers: { "X-Request-Id" => "mine" })
    assert_requested stub
    assert_equal 1, out["added"]
  end

  def test_empty_body_returns_nil
    stub_request(:delete, "#{BASE}/contacts/abc").to_return(status: 204, body: "")
    assert_nil new_client.contacts.delete("abc")
  end

  def test_unknown_request_option_raises
    assert_raises(ArgumentError) { new_client.me.get(bogus: 1) }
  end
end
