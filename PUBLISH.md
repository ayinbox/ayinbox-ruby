# Publishing the gem

The gem is published to RubyGems by `.github/workflows/release.yml` when a `v*` tag is pushed. It uses RubyGems trusted publishing (OIDC): no API key is stored in GitHub.

## One-time setup

1. Sign in to https://rubygems.org with the account that will own `ayinbox` (create it with team@ayinbox.com if needed) and turn on multi-factor authentication. The gemspec sets `rubygems_mfa_required`.
2. The gem name `ayinbox` does not exist yet, so add a pending trusted publisher: go to https://rubygems.org/profile/oidc/pending_trusted_publishers, choose "Create", and enter:
   - Gem name: `ayinbox`
   - Repository owner: `ayinbox`
   - Repository name: `ayinbox-ruby`
   - Workflow filename: `release.yml`
   - Environment: `release`
3. In GitHub, open `ayinbox/ayinbox-ruby` > Settings > Environments, create an environment named `release`, and (optionally) add required reviewers so a tag cannot publish without approval.
4. After the first release, add other owners with `gem owner ayinbox --add <email>` if needed. The pending publisher becomes a normal trusted publisher on first use.

## Releasing

1. Update `lib/ayinbox/version.rb` and `CHANGELOG.md`, commit to `main`, and wait for CI to pass.
2. Tag and push:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

The workflow checks that the tag matches `Ayinbox::VERSION`, runs the tests, builds the gem and pushes it to RubyGems (`rake release` through `rubygems/release-gem`).

After the first publish, change the README install section from the GitHub form to `gem install ayinbox` / `gem "ayinbox"`.
