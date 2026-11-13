# AY Inbox Ruby library

The official Ruby client for the [AY Inbox](https://ayinbox.com) REST API. AY Inbox is a hosted cold email platform: it sends cold email at a paced daily volume, brings every reply into one inbox (Unibox), drafts answers from a per-campaign brain, and can offer a meeting time.

AY Inbox is a hosted service. This repository holds the Ruby client library for its public API. The service itself is not open source.

Access to the hosted service is invite only for now: ask at team@ayinbox.com.

## Install

Not on RubyGems yet. Until it is, install from GitHub with Bundler:

```ruby
# Gemfile
gem "ayinbox", git: "https://github.com/ayinbox/ayinbox-ruby"
```

Then run `bundle install`. Requires Ruby 3.1 or later. The library has no runtime dependencies beyond the standard library (`net/http`, `json`, `openssl`).

## Quick start

```ruby
require "ayinbox"

client = Ayinbox::Client.new # reads AYINBOX_API_KEY

me = client.me.get
puts "Signed in as #{me['email']}"

client.campaigns.list(status: "active").auto_paging_each do |campaign|
  puts "#{campaign['name']}: #{campaign['status']}"
end

begin
  contacts = client.contacts.create(
    { email: "lee@example.com", first_name: "Lee", company: "Example Co" },
    idempotency_key: "import-lee-2026-11-13"
  )
  puts "Saved #{contacts.first['id']}"
rescue Ayinbox::PermissionDeniedError => e
  warn "Missing scope: #{e.code} (request #{e.request_id})"
end
```

Responses are plain Hashes with string keys, exactly as the API sends them. Fields the library does not know about are kept, never rejected.

## Client options

```ruby
client = Ayinbox::Client.new(
  api_key: "aybox_...",                      # default: ENV["AYINBOX_API_KEY"]
  base_url: "https://api.ayinbox.com/v1",    # default, or ENV["AYINBOX_BASE_URL"]
  timeout: 30,                               # seconds, per attempt
  max_retries: 2,                            # 0 disables retries
  transport: MyTransport.new                 # optional, see below
)
```

API keys start with `aybox_` and OAuth access tokens with `ayat_`; both work as `api_key`. The key is sent as `Authorization: Bearer <key>` and never appears in `inspect` output or error messages.

`transport` is any object with `call(method, uri, headers, body, timeout)` returning `[status, headers, body]`. The default uses `Net::HTTP`.

Every method takes per-call options as a trailing Hash: `idempotency_key:`, `timeout:` and `headers:` (for example `{ "X-Request-Id" => "my-trace-id" }`).

## Resources

| Resource | Method | HTTP |
|---|---|---|
| `me` | `get` | `GET /me` |
| `campaigns` | `list(params)` | `GET /campaigns` |
| | `get(id)` | `GET /campaigns/{id}` |
| | `create(params)` | `POST /campaigns` |
| | `pause(id)` | `POST /campaigns/{id}/stop` |
| `contacts` | `list(params)` | `POST /contacts/search` |
| | `get(id)` | `GET /contacts/{id}` |
| | `create(contact_or_array)` | `POST /contacts` |
| | `update(id, params)` | `PATCH /contacts/{id}` |
| | `delete(id)` | `DELETE /contacts/{id}` |
| `mailboxes` | `list(params)` | `GET /emails` |
| `unibox` | `list_threads(params)` | `GET /unibox` |
| | `get_thread(thread_id, params)` | `GET /unibox/thread` |
| `Ayinbox::Webhooks` | `verify_signature`, `construct_event` | local, no HTTP |

For `contacts.list`, the keys `cursor`, `limit` and `category` go in the query string and every other key (`query`, `campaign_ids`, `sort_by`, `reverse` and the rest) is sent as the search body. `contacts.create` always returns an Array, even for one contact.

Every other route is reachable through `request`:

```ruby
client.request("GET", "/campaigns-overview")
client.request("POST", "/suppressions",
               body: { entries: [{ value: "competitor.example" }] },
               idempotency_key: "suppress-competitor")
```

`request(method, path, query:, body:, idempotency_key:, headers:, timeout:)` goes through the same authentication, retries and error mapping, and returns the decoded JSON, `nil` for an empty body, or the raw String for a non-JSON answer.

## Pagination

List methods return an `Ayinbox::Page` with `data`, `next_cursor`, `has_more?`, `total` (when the endpoint sends it) and `next_page`. Other top-level fields are read with `page["counts"]`.

`auto_paging_each` walks every page lazily, passing the cursor back unchanged. Without a block it returns an `Enumerator`:

```ruby
emails = client.contacts.list(campaign_ids: [campaign_id]).auto_paging_each.map { |c| c["email"] }

client.paginate("GET", "/suppressions", query: { limit: 200 }) { |row| puts row["email"] }
```

`paginate` works with any route that answers with `data` and `pagination`. For a search, the same body is sent on every page, as the API requires. Use `limit` between 1 and 100.

## Errors

Every error inherits from `Ayinbox::Error`. Answers with a non-2xx status raise a subclass of `Ayinbox::APIError`, which carries `status`, `code`, `message`, `reason`, `request_id`, `body` and `headers`. Branch on `code` and the class, never on `message`.

| Class | Status |
|---|---|
| `BadRequestError` (under `InvalidRequestError`) | 400 |
| `AuthenticationError` | 401 |
| `PaymentRequiredError` | 402 |
| `PermissionDeniedError` | 403 |
| `NotFoundError` | 404 |
| `ConflictError` | 409 |
| `UnprocessableError` (under `InvalidRequestError`) | 422 |
| `RateLimitError` (has `retry_after` seconds) | 429 |
| `InternalServerError` (under `ServerError`) | 500 and other 5xx |
| `ServiceUnavailableError` (under `ServerError`, has `retry_after`) | 503 |
| `APIConnectionError`, `TimeoutError` | no answer |

## Retries and timeouts

The client retries `429`, `502`, `503`, `504`, connection failures and timeouts, up to `max_retries` times (default 2, so three attempts). It waits for `Retry-After` when the server sends one (capped at 120 seconds), otherwise exponential backoff with full jitter (base 0.5 seconds, cap 8 seconds).

A `POST` or `PATCH` without an idempotency key is retried only on `429`, which the server never ran. A `500` is never retried, and neither is `409 idempotency_outcome_unknown`. `contacts.list` is a read even though it is a `POST`, so it is retried like a `GET`.

`timeout` applies to each attempt; pass `timeout:` per call to override it.

## Idempotency

Every mutating method accepts `idempotency_key:` and sends it as the `Idempotency-Key` header. The library does not generate keys for you: pass one on any write you might retry, and the client reuses it on every automatic retry of that call. The server keeps the result for 24 hours and replays it for the same key and the same request. The same key with a different request answers `409 conflict`; a first attempt that never finished answers `409 idempotency_outcome_unknown`, and you should check whether the change happened before retrying with a new key.

## Webhooks

Each delivery carries `X-Ayinbox-Signature: t=<unix-seconds>,v1=<hex>`. Verify it against the raw request body, before any JSON parsing:

```ruby
secret = ENV.fetch("AYINBOX_WEBHOOK_SECRET") # whsec_..., shown once when the endpoint is created
raw = request.body.read
header = request.get_header("HTTP_X_AYINBOX_SIGNATURE")

event = Ayinbox::Webhooks.construct_event(raw, header, secret) # raises SignatureVerificationError
# or: Ayinbox::Webhooks.verify_signature(raw, header, secret) => true / false
```

The default tolerance is 300 seconds (`tolerance:` changes it). The comparison is constant time. Use `X-Ayinbox-Event-Id` (also `event["id"]`) to drop duplicate deliveries.

## Calls that send email

- These calls put real email on the wire:
  - `campaigns.start` (`POST /campaigns/{id}/start`): needs `START_CAMPAIGNS` or `SEND_CAMPAIGNS`.
  - `campaigns.update` with `status: "active"` (and `completed` or `paused_undeliverable`): needs `START_CAMPAIGNS` or `SEND_CAMPAIGNS` in addition to `WRITE_CAMPAIGNS`.
  - `campaigns.leads.resume` on a finished campaign: needs `START_CAMPAIGNS` or `SEND_CAMPAIGNS`.
  - `unibox.reply` and `unibox.approveAgentDraft`: need `WRITE_UNIBOX`. A key with `WRITE_UNIBOX` can send replies from any mailbox it can reach.
  - Through `request`: `POST /unibox/compose`, `POST /emails/{id}/send`, `POST /campaigns/{id}/test-email`, the first-email review queue (`/campaigns/{id}/reviews/...`), placement tests: `SEND_CAMPAIGNS` (compose: `WRITE_UNIBOX`).

  In this library, all of those are reached through `request`. The named methods here never send: `campaigns.create` makes a draft and `campaigns.pause` stops sending.
- Adding contacts can send mail without calling start: contacts added to an `active` campaign are queued; a `completed` campaign starts again on its own when leads are added; a contact that comes to match a segment linked to a sending campaign is enrolled. That includes `contacts.create` and `contacts.update` with `campaigns`.
- `START_CAMPAIGNS` starts, resumes and pauses campaigns and nothing else. `SEND_CAMPAIGNS` covers everything `START_CAMPAIGNS` covers plus the other sending actions. `WRITE_CAMPAIGNS` alone edits drafts and pauses, and cannot start anything.
- A key for a model that reads the inbox should use the "Agent: read and draft" preset (84574239): every read scope plus `AI_DRAFT`, with nothing that writes or sends.
- Some calls spend workspace credits (AI drafts, research, enrichment, paid tools). They answer `402 insufficient_credits` when the balance is out.
- Retrying a send without an idempotency key can send twice. Pass an idempotency key on every mutating call you might retry.

## Examples

- [`examples/list_campaigns.rb`](examples/list_campaigns.rb): sign in and list every campaign.
- [`examples/verify_webhook.rb`](examples/verify_webhook.rb): verify a signed delivery.

## Development

```sh
bundle config set --local path vendor/bundle
bundle install
bundle exec rake test
bundle exec rubocop
```

The tests run against WebMock stubs fed from `test/fixtures/`. They make no network calls and use no real key.

## Documentation

- API reference: https://docs.ayinbox.com/api/
- Authentication and scopes: https://docs.ayinbox.com/api/authentication/
- Errors: https://docs.ayinbox.com/api/error-codes/

## License

MIT. See [LICENSE](LICENSE).
