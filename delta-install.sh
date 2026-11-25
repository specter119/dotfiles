#!/bin/sh
# Install the selected Delta application and its bundled CLI on macOS or Linux.
set -eu

: "${HOME:?HOME is required}"
release_channel=${release_channel:-stable}
tenant_cloud_url=${tenant_cloud_url:-}
delta_server_url=${delta_server_url:-}
mode=interactive
action=install
while [ "$#" -gt 0 ]; do
    case "$1" in
        --non-interactive) mode=non-interactive ;;
        --locate-cli) action=locate-cli ;;
        --trunk) release_channel=trunk ;;
        --help|-h)
            printf '%s\n' 'Usage: sh install.sh [--trunk] [--non-interactive] [--locate-cli]' \
                'Locate the selected channel CLI without installing (--locate-cli), or install it if absent.' \
                'Non-interactive installation prints only the absolute CLI path on stdout.'
            exit 0
            ;;
        *) echo "Unknown installer argument: $1" >&2; exit 2 ;;
    esac
    shift
done

case "$release_channel" in
    stable) bundle_name=Delta; linux_bundle_dir=Delta; linux_cli=delta; linux_app=delta.app ;;
    trunk) bundle_name="Delta Trunk"; linux_bundle_dir=delta-trunk; linux_cli=delta-trunk; linux_app=delta-trunk.app ;;
    *) echo "Unsupported Delta release channel: $release_channel" >&2; exit 2 ;;
esac
if [ -n "$tenant_cloud_url" ] || [ -n "$delta_server_url" ]; then
    if [ -z "$tenant_cloud_url" ] || [ -z "$delta_server_url" ]; then
        echo 'Both tenant_cloud_url and delta_server_url are required.' >&2
        exit 2
    fi
    for origin in "$tenant_cloud_url" "$delta_server_url"; do
        if ! printf '%s\n' "$origin" | LC_ALL=C grep -Eq '^https://[A-Za-z0-9][A-Za-z0-9.:-]*$'; then
            echo "Invalid tenant HTTPS origin: $origin" >&2
            exit 2
        fi
    done
    release_api_url=$delta_server_url
else
    release_api_url=https://delta.dev/api
    if [ "$action" = install ] &&
        { [ -e "$HOME/.config/delta/tenant" ] || [ -L "$HOME/.config/delta/tenant" ]; }; then
        echo 'This machine has a tenant configuration. Install Delta from your tenant homepage instead of the public installer.' >&2
        exit 1
    fi
fi

os=$(uname -s)
case "$os" in
    Darwin) platform=macos ;;
    Linux) platform=linux ;;
    *) echo "Delta installer does not support $os." >&2; exit 1 ;;
esac
case "$(uname -m)" in
    arm64|aarch64) arch=aarch64 ;;
    x86_64|amd64) arch=x86_64 ;;
    *) echo "Unsupported CPU architecture." >&2; exit 1 ;;
esac

if [ "$platform" = macos ]; then
    app_dir="$HOME/Applications"
    app="$app_dir/$bundle_name.app"
    cli="$app/Contents/MacOS/delta"
else
    app="$HOME/.local/$linux_app"
    cli="$app/bin/$linux_cli"
fi
link="$HOME/.local/bin/delta"

check_tenant_config() {
    if [ -z "$tenant_cloud_url" ]; then return; fi
    directory="$HOME/.config/delta"
    file="$directory/tenant"
    if [ -L "$file" ] || { [ -e "$file" ] && [ ! -f "$file" ]; }; then
        echo "Tenant configuration at $file is not a regular file." >&2
        exit 1
    fi
    if [ -f "$file" ]; then
        if ! grep -Fqx "TENANT_URL=$tenant_cloud_url" "$file" ||
            { grep -q '^DELTA_REMOTE_URL=' "$file" &&
              ! grep -Fqx "DELTA_REMOTE_URL=$delta_server_url" "$file"; }; then
            echo "Tenant configuration at $file differs from this tenant. Resolve it before installing." >&2
            exit 1
        fi
    fi
}

