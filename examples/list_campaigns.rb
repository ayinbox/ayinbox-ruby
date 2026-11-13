# frozen_string_literal: true

# Lists every campaign. Run: AYINBOX_API_KEY=aybox_... ruby -Ilib examples/list_campaigns.rb
require "ayinbox"

client = Ayinbox::Client.new
me = client.me.get
puts "Signed in as #{me['email']} (#{me['organization_name']})"

client.campaigns.list(limit: 50).auto_paging_each do |campaign|
  puts "#{campaign['id']}  #{campaign['status'].ljust(10)}  #{campaign['name']}"
end
