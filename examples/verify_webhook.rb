# frozen_string_literal: true

# Verifies a signed delivery. Run: AYINBOX_WEBHOOK_SECRET=whsec_... ruby -Ilib examples/verify_webhook.rb
require "ayinbox"

secret = ENV.fetch("AYINBOX_WEBHOOK_SECRET", "whsec_test_secret")

# In a real handler these come from the request: the raw body bytes and the X-Ayinbox-Signature header.
raw_body = '{"id":"00000000-0000-4000-8000-000000000001","event_type":"campaign.reply_received",' \
           '"organization_id":"00000000-0000-4000-8000-0000000000aa","created_at":"2023-11-14T22:13:20Z","data":{}}'
timestamp = Time.now.to_i
header = "t=#{timestamp},v1=#{Ayinbox::Webhooks.compute_signature(raw_body, timestamp, secret)}"

begin
  event = Ayinbox::Webhooks.construct_event(raw_body, header, secret)
  puts "Verified #{event['event_type']} (event id #{event['id']})"
rescue Ayinbox::SignatureVerificationError
  warn "Signature did not verify; answer 400 and drop the delivery"
end