install_tenant_config() {
    if [ -z "$tenant_cloud_url" ]; then return; fi
    check_tenant_config
    mkdir -p "$directory"
    if [ -f "$file" ] && grep -Fqx "DELTA_REMOTE_URL=$delta_server_url" "$file"; then return; fi
    temporary=$(mktemp "$directory/.tenant.XXXXXX")
    chmod 600 "$temporary"
    if [ -f "$file" ]; then
        cat "$file" > "$temporary"
        printf '\nDELTA_REMOTE_URL=%s\n' "$delta_server_url" >> "$temporary"
    else
        printf 'TENANT_URL=%s\nDELTA_REMOTE_URL=%s\n' \
            "$tenant_cloud_url" "$delta_server_url" > "$temporary"
    fi
    mv "$temporary" "$file"
}

report_cli() {
    if [ "$mode" = non-interactive ] || [ "$action" = locate-cli ]; then
        printf '%s\n' "$cli"
    else
        printf 'Delta CLI: %s\n' "$cli" >&2
        if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$cli" ]; then
            printf '%s is occupied; use the CLI path above or resolve the conflict.\n' "$link" >&2
            return
        fi
        case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *)
                case "${SHELL:-}" in
                    */zsh) profile="$HOME/.zshrc" ;;
                    */bash)
                        if [ "$platform" = macos ]; then
                            profile="$HOME/.bash_profile"
                        else
                            profile="$HOME/.bashrc"
                        fi
                        ;;
                    *) profile= ;;
                esac
                if [ -n "$profile" ]; then
                    printf 'Add %s to PATH in %s? [y/N] ' "$HOME/.local/bin" "$profile" >/dev/tty
                    IFS= read -r answer </dev/tty || answer=
                    case "$answer" in
                        y|Y|yes|YES)
                            printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profile"
                            printf 'Updated %s. Open a new terminal to use delta.\n' "$profile" >&2
                            ;;
                        *) printf 'Add %s to PATH to use delta in your shell.\n' "$HOME/.local/bin" >&2 ;;
                    esac
                else
                    printf 'Add %s to PATH to use delta in your shell.\n' "$HOME/.local/bin" >&2
                fi
                ;;
        esac
    fi
}

if [ "$action" = install ]; then check_tenant_config; fi

# Only select an existing installation of the requested channel.
found=
if [ -L "$link" ]; then
    existing=$(readlink "$link")
    case "$platform:$existing" in
        "macos:$HOME/Applications/$bundle_name.app/Contents/MacOS/delta"|\
        "macos:/Applications/$bundle_name.app/Contents/MacOS/delta"|\
        "linux:$HOME/.local/$linux_app/bin/$linux_cli")
            if [ -x "$existing" ]; then found="$existing"; fi
            ;;
    esac
fi
if [ -z "$found" ] && [ "$platform" = macos ]; then
    for candidate in "$cli" "/Applications/$bundle_name.app/Contents/MacOS/delta"; do
        if [ -x "$candidate" ]; then found="$candidate"; break; fi
    done
elif [ -z "$found" ] && [ -x "$cli" ]; then
    found="$cli"
fi
if [ -n "$found" ]; then
    cli="$found"
    if [ "$action" = install ]; then
        mkdir -p "$HOME/.local/bin"
        if [ ! -e "$link" ] && [ ! -L "$link" ]; then
            ln -s "$cli" "$link"
        elif [ -L "$link" ]; then
            case "$(readlink "$link")" in
                "$HOME/Applications/Delta.app/Contents/MacOS/delta"|\
                /Applications/Delta.app/Contents/MacOS/delta|\
                "$HOME/Applications/Delta Trunk.app/Contents/MacOS/delta"|\
                "/Applications/Delta Trunk.app/Contents/MacOS/delta"|\
                "$HOME/.local/delta.app/bin/delta"|\
                "$HOME/.local/delta-trunk.app/bin/delta-trunk")
                    ln -sfn "$cli" "$link" ;;
            esac
        fi
        install_tenant_config
    fi
    report_cli
    exit 0
