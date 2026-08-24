app_name := "ClawdBack"
bundle_name := app_name + ".app"
install_dir := env_var('HOME') / "Applications"
executable_name := "clawd-back"

# Code signing identity: "-" for ad-hoc, or your Developer ID.
# Override: just install signing_identity="Apple Development: You (XXXXXXXXXX)"
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

install: sign
    @echo "Installing to {{install_dir}}..."
    @mkdir -p {{install_dir}}
    @rm -rf {{install_dir}}/{{bundle_name}}
    @cp -r {{bundle_name}} {{install_dir}}/
    @echo "Installed: {{install_dir}}/{{bundle_name}}"
    @echo ""
    @echo "Usage:"
    @echo "  open {{install_dir}}/{{bundle_name}} --args notify --message 'Your message' --title 'Title'"

uninstall:
    @echo "Removing {{install_dir}}/{{bundle_name}}..."
    @rm -rf {{install_dir}}/{{bundle_name}}
    @echo "Uninstalled."

test-notify: install
    @echo "Sending test notification..."
    env -u ZELLIJ_SESSION_NAME -u ZELLIJ_PANE_ID open {{install_dir}}/{{bundle_name}} --args notify --message "Test notification from Clawd Back" --title "Test"

# List available code signing identities.
list-identities:
    @echo "Available code signing identities:"
    @security find-identity -v -p codesigning
