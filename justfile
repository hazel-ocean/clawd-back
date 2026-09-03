app_name := "ClawdBack"
bundle_name := app_name + ".app"
executable_name := "clawd-back"

# Code signing identity: "-" for ad-hoc, or your Developer ID.
# Override: just sign signing_identity="Apple Development: You (XXXXXXXXXX)"
# Find yours: security find-identity -v -p codesigning
signing_identity := "-"

# List available recipes.
default:
    @just --list

build:
    swift build

release:
    swift build -c release

clean:
    rm -rf .build
    rm -rf {{bundle_name}}

bundle: release
    @echo "Creating app bundle..."
    @rm -rf {{bundle_name}}
    @mkdir -p {{bundle_name}}/Contents/MacOS
    @mkdir -p {{bundle_name}}/Contents/Resources
    @cp .build/release/{{executable_name}} {{bundle_name}}/Contents/MacOS/
    @cp -R Resources/. {{bundle_name}}/Contents/Resources/
    @mv {{bundle_name}}/Contents/Resources/Info.plist {{bundle_name}}/Contents/
    @rm -f {{bundle_name}}/Contents/Resources/entitlements.plist
    @sed -i "" "s|0.0.0-dev|$(cat VERSION)|g" {{bundle_name}}/Contents/Info.plist
    @find Sources -name '*.applescript' -exec sh -c 'd="{{bundle_name}}/Contents/Resources/$(dirname "${1#Sources/}")"; mkdir -p "$d"; cp "$1" "$d/"' _ {} \;
    @cp -R hooks {{bundle_name}}/Contents/Resources/
    @chmod +x {{bundle_name}}/Contents/Resources/hooks/*/*
    @echo "App bundle created: {{bundle_name}}"

sign: bundle
    @echo "Code signing app bundle..."
    codesign --force --sign "{{signing_identity}}" --timestamp {{bundle_name}}
    @echo "Verifying signature..."
    codesign --verify --verbose {{bundle_name}}
    @echo "Code signing complete."

# Notify from the bundle in this directory; an unsigned one is refused.
test-notify: sign
    @echo "Sending test notification..."
    env -u ZELLIJ_SESSION_NAME -u ZELLIJ_PANE_ID open -gn {{bundle_name}} --args notify --message "Test notification from Clawd Back" --title "Test"

# List available code signing identities.
list-identities:
    @echo "Available code signing identities:"
    @security find-identity -v -p codesigning

# Show a log stream of events published by Clawd Back
logs:
    clear
    log stream --predicate 'subsystem == "com.hazel.clawd-back"' --style compact
