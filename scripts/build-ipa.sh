#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  print -u2 "XcodeGen is required to create the Xcode project. Install it with: brew install xcodegen"
  exit 1
fi
xcodegen generate

build_dir="$project_root/build"
app_path="$build_dir/Build/Products/Release-iphoneos/Plyph.app"
keyboard_path="$app_path/PlugIns/PlyphKeyboard.appex"
payload_dir="$build_dir/Payload"
ipa_path="$build_dir/Plyph.ipa"
checksum_path="$ipa_path.sha256"

xcodebuild \
  -project Plyph.xcodeproj \
  -scheme Plyph \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$build_dir" \
  CODE_SIGNING_ALLOWED=NO \
  build

extension_point="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$keyboard_path/Info.plist")"
if [[ "$extension_point" != "com.apple.keyboard-service" ]]; then
  print -u2 "Keyboard Info.plist is missing a valid NSExtension definition."
  exit 1
fi

rm -rf "$payload_dir"
mkdir -p "$payload_dir"
cp -R "$app_path" "$payload_dir/Plyph.app"
codesign --force --sign - \
  --entitlements Config/PlyphKeyboard.entitlements \
  "$payload_dir/Plyph.app/PlugIns/PlyphKeyboard.appex"
codesign --force --sign - \
  --entitlements Config/Plyph.entitlements \
  "$payload_dir/Plyph.app"
ditto -c -k --sequesterRsrc --keepParent "$payload_dir" "$ipa_path"

if ! unzip -Z1 "$ipa_path" | grep -qx "Payload/Plyph.app/Info.plist"; then
  print -u2 "The IPA is missing the main app Info.plist."
  exit 1
fi

if ! unzip -Z1 "$ipa_path" | grep -qx \
  "Payload/Plyph.app/PlugIns/PlyphKeyboard.appex/Info.plist"; then
  print -u2 "The IPA is missing the Plyph keyboard extension."
  exit 1
fi

(
  cd "$build_dir"
  shasum -a 256 "${ipa_path:t}" > "${checksum_path:t}"
)

print "Created $ipa_path with an ad-hoc signature and the required App Group entitlements."
print "Created $checksum_path."
print "Import the IPA into SideStore or AltStore, which will re-sign it with your Apple ID."
