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

Use the repository's `deploy-testflight` and `bump-version` skills for releases. Simulator verification must use `xcodebuildmcp`.
