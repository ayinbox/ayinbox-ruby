# frozen_string_literal: true

require_relative "test_helper"

class ResourcesTest < Minitest::Test
  include FixtureHelpers

  CAMPAIGN_ID = "11111111-1111-4111-8111-222222222222"
  CONTACT_ID = "22222222-2222-4222-8222-111111111111"

  def test_campaigns_list_returns_page
    stub_request(:get, "#{BASE}/campaigns?status=active&limit=2").to_return(ok("campaigns_list.json"))
    page = new_client.campaigns.list(status: "active", limit: 2)
    assert_kind_of Ayinbox::Page, page
    assert_equal 2, page.data.size
    assert page.has_more?
    assert_equal "c1_ZmFrZS1jdXJzb3ItcGFnZS0y", page.next_cursor
    assert_equal 3, page.total
  end

  def test_auto_paging_walks_two_pages
    stub_request(:get, "#{BASE}/campaigns?status=active").to_return(ok("campaigns_list.json"))
    page2 = stub_request(:get, "#{BASE}/campaigns?status=active&cursor=c1_ZmFrZS1jdXJzb3ItcGFnZS0y")
            .to_return(ok("campaigns_list_page2.json"))
    ids = new_client.campaigns.list(status: "active").auto_paging_each.map { |c| c["id"] }
    expected = fixture_json("campaigns_list.json")["data"].map { |c| c["id"] } +
               fixture_json("campaigns_list_page2.json")["data"].map { |c| c["id"] }
    assert_equal expected, ids
    assert_requested page2, times: 1
  end

  def test_generic_paginate
    stub_request(:get, "#{BASE}/campaigns").to_return(ok("campaigns_list.json"))
    stub_request(:get, "#{BASE}/campaigns?cursor=c1_ZmFrZS1jdXJzb3ItcGFnZS0y")
      .to_return(ok("campaigns_list_page2.json"))
    enum = new_client.paginate("GET", "/campaigns")
    assert_kind_of Enumerator, enum
    assert_equal 3, enum.to_a.size
  end

  def test_campaigns_get
    stub_request(:get, "#{BASE}/campaigns/#{CAMPAIGN_ID}").to_return(ok("campaign.json"))
    assert_equal fixture_json("campaign.json")["name"], new_client.campaigns.get(CAMPAIGN_ID)["name"]
  end

  def test_campaigns_create_sends_idempotency_key
    stub = stub_request(:post, "#{BASE}/campaigns")
           .with(body: { "name" => "Q4 outbound" }, headers: { "Idempotency-Key" => "create-q4" })
           .to_return(ok("campaign.json"))
    new_client.campaigns.create({ name: "Q4 outbound" }, idempotency_key: "create-q4")
    assert_requested stub
  end

  def test_campaigns_create_without_key_sends_no_header
    stub_request(:post, "#{BASE}/campaigns").to_return(ok("campaign.json"))
    new_client.campaigns.create(name: "Q4")
    assert_requested(:post, "#{BASE}/campaigns") { |req| !req.headers.key?("Idempotency-Key") }
  end

  def test_campaigns_pause
    stub_request(:post, "#{BASE}/campaigns/#{CAMPAIGN_ID}/stop").to_return(ok("campaign_stop.json"))
    assert_equal "stopped", new_client.campaigns.pause(CAMPAIGN_ID)["status"]
  end

  def test_contacts_list_splits_query_and_body_and_resends_body
    first = stub_request(:post, "#{BASE}/contacts/search?limit=1")
            .with(body: { "query" => "lee", "sort_by" => "email" })
            .to_return(status: 200, headers: JSON_HEADERS,
                       body: JSON.generate("data" => [{ "id" => "a" }],
                                           "pagination" => { "next_cursor" => "c1_n", "has_more" => true }))
    second = stub_request(:post, "#{BASE}/contacts/search?limit=1&cursor=c1_n")
             .with(body: { "query" => "lee", "sort_by" => "email" })
             .to_return(ok("contacts_list.json"))
    rows = new_client.contacts.list(query: "lee", sort_by: "email", limit: 1).auto_paging_each.to_a
    assert_requested first
    assert_requested second
    assert_equal 1 + fixture_json("contacts_list.json")["data"].size, rows.size
  end

  def test_contacts_list_exposes_counts
    stub_request(:post, "#{BASE}/contacts/search").to_return(ok("contacts_list.json"))
    page = new_client.contacts.list
    assert_equal fixture_json("contacts_list.json")["counts"], page["counts"]
  end

  def test_contacts_get
    stub_request(:get, "#{BASE}/contacts/#{CONTACT_ID}").to_return(ok("contact.json"))
    assert_equal fixture_json("contact.json")["email"], new_client.contacts.get(CONTACT_ID)["email"]
  end

  def test_contacts_create_returns_array
    stub = stub_request(:post, "#{BASE}/contacts")
           .with(body: { "email" => "lee@example.com" }, headers: { "Idempotency-Key" => "lee-1" })
           .to_return(ok("contacts_create.json"))
    out = new_client.contacts.create({ email: "lee@example.com" }, idempotency_key: "lee-1")
    assert_requested stub
    assert_kind_of Array, out
    assert_equal "lee@example.com", out.first["email"]
  end

  def test_contacts_update
    stub = stub_request(:patch, "#{BASE}/contacts/#{CONTACT_ID}")
           .with(body: { "company" => "New Co" }).to_return(ok("contact.json"))
    new_client.contacts.update(CONTACT_ID, { company: "New Co" })
    assert_requested stub
  end

  def test_contacts_delete
    stub = stub_request(:delete, "#{BASE}/contacts/#{CONTACT_ID}")
           .with(headers: { "Idempotency-Key" => "del-1" }).to_return(status: 204)
    assert_nil new_client.contacts.delete(CONTACT_ID, idempotency_key: "del-1")
    assert_requested stub
  end

  def test_mailboxes_list
    stub_request(:get, "#{BASE}/emails?q=sales").to_return(ok("mailboxes_list.json"))
    page = new_client.mailboxes.list(q: "sales")
    assert_equal 2, page.data.size
    refute page.has_more?
    assert_nil page.next_page
  end

  def test_unibox_list_threads
    stub_request(:get, "#{BASE}/unibox?folder=inbox&unseen=true").to_return(ok("unibox_threads.json"))
    page = new_client.unibox.list_threads(folder: "inbox", unseen: true)
    assert page.has_more?
    assert_equal fixture_json("unibox_threads.json")["data"].first["thread_id"], page.data.first["thread_id"]
  end

  def test_unibox_get_thread
    stub_request(:get, "#{BASE}/unibox/thread?thread_id=t-1&email_id=e-1").to_return(ok("unibox_thread.json"))
    page = new_client.unibox.get_thread("t-1", email_id: "e-1")
    assert_equal 2, page.data.size
  end

  def test_unknown_response_fields_are_kept_not_rejected
    stub_request(:get, "#{BASE}/me").to_return(status: 200, headers: JSON_HEADERS,
                                               body: '{"user_id":"u","brand_new_field":{"x":1}}')
    assert_equal({ "x" => 1 }, new_client.me.get["brand_new_field"])
  end
end
