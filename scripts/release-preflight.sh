#!/bin/bash
# Read-only checks of an explicit built .app. Never prints credential values.
# Passing is necessary, not sufficient: App Store Connect and real-device checks are separate.
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" || "$1" != *.app ]]; then
    echo "Usage: bash scripts/release-preflight.sh /absolute/path/Hair\ Compass\ AI\ 5.app" >&2
    exit 2
fi

release_app="$1"
release_plist="$release_app/Info.plist"
failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
plist_value() { /usr/bin/plutil -extract "$1" raw -o - "$release_plist" 2>/dev/null || true; }

if [[ ! -f "$release_plist" ]]; then
    echo "FAIL: Info.plist is missing." >&2
    exit 1
fi

[[ "$(plist_value CFBundleIdentifier)" == "harib.Hair-Compass-AI-5" ]] || fail "Wrong app bundle identifier."
[[ "$(plist_value DTPlatformName)" == "iphoneos" ]] || fail "This is not an iPhone device build."

# A gitignored build input is still public if it is expanded into the delivered bundle.
provider_credential="$(plist_value HCDeepSeekAPIKey)"
if [[ -n "$provider_credential" ]]; then
    fail "Provider credential or unresolved credential setting found in Info.plist (value withheld). Use a production backend; never distribute a provider key."
else
    echo "PASS: No provider credential in HCDeepSeekAPIKey."
fi
unset provider_credential

if /usr/bin/codesign --verify --deep --strict "$release_app" >/dev/null 2>&1; then
    echo "PASS: Local code-signature integrity."
else
    fail "Code signature is missing or invalid."
fi

release_profile="$release_app/embedded.mobileprovision"
if [[ -f "$release_profile" ]]; then
    debug_allowed=$(/usr/bin/security cms -D -i "$release_profile" 2>/dev/null | /usr/bin/plutil -extract Entitlements.get-task-allow raw -o - - 2>/dev/null || true)
    [[ "$debug_allowed" == "false" ]] || fail "Provisioning profile permits debugging or could not be verified. Export with App Store distribution signing."
else
    fail "Distribution provisioning profile is missing."
fi

[[ -f "$release_app/PrivacyInfo.xcprivacy" ]] || fail "App privacy manifest is missing."
[[ -f "$release_app/PlugIns/Hair Compass CheckIn Widget.appex/PrivacyInfo.xcprivacy" ]] || fail "Widget privacy manifest is missing."

echo "Local failures: $failures"
echo "This does NOT verify App Store Connect agreements/products, live payments, privacy declarations, server readiness, or physical-device behavior."
[[ $failures -eq 0 ]]
