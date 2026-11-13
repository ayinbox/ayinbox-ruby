# frozen_string_literal: true

require_relative "lib/ayinbox/version"

Gem::Specification.new do |spec|
  spec.name = "ayinbox"
  spec.version = Ayinbox::VERSION
  spec.authors = ["AY Inbox"]
  spec.email = ["team@ayinbox.com"]
  spec.summary = "Ruby client for the AY Inbox REST API"
  spec.description = "Official Ruby client for the AY Inbox REST API: campaigns, contacts, mailboxes, " \
                     "the Unibox, typed errors, retries, pagination and webhook signature verification."
  spec.homepage = "https://github.com/ayinbox/ayinbox-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://docs.ayinbox.com/api/",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]
end
