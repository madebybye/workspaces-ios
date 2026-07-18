#!/bin/bash
#
# archive-and-upload.sh — build, sign, and ship Workspaces to TestFlight.
#
# Pipeline: xcodebuild archive  ->  xcodebuild -exportArchive (signs + uploads)
#
# Tooling note (verified against Xcode 26.6 on this machine):
#   * The modern, supported upload path is `xcodebuild -exportArchive` with
#     `destination = upload` in the export options plist. xcodebuild performs
#     the App Store Connect upload itself; no separate upload tool is needed.
#   * `xcrun altool` (26.40.1) still ships and still supports
#     `--upload-app` / `--upload-package` with App Store Connect API keys;
#     it is kept below as a commented fallback.
#   * `iTMSTransporter` also still ships but is legacy; do not use for new work.
#   * There is no `xcrun appstoreconnect` CLI in Xcode 26.
#
# Prerequisites (see docs/TESTFLIGHT.md):
#   1. Paid Apple Developer Program membership, signed into Xcode
#      (Settings > Accounts) for the team that will own the app.
#   2. App record created in App Store Connect for the bundle id
#      (currently com.madebybye.workspaces — see docs/TESTFLIGHT.md about ownership).
#   3. TEAM_ID below / in ExportOptions.plist set to that team.
#
# Usage:
#   TEAM_ID=ABCDE12345 ./scripts/archive-and-upload.sh            # archive + upload
#   TEAM_ID=ABCDE12345 ./scripts/archive-and-upload.sh --export-only  # write .ipa, no upload

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/Workspaces.xcodeproj"
SCHEME="Workspaces"
OUT_DIR="${OUT_DIR:-$PROJECT_DIR/build}"
ARCHIVE_PATH="$OUT_DIR/Workspaces.xcarchive"
EXPORT_PATH="$OUT_DIR/export"
EXPORT_PLIST_SRC="$PROJECT_DIR/ExportOptions.plist"

# The Apple Developer Team ID that owns the App ID / App Store Connect record.
TEAM_ID="${TEAM_ID:?Set TEAM_ID to the Apple Developer Team ID that owns the app}"

MODE="upload"
[[ "${1:-}" == "--export-only" ]] && MODE="export"

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# 1. Archive (Release, generic iOS device, automatic signing)
# ---------------------------------------------------------------------------
# -allowProvisioningUpdates lets xcodebuild talk to Apple's signing service to
# register the App ID, create/download the App Store provisioning profile, and
# use the team's (possibly cloud-managed) Apple Distribution certificate.
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  archive \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID"

# ---------------------------------------------------------------------------
# 2. Export options: inject team id + destination for this run
# ---------------------------------------------------------------------------
EXPORT_PLIST="$OUT_DIR/ExportOptions.resolved.plist"
cp "$EXPORT_PLIST_SRC" "$EXPORT_PLIST"
/usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID" "$EXPORT_PLIST"
if [[ "$MODE" == "upload" ]]; then
  /usr/libexec/PlistBuddy -c "Set :destination upload" "$EXPORT_PLIST"
else
  /usr/libexec/PlistBuddy -c "Set :destination export" "$EXPORT_PLIST"
fi

# ---------------------------------------------------------------------------
# 3. Export: re-sign for App Store Connect and (destination=upload) deliver
# ---------------------------------------------------------------------------
# With destination=upload this single command signs with Apple Distribution,
# uploads the build to App Store Connect, and uploads dSYMs (uploadSymbols).
# Progress/errors appear in the xcodebuild output; the build then shows up in
# App Store Connect > TestFlight after processing (typically 5–30 minutes).
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

if [[ "$MODE" == "export" ]]; then
  echo "Exported .ipa to: $EXPORT_PATH"
  echo "Upload it with Transporter.app, or uncomment the altool fallback below."
else
  echo "Upload submitted. Watch App Store Connect > TestFlight for processing."
fi

# ---------------------------------------------------------------------------
# Fallback: upload an exported .ipa with altool + App Store Connect API key
# ---------------------------------------------------------------------------
# Requires an ASC API key (.p8) in ~/.appstoreconnect/private_keys/ (or
# ./private_keys). Create one in App Store Connect > Users and Access >
# Integrations > App Store Connect API (role: App Manager or Developer).
#
#   xcrun altool --upload-app \
#     -f "$EXPORT_PATH/Workspaces.ipa" \
#     --type ios \
#     --apiKey "YOUR_KEY_ID" \
#     --apiIssuer "YOUR_ISSUER_ID"
#
# Or with an Apple ID + app-specific password (appleid.apple.com):
#
#   xcrun altool --upload-app -f "$EXPORT_PATH/Workspaces.ipa" --type ios \
#     -u "you@example.com" -p "@keychain:AC_PASSWORD"
