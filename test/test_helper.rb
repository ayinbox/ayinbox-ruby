# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ayinbox"
require "minitest/autorun"
require "webmock/minitest"

WebMock.disable_net_connect!

module FixtureHelpers
  BASE = "https://api.test/v1"
  KEY = "aybox_test_0000000000000000000000000000000000000000000"
  FIXTURES = File.expand_path("fixtures", __dir__)
  JSON_HEADERS = { "Content-Type" => "application/json; charset=utf-8", "X-Request-Id" => "req-fixture-0001" }.freeze

  def fixture(name)
    File.read(File.join(FIXTURES, name))
  end

  def fixture_json(name)
    JSON.parse(fixture(name))
  end

  def ok(name, status: 200)
    { status: status, body: fixture(name), headers: JSON_HEADERS }
  end

  def error_response(file, status, headers = {})
    { status: status, body: fixture("errors/#{file}"), headers: JSON_HEADERS.merge(headers) }
  end

  def new_client(**kwargs)
    @sleeps = []
    Ayinbox::Client.new(api_key: KEY, base_url: BASE, sleeper: ->(s) { @sleeps << s }, **kwargs)
  end
end
