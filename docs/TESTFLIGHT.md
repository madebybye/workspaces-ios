# Getting Workspaces onto TestFlight — handoff

Status as of 2026-07-18, prepared on Robert's Mac (Xcode 26.6, build 17F113).

## What is already done (verified on this machine)

- **Release config compiles for device.** An unsigned device archive
  (`CODE_SIGNING_ALLOWED=NO`) succeeds.
- **A development-signed archive succeeds.** Automatic signing with
  `DEVELOPMENT_TEAM=3KHQR8LD7D` (Affolk Inc.) produced a valid archive signed
  with an Apple Development certificate and the team's wildcard development
  profile. This proves the whole signing pipeline works; only *distribution*
  signing remains.
- **Versioning:** `MARKETING_VERSION = 1.0.0`, `CURRENT_PROJECT_VERSION = 1`.
- **App-Store-relevant Info.plist state (verified in the built .app):**
  - Display name: `Workspaces` (`INFOPLIST_KEY_CFBundleDisplayName`)
  - `ITSAppUsesNonExemptEncryption = NO` (app uses only HTTPS, which is
    exempt) — set in `Workspaces/Info.plist`, so App Store Connect will not
    ask the export-compliance question on every build
  - `NSPhotoLibraryAddUsageDescription` = "Save workspace photos to your
    photo library." (future-proofs Save-to-Photos)
  - Launch screen configured (`UILaunchScreen` with the `Paper` color)
- **Privacy manifest:** `Workspaces/PrivacyInfo.xcprivacy` exists and is
  present in the built `.app` (no tracking, no collected data, file-timestamp
  API reason C617.1).
- **App icon:** all three variants present (light / dark / tinted, 1024pt).
- **Affiliate disclosure:** shown in-app.
- **Scaffolding:** `ExportOptions.plist` (app-store-connect, automatic
  signing, `manageAppVersionAndBuildNumber`, `uploadSymbols`) and
  `scripts/archive-and-upload.sh` (archive → export → upload via
  `xcodebuild -exportArchive` with `destination=upload`; altool fallback
  documented in the script).

## What was intentionally NOT done

- **No App Store export/upload was attempted.** Running
  `-exportArchive -allowProvisioningUpdates` would have registered the App ID
  before the bundle-id ownership decision was made. That decision has since
  been made (next section); the upload is now unblocked once the App ID is
  registered.
- No credentials were entered, no certificates or keys were created, nothing
  was committed to git.

## Signing reality on this Mac

- 6 valid **Apple Development** certificates across 5 teams; **no Apple
  Distribution certificate in the keychain** (modern Xcode uses cloud-managed
  distribution certs, so this is normal and not a blocker).
- Teams seen: `Y2229PLGGP`, `XJC65M27DN`, `XC92SFAGRG`,
  `3KHQR8LD7D` (Affolk Inc.), `KR8X94SW38`.
- `KR8X94SW38` has a May-2026 Xcode-managed **App Store** profile for another
  app, so that membership is paid and active. `3KHQR8LD7D` has a valid
  wildcard development profile (used for the successful signed archive).
- No App Store Connect API keys found on disk.
- Xcode has signed-in developer accounts (archives with
  `-allowProvisioningUpdates` worked without prompting).

## Remaining human steps

### 1. Bundle-id ownership (DECIDED)

The bundle id is **`com.madebybye.workspaces`** — reverse-DNS of Robert's own
domain (madebybye.com), so the App ID and App Store Connect record live under
Robert's Apple Developer team with a namespace he controls. This avoids
squatting on the friend's `xyz.workspaces.*` namespace; if the app is ever
handed over to the site owner, use App Store Connect's app-transfer flow (the
bundle id travels with the app).

### 2. Create the App ID and app record

