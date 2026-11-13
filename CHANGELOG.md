# Changelog

## 0.1.0 (unreleased)

- First release.
- `Ayinbox::Client` with API key from `AYINBOX_API_KEY`, base URL override, timeout, retries and an injectable transport.
- Methods: `me.get`, `campaigns.list`, `campaigns.get`, `campaigns.create`, `campaigns.pause`, `contacts.list`, `contacts.get`, `contacts.create`, `contacts.update`, `contacts.delete`, `mailboxes.list`, `unibox.list_threads`, `unibox.get_thread`.
- Generic `request` and `paginate`, `Page#auto_paging_each`.
- Typed errors, retries with backoff that honour `Retry-After`, per-call idempotency keys.
- `Ayinbox::Webhooks.verify_signature` and `construct_event`.