fi
if [ "$action" = locate-cli ]; then exit 1; fi

if [ "$mode" = interactive ]; then
    if [ ! -r /dev/tty ]; then
        echo "No terminal available; use --non-interactive to install without a prompt." >&2
        exit 1
    fi
    printf '%s\n' 'Delta includes a GUI app and a CLI that can start its headless background process.' \
        "Install Delta for this user? [y/N] " >/dev/tty
    IFS= read -r answer </dev/tty || exit 1
    case "$answer" in y|Y|yes|YES) ;; *) echo "Installation cancelled." >&2; exit 1 ;; esac
fi

work=$(mktemp -d)
cleanup() {
    if [ -n "${staged:-}" ] && [ -d "$staged" ]; then
        if [ -d "$staged/old.app" ] && [ ! -e "$app" ]; then
            mv "$staged/old.app" "$app"
        fi
        rm -rf "$staged"
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
response="$work/release.json"
asset_url="$release_api_url/releases/$release_channel/latest/asset?asset=delta&os=$platform&arch=$arch"
curl -fsSL "$asset_url" -o "$response"
if [ "$platform" = macos ]; then
    download_url=$(plutil -extract url raw -o - "$response")
else
    download_url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$response")
fi
case "$download_url" in
    https://*) ;;
    *) echo "The release endpoint returned an invalid download URL." >&2; exit 1 ;;
esac

if [ "$platform" = macos ]; then
    archive="$work/$bundle_name.app.zip"
else
    archive="$work/Delta.tar.gz"
fi
if [ -e "$link" ] || [ -L "$link" ]; then
    if [ ! -L "$link" ]; then
        echo "Unrelated command exists at $link; leaving it untouched." >&2
        exit 1
    fi
    existing=$(readlink "$link")
    case "$existing" in
        "$cli"|"$HOME/Applications/Delta.app/Contents/MacOS/delta"|\
        /Applications/Delta.app/Contents/MacOS/delta|\
        "$HOME/Applications/Delta Trunk.app/Contents/MacOS/delta"|\
        "/Applications/Delta Trunk.app/Contents/MacOS/delta"|\
        "$HOME/.local/delta.app/bin/delta"|\
        "$HOME/.local/delta-trunk.app/bin/delta-trunk")
            ;;
        *)
            echo "Unrelated CLI link exists at $link; leaving it untouched." >&2
            exit 1
            ;;
    esac
fi

curl -fsSL "$download_url" -o "$archive"
if [ "$platform" = macos ]; then
    mkdir -p "$app_dir" "$HOME/.local/bin"
    staged=$(mktemp -d "$app_dir/.delta-install.XXXXXX")
    ditto -x -k "$archive" "$staged"
    if [ ! -x "$staged/$bundle_name.app/Contents/MacOS/delta" ]; then
        echo "The Delta archive is missing its CLI." >&2
        exit 1
    fi
    # Keep the old bundle available until the new one is in place.
    if [ -e "$app" ]; then
        mv "$app" "$staged/old.app"
    fi
    if ! mv "$staged/$bundle_name.app" "$app"; then
        if [ -e "$staged/old.app" ]; then mv "$staged/old.app" "$app"; fi
        exit 1
    fi
    ln -sfn "$cli" "$link"
    rm -rf "$staged"
    staged=
else
    tar -xzf "$archive" -C "$work"
    if [ ! -f "$work/$linux_bundle_dir/install.sh" ]; then
        echo "The Delta archive is missing its installer." >&2
        exit 1
    fi
    bash "$work/$linux_bundle_dir/install.sh" >&2
    if [ ! -x "$cli" ] || [ ! -L "$link" ] || [ "$(readlink "$link")" != "$cli" ]; then
        echo "Delta installed, but its CLI could not be linked." >&2
        exit 1
    fi
fi

install_tenant_config
report_cli