In [App Store Connect](https://appstoreconnect.apple.com) (Robert's team):

1. Certificates, Identifiers & Profiles → Identifiers → **register App ID**
   `com.madebybye.workspaces` (explicit, no special capabilities needed).
   (Xcode's `-allowProvisioningUpdates` can also do this automatically.)
2. App Store Connect → My Apps → **+ New App**: platform iOS, name
   "Workspaces" (must be globally unique on the store; have fallbacks ready,
   e.g. "Workspaces — desk setups"), primary language, bundle id from step 1,
   SKU (any string, e.g. `workspaces-ios-001`).

### 3. First upload

Either:

- **Script:** sign into Xcode (Settings → Accounts) with an account on the
  owning team, then
  `TEAM_ID=<owning team id> ./scripts/archive-and-upload.sh`
  — it archives, signs with the team's distribution identity
  (cloud-managed; created on first use), and uploads. Set `teamID` in
  `ExportOptions.plist` to make the script's plist edit unnecessary.
- **Xcode UI:** Product → Archive → Organizer → Distribute App →
  App Store Connect → Upload (automatic signing).

The build appears in App Store Connect → TestFlight after processing
(5–30 min). Because `ITSAppUsesNonExemptEncryption=NO` is baked in, no
export-compliance prompt should appear.

### 4. TestFlight — internal testing (no review needed)

- App Store Connect → TestFlight → Internal Testing → create a group, add
  testers (must be added to the team as users first; up to 100 internal
  testers). Builds are available to them immediately after processing.

### 5. TestFlight — external testing (requires Beta App Review)

Needed before inviting up to 10,000 external testers via email/public link:

- **Beta App Description**, feedback email, and contact info
- **What to Test** notes per build
- A privacy policy URL (required for external TestFlight)
- Beta App Review (~1 day) applies App Store guidelines; see the risk
  section below — have the site-owner authorization ready.

### 6. Metadata/screenshots for the eventual App Store listing

- Screenshots: 6.9" iPhone required (iPad screenshots too since the app
  supports iPad, `TARGETED_DEVICE_FAMILY = 1,2`). Raw captures exist in
  `docs/screenshot-*.png` but must be re-taken at the exact required
  resolutions on the current flagship simulators.
- App name (30 chars), subtitle (30), description, keywords (100),
  support URL, marketing URL (workspaces.xyz), privacy policy URL.
- App Privacy questionnaire in ASC — should match the privacy manifest:
  no data collected, no tracking.
- Age rating questionnaire, category (e.g. Lifestyle or News).

### 7. App Review risk areas (plan before external beta / App Store)

- **5.2.2 / unofficial-client apps:** Workspaces is a third-party editorial
  client for workspaces.xyz. Apple can reject apps that use third-party
  content without permission. **Get written authorization from the friend
  (the site owner)** — ideally a short signed letter/email stating the app
  is authorized to display workspaces.xyz content and use the name — and
  attach it in App Review notes. Best of all: ship under the friend's own
  developer account, which makes the app first-party and moots 5.2.2.
- **4.2 minimum functionality:** a pure content-viewer wrapped around a
  website can be rejected as "could be a website." Native touches (saved
  items, collections, notifications, photo saving, widgets, offline cache)
  strengthen the case — call these out in App Review notes.
- **Affiliate links:** affiliate/monetized links to physical goods are fine
  (physical goods are exempt from IAP rules), and the app already shows an
  affiliate disclosure in-app. Keep the disclosure visible and mention it
  in review notes.

## Compliance snapshot

| Item | State |
|---|---|
| Privacy manifest (PrivacyInfo.xcprivacy, in built .app) | Done |
| Launch screen | Done |
| App icon (light / dark / tinted) | Done |
| Encryption exempt (`ITSAppUsesNonExemptEncryption=NO`) | Done |
| Affiliate disclosure in-app | Done |
| Photo-library add usage description | Done |
| Version 1.0.0 (build 1) | Done |
| Distribution signing / upload | Needs owning team (steps 1–3) |
| Privacy policy URL | Needed for external TestFlight |
| Site-owner authorization in writing | Recommended before review |
