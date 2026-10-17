# Releasing Harbor

Releases are signed with Griffin's Developer ID, notarized by Apple, published on GitHub, and listed in the [griffhurt/homebrew-tap](https://github.com/griffhurt/homebrew-tap) cask. Installed copies update themselves with Sparkle.

## One-time setup on a Mac

1. **Developer ID certificate.** In Xcode, go to **Settings → Accounts → Manage Certificates** and add a **Developer ID Application** certificate, or import the `.p12` exported from another Mac. `security find-identity -v -p codesigning` should list it.
2. **Notary profile.** Create an app-specific password at [account.apple.com](https://account.apple.com), under **Sign-In and Security → App-Specific Passwords**. Then save it to the keychain:
   ```sh
   xcrun notarytool store-credentials harbor-notary --apple-id <Apple ID> --team-id R3Q3N484K2
   ```
3. **Sparkle update key.** Installed copies only accept updates signed with the key whose public half is `SUPublicEDKey` in `Resources/Info.plist`, so never generate a new one. Import the backup:
   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account com.griffhurt.harbor -f <backup file>
   ```
   To make a backup, use `-x <file>` instead of `-f`, and keep the file in a password manager.
4. **Tap.** Run `brew tap griffhurt/tap`. The cask is at `$(brew --repository griffhurt/tap)/Casks/harbor.rb`.

## Making a release

Use the new version in place of `1.1.0`.

1. Commit everything, push `main`, and wait for CI to pass.
2. Tag the release:
   ```sh
   git tag v1.1.0 && git push origin v1.1.0
   ```
3. Build it:
   ```sh
   NOTARY_PROFILE=harbor-notary scripts/build.sh --release
   ```
   The version comes from the tag and the build number is the commit count. This makes `build/Harbor-1.1.0.zip` and `build/appcast.xml`. If Apple rejects the app, the script stops; `xcrun notarytool log <id> --keychain-profile harbor-notary` says why.
4. Publish it, with **both** files:
   ```sh
   gh release create v1.1.0 build/Harbor-1.1.0.zip build/appcast.xml --title "Harbor 1.1.0" --notes "…"
   ```
5. Update the cask's `version` and `sha256` (`shasum -a 256 build/Harbor-1.1.0.zip`), then check, commit and push it:
   ```sh
   brew style griffhurt/tap && brew audit --cask --online griffhurt/tap/harbor
   ```
6. In an older copy of Harbor, choose **Harbor › Check for Updates…** and make sure it offers the new version.

## How updates work

- The feed URL is `https://github.com/griffhurt/harbor/releases/latest/download/appcast.xml`, so installed copies read the appcast attached to the latest release. A release without `appcast.xml` breaks updates for everyone until the next one.
- Drafts and pre-releases never count as the latest release, so they don't reach users until they're published as full releases.
- Sparkle compares build numbers. The commit count on `main` always goes up, as long as `main`'s history is never rewritten.
- Only release builds have a feed URL (`build.sh --release` adds `SUFeedURL`), so local builds never update.
