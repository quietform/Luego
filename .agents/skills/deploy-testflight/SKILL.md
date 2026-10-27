---
name: deploy-testflight
description: iOS TestFlight deployment workflow for Luego using Xcode-managed signing, simulator verification, archive/export upload, tester-group distribution, and CalVer build coordination. Use when archiving and uploading Luego iOS builds to TestFlight, troubleshooting Apple account or provisioning issues, or fixing duplicate build-number rejections by updating `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
---

# deploy-testflight

Ship Luego iOS builds to TestFlight with Xcode-managed signing and Xcode-authenticated upload.

## Workflow

1. Run preflight checks.
   - Confirm the checkout is the Luego repo root and the `Luego` scheme resolves.
   - Confirm Xcode is signed into the correct Apple Developer account and can access the expected team.
   - Confirm automatic signing resolves for both the app target and the share extension target.
   - Verify the current version/build values:
     ```bash
     grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION|CODE_SIGN_STYLE|DEVELOPMENT_TEAM" Luego.xcodeproj/project.pbxproj | head -12
     ```
   - Verify the app on the simulator before archiving:
     ```bash
     xcodebuildmcp simulator build --use-latest-os
     xcodebuildmcp simulator build-and-run --use-latest-os
     ```
2. Update version metadata before archiving.
   - Follow the `$bump-version` policy.
   - For same-day reuploads, increment only `CURRENT_PROJECT_VERSION`.
   - When the version date changes, set `MARKETING_VERSION` to `YYYY.MM.DD` and reset `CURRENT_PROJECT_VERSION` to `1`.
   - Keep `Luego`, `LuegoShareExtension`, and `LuegoTests` in sync in `Luego.xcodeproj/project.pbxproj`.
   - Re-read the version/build values after editing:
     ```bash
     grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" Luego.xcodeproj/project.pbxproj | head -12
     ```
3. Archive the app with automatic signing.
   ```bash
   mkdir -p build
   xcodebuild archive \
     -project Luego.xcodeproj \
     -scheme Luego \
     -destination 'generic/platform=iOS' \
     -archivePath build/Luego.xcarchive \
     -configuration Release \
     -allowProvisioningUpdates
   ```
4. Write `build/ExportOptions.plist`.
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>destination</key>
       <string>upload</string>
       <key>method</key>
       <string>app-store-connect</string>
       <key>signingStyle</key>
       <string>automatic</string>
       <key>uploadSymbols</key>
       <true/>
       <key>manageAppVersionAndBuildNumber</key>
       <false/>
   </dict>
   </plist>
   ```
5. Export and upload with the Xcode-authenticated session.
   ```bash
   xcodebuild -exportArchive \
     -archivePath build/Luego.xcarchive \
     -exportOptionsPlist build/ExportOptions.plist \
     -exportPath build/Export \
     -allowProvisioningUpdates
   ```
6. Distribute the build to testers.
   - Wait until the new build's processing state is `VALID`:
     ```bash
     asc builds list --platform IOS --limit 3 --sort -uploadedDate --output table
     ```
   - `Friends-Internal` receives every build automatically. Add `External-Testers` and submit for beta app review:
     ```bash
     asc builds add-groups --build-id "BUILD_ID" --group "External-Testers" --submit --confirm
     asc builds beta-app-review-submission view --build-id "BUILD_ID" --output table
     ```
   - External testers, including public-link testers, get the build once review approves it.
7. Report the result.
   - Return the archive path, export path, and upload status.
   - Return the final `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
   - Return the tester groups on the build and the beta review state.
   - Return any actionable error output when archive, upload, or distribution fails.
8. Optionally clean local artifacts.
   ```bash
   rm -rf build/Luego.xcarchive build/Export build/ExportOptions.plist
   ```

## Troubleshooting checklist

- Authentication failures: refresh the Apple ID session in Xcode, confirm the correct team is selected, and retry the export/upload step.
- Provisioning failures: verify automatic signing is enabled, entitlements match the enabled capabilities, and both the app target and share extension target resolve with the same team.
- Duplicate build number: re-run the versioning step, keep the current date in `MARKETING_VERSION`, increment `CURRENT_PROJECT_VERSION`, then archive again.
- Missing upload progress or opaque exporter failures: inspect the `xcodebuild -exportArchive` output first, then confirm the generated archive exists at `build/Luego.xcarchive`.
