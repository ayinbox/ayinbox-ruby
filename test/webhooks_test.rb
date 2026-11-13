# frozen_string_literal: true

require_relative "test_helper"

class WebhooksTest < Minitest::Test
  include FixtureHelpers

  def setup
    @v = fixture_json("webhook_signature.json")
  end

  def verify(body: @v["body"], header: @v["header"], secret: @v["secret"], now: @v["timestamp"], **kw)
    Ayinbox::Webhooks.verify_signature(body, header, secret, now: now, **kw)
  end

  def test_computes_expected_signature
    assert_equal @v["expected_v1"], Ayinbox::Webhooks.compute_signature(@v["body"], @v["timestamp"], @v["secret"])
  end

  def test_valid_vector
    assert verify
  end

  def test_tampered_body
    refute verify(body: @v["body"].sub("reply_received", "reply_receivee"))
  end

  def test_wrong_secret
    refute verify(secret: "whsec_other")
  end

  def test_outside_tolerance
    refute verify(now: @v["timestamp"] + 301)
    assert verify(now: @v["timestamp"] + 300)
  end

  def test_missing_parts
    refute verify(header: "v1=#{@v['expected_v1']}")
    refute verify(header: "t=#{@v['timestamp']}")
    refute verify(header: nil)
  end

  def test_any_of_several_v1_passes
    assert verify(header: "t=#{@v['timestamp']},v1=deadbeef,v0=x,v1=#{@v['expected_v1']}")
  end

  def test_construct_event
    event = Ayinbox::Webhooks.construct_event(@v["body"], @v["header"], @v["secret"], now: @v["timestamp"])
    assert_equal "campaign.reply_received", event["event_type"]
    assert_raises(Ayinbox::SignatureVerificationError) do
      Ayinbox::Webhooks.construct_event(@v["body"], @v["header"], "whsec_other", now: @v["timestamp"])
    end
  end

  def test_client_exposes_webhooks
    assert_equal Ayinbox::Webhooks, new_client.webhooks
  end
end
