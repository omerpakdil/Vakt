#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_ID="${DEVICE_ID:-booted}"
APP_PATH="${APP_PATH:-/tmp/VaktReferralDerived/Build/Products/Debug-iphonesimulator/Vakt.app}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/LocalizationQA}"
BUNDLE_ID="com.callousity.vakt"
languages=(ar ur de fr ru)
surfaces=(splash onboarding-1 onboarding-2 onboarding-3 onboarding-4 onboarding-5 onboarding-6 sign-in paywall)

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

launch_argument() {
  case "$1" in
    splash) echo "--vakt-preview-splash" ;;
    onboarding-1) echo "--vakt-onboarding-page=0" ;;
    onboarding-2) echo "--vakt-onboarding-page=1" ;;
    onboarding-3) echo "--vakt-onboarding-page=2" ;;
    onboarding-4) echo "--vakt-onboarding-page=3" ;;
    onboarding-5) echo "--vakt-onboarding-page=4" ;;
    onboarding-6) echo "--vakt-onboarding-page=5" ;;
    sign-in) echo "--vakt-sign-in-preview" ;;
    paywall) echo "--vakt-paywall-preview" ;;
    *) return 1 ;;
  esac
}

for language in "${languages[@]}"; do
  mkdir -p "$OUTPUT_DIR/$language"
  for surface in "${surfaces[@]}"; do
    argument="$(launch_argument "$surface")"
    xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$BUNDLE_ID" --args \
      -AppleLanguages "($language)" \
      -AppleLocale "$language" \
      "$argument" >/dev/null
    sleep 2
    xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT_DIR/$language/$surface.png" >/dev/null
    echo "$language · $surface"
  done
done

echo "Screenshots written to $OUTPUT_DIR"
