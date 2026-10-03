#!/usr/bin/env bash
# Safe filesystem smoke checks: no Fedora packages or system services are touched.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run the smoke tests as your normal user, without sudo." >&2
    exit 1
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/clone/config" "$scratch/home"

# Extract preflight only, preserving the script's location-based source lookup.
# Skip the root check so this can run as an ordinary user.
awk '
    /^# Ensure running as root before collecting interactive input\./ { skip = 1; next }
    skip && /^if ! command -v dnf/ { skip = 0 }
    /^# --- Pre-flight confirmation ---/ { exit }
    !skip { print }
' "$repo_dir/fedora_install.sh" > "$scratch/clone/preflight.sh"

SUDO_USER=$(id -un)
SMOKE_USER_HOME="$scratch/home"
export SUDO_USER SMOKE_USER_HOME
dnf() { echo 'Unexpected DNF call' >&2; return 77; }
rpm() { [[ "$*" == '-E %fedora' ]] && echo 43; }
sudo() {
    if [[ "${1:-}" == -u ]]; then shift 2; fi
    "$@"
}
getent() {
    if [[ "$1" == passwd ]]; then
        printf '%s:x:1000:1000::%s:/bin/bash\n' "$2" "$SMOKE_USER_HOME"
    else
        command getent "$@"
    fi
}
export -f dnf rpm sudo getent

if (cd "$scratch" && bash "$scratch/clone/preflight.sh") > "$scratch/out" 2>&1; then
    echo 'Missing clone config must fail preflight' >&2; exit 1
fi
grep -qE 'Missing .*/clone/config/hypr/hyprland.lua' "$scratch/out"
mkdir -p "$scratch/clone/config/hypr"
touch "$scratch/clone/config/hypr/hyprland.lua"
(cd "$scratch" && bash "$scratch/clone/preflight.sh")
chmod 000 "$scratch/clone/config/hypr/hyprland.lua"
if (cd "$scratch" && bash "$scratch/clone/preflight.sh") > "$scratch/out" 2>&1; then
    echo 'Unreadable clone config must fail preflight' >&2; exit 1
fi
grep -qE 'cannot read .*/clone/config' "$scratch/out"
chmod 644 "$scratch/clone/config/hypr/hyprland.lua"
mkdir -p "$scratch/clone/config/noctalia-greeter"
(cd "$scratch" && bash "$scratch/clone/preflight.sh")
echo 'PASS: preflight uses clone config from another directory and rejects missing or unreadable Hyprland config'

# shellcheck source=/dev/null
source <(sed -n '/^deploy_configs() {/,/^}/p' "$repo_dir/fedora_install.sh")
CONFIG_SOURCE_DIR="$scratch/clone/config"
CONFIG_DIR="$scratch/home/.config"
ACTUAL_USER=$(id -un)
export ACTUAL_USER
mkdir -p "$CONFIG_DIR/hypr"
printf 'old\n' > "$CONFIG_DIR/hypr/startup.lua"
printf 'new\n' > "$CONFIG_SOURCE_DIR/hypr/startup.lua"
cp -- "$repo_dir/config/noctalia-greeter/greeter.toml" "$CONFIG_SOURCE_DIR/noctalia-greeter/greeter.toml"
# Reproduce a config directory that cannot be written by its owner.
chmod 0500 "$CONFIG_DIR"
deploy_configs > /dev/null
[[ $(stat -c %a "$CONFIG_DIR") == 700 ]]
[[ $(cat "$CONFIG_DIR/hypr/startup.lua") == new ]]
[[ $(cat "$CONFIG_DIR/hypr.bak."*/startup.lua) == old ]]
[[ ! -e "$CONFIG_DIR/noctalia-greeter" ]]
if compgen -G "$CONFIG_DIR/.installer-stage.*" > /dev/null; then
    echo 'Staging directory was not removed' >&2; exit 1
fi
echo 'PASS: config write permissions are repaired, dotfiles deploy with backup, and greeter files stay out of ~/.config'

# A source lost after preflight must not report a successful deployment.
mv -- "$CONFIG_SOURCE_DIR" "$scratch/saved-config"
if deploy_configs > "$scratch/out" 2>&1; then
    echo 'Missing source must fail deployment' >&2; exit 1
fi
[[ $(cat "$CONFIG_DIR/hypr/startup.lua") == new ]]
mv -- "$scratch/saved-config" "$CONFIG_SOURCE_DIR"
echo 'PASS: missing source fails without replacing installed user config'

# A failed ownership repair must stop before staging or replacing existing files.
(
    chown() { return 1; }
    if deploy_configs > "$scratch/out" 2>&1; then
        echo 'Failed config ownership repair must fail deployment' >&2; exit 1
    fi
    grep -q 'Could not prepare' "$scratch/out"
    [[ $(cat "$CONFIG_DIR/hypr/startup.lua") == new ]]
    if compgen -G "$CONFIG_DIR/.installer-stage.*" > /dev/null; then
        echo 'Staging must not start after failed ownership repair' >&2; exit 1
    fi
)
echo 'PASS: failed ownership repair stops deployment before changing dotfiles'

# Missing sessions and failed service enablement must not change the boot target.
# shellcheck source=/dev/null
source <(sed -n '/^enable_greetd_service() {/,/^}/p' "$repo_dir/fedora_install.sh")
HYPRLAND_SESSION_FILE="$scratch/hyprland.desktop"
systemctl() {
    printf '%s\n' "$*" >> "$scratch/systemctl.log"
    [[ "$1" != enable || "${fail_enable:-0}" != 1 ]]
}
if enable_greetd_service > "$scratch/out" 2>&1; then
    echo 'Missing Hyprland session must fail' >&2; exit 1
fi
[[ ! -e "$scratch/systemctl.log" ]]
touch "$HYPRLAND_SESSION_FILE"
fail_enable=1
if enable_greetd_service > "$scratch/out" 2>&1; then
    echo 'Service enable failure must propagate' >&2; exit 1
fi
[[ $(cat "$scratch/systemctl.log") == 'enable greetd' ]]
: > "$scratch/systemctl.log"
fail_enable=0
enable_greetd_service > /dev/null
[[ $(cat "$scratch/systemctl.log") == $'enable greetd\nset-default graphical.target\nget-default' ]]
echo 'PASS: boot target changes only after session check and successful greetd enablement'
