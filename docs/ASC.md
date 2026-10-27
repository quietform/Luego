# App Store Connect CLI

Luego's App Store Connect app ID is `6755436648`, with bundle ID `com.esoxjem.Luego`.

Local `.asc/config.json` sets the default app and selects the existing `app-store-connect` Keychain profile, which has access to Luego. The config is ignored by Git and has mode `0600`; private key material stays in macOS Keychain.

Run from this repository:

```bash
asc auth doctor
asc status --platform IOS --output table
asc builds list --platform IOS --limit 5 --sort -uploadedDate --output table
```

On another checkout, run `asc auth init --local`, then set `app_id` to `6755436648` and `default_key_name` to the name of an authenticated Keychain profile with access to Luego. Register credentials with `asc auth login` when needed; discover flags with `--help`.

TestFlight has two groups: `Friends-Internal` receives every build automatically, and `External-Testers` (with a public link) receives each build after beta app review.

For App Store releases, stage the version with `asc release stage --copy-metadata-from PREVIOUS_VERSION --exclude-fields whatsNew`, then write fresh release notes. New versions start with empty App Review contact details; copy them from `asc testflight review view` into `asc review details-update`. Run `asc validate` before `asc review submit`. Versions release automatically after approval.

Use the repository's `deploy-testflight` and `bump-version` skills for releases. Follow the [simulator verification policy](TESTING.md#simulator-verification), using `xcodebuildmcp` and one relevant simulator by default. Release preparation alone does not require duplicate iPhone and iPad checks.
