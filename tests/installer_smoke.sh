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
if (cd "$scratch" && bash "$scratch/clone/preflight.sh") > "$scratch/out" 2>&1; then
    echo 'Incomplete greeter config must fail preflight' >&2; exit 1
fi
grep -qE 'Expected .*/clone/config/noctalia-greeter/greeter.toml' "$scratch/out"
cp -- "$repo_dir/config/noctalia-greeter/greeter.toml" "$scratch/clone/config/noctalia-greeter/greeter.toml"
(cd "$scratch" && bash "$scratch/clone/preflight.sh")
echo 'PASS: preflight uses clone config from another directory and rejects unreadable or incomplete config'

# shellcheck source=/dev/null
source <(sed -n '/^deploy_configs() {/,/^}/p' "$repo_dir/fedora_install.sh")
# shellcheck source=/dev/null
source <(sed -n '/^deploy_greeter_config() {/,/^}/p' "$repo_dir/fedora_install.sh")
CONFIG_SOURCE_DIR="$scratch/clone/config"
CONFIG_DIR="$scratch/home/.config"
ACTUAL_USER=$(id -un)
export ACTUAL_USER
GREETER_STATE_DIR="$scratch/greeter-state"
mkdir -p "$CONFIG_DIR/hypr" "$GREETER_STATE_DIR"
printf 'old\n' > "$CONFIG_DIR/hypr/startup.lua"
printf 'new\n' > "$CONFIG_SOURCE_DIR/hypr/startup.lua"
deploy_configs > /dev/null
[[ $(cat "$CONFIG_DIR/hypr/startup.lua") == new ]]
[[ $(cat "$CONFIG_DIR/hypr.bak."*/startup.lua) == old ]]
[[ ! -e "$CONFIG_DIR/noctalia-greeter" ]]
if compgen -G "$CONFIG_DIR/.installer-stage.*" > /dev/null; then
    echo 'Staging directory was not removed' >&2; exit 1
fi
echo 'PASS: user dotfiles deploy with backup and greeter files stay out of ~/.config'

# Mock only ownership changes (the real installer runs this as root).
install() {
    local args=() owner_seen=0 group_seen=0
    while (($#)); do
        case "$1" in
            -o) [[ "$2" == greeter ]] || return 1; owner_seen=1; shift 2 ;;
            -g) [[ "$2" == greeter ]] || return 1; group_seen=1; shift 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done
    [[ "$owner_seen" == 1 && "$group_seen" == 1 ]] || return 1
    command install "${args[@]}"
}
mv -- "$CONFIG_SOURCE_DIR/noctalia-greeter" "$scratch/custom-greeter"
deploy_greeter_config > /dev/null
[[ ! -e "$GREETER_STATE_DIR/greeter.toml" ]]
mv -- "$scratch/custom-greeter" "$CONFIG_SOURCE_DIR/noctalia-greeter"
deploy_greeter_config > /dev/null
cmp -- "$repo_dir/config/noctalia-greeter/greeter.toml" "$GREETER_STATE_DIR/greeter.toml"
[[ $(stat -c %a "$GREETER_STATE_DIR/greeter.toml") == 640 ]]
printf 'theme = "updated"\n' > "$CONFIG_SOURCE_DIR/noctalia-greeter/greeter.toml"
deploy_greeter_config > /dev/null
[[ $(cat "$GREETER_STATE_DIR/greeter.toml") == 'theme = "updated"' ]]
cmp -- "$repo_dir/config/noctalia-greeter/greeter.toml" "$GREETER_STATE_DIR/greeter.toml.bak"
[[ ! -e "$CONFIG_DIR/noctalia-greeter" ]]
echo 'PASS: bundled greeter config deploys with greeter ownership arguments, 0640 permissions and backup'

# A source lost after preflight must not report a successful deployment.
mv -- "$CONFIG_SOURCE_DIR" "$scratch/saved-config"
if deploy_configs > "$scratch/out" 2>&1; then
    echo 'Missing source must fail deployment' >&2; exit 1
fi
[[ $(cat "$CONFIG_DIR/hypr/startup.lua") == new ]]
mv -- "$scratch/saved-config" "$CONFIG_SOURCE_DIR"
echo 'PASS: missing source fails without replacing installed user config'

# A directory at the file destination must not silently receive a nested config.
rm -- "$GREETER_STATE_DIR/greeter.toml"
mkdir -- "$GREETER_STATE_DIR/greeter.toml"
if deploy_greeter_config > "$scratch/out" 2>&1; then
    echo 'Directory at greeter config destination must fail' >&2; exit 1
fi
[[ -z $(ls -A "$GREETER_STATE_DIR/greeter.toml") ]]
rmdir -- "$GREETER_STATE_DIR/greeter.toml"

# A symlink at the destination is replaced without touching its referent.
printf 'external config\n' > "$scratch/external-config"
ln -s -- "$scratch/external-config" "$GREETER_STATE_DIR/greeter.toml"
deploy_greeter_config > /dev/null
[[ ! -L "$GREETER_STATE_DIR/greeter.toml" ]]
[[ $(cat "$scratch/external-config") == 'external config' ]]
[[ $(cat "$GREETER_STATE_DIR/greeter.toml") == 'theme = "updated"' ]]
echo 'PASS: greeter destination directories fail and symlinks are replaced safely'

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

# Stop setup at user creation so this test cannot reach any /etc or /var writes.
(
    # shellcheck source=/dev/null
    source <(sed -n '/^setup_noctalia_greeter() {/,/^}/p' "$repo_dir/fedora_install.sh")
    noctalia-greeter-session() { :; }
    getent() { return 2; }
    id() { return 1; }
    groupadd() { printf '%s\n' "$*" > "$scratch/groupadd.log"; }
    useradd() { printf '%s\n' "$*" > "$scratch/useradd.log"; return 1; }
    if setup_noctalia_greeter > "$scratch/out" 2>&1; then
        echo 'Expected the mock user creation failure to stop setup' >&2; exit 1
    fi
    [[ $(cat "$scratch/groupadd.log") == '--system greeter' ]]
    [[ $(cat "$scratch/useradd.log") == "-r -g greeter -s /usr/bin/nologin -d $GREETER_STATE_DIR greeter" ]]
)
echo 'PASS: greeter group is created explicitly and used for the new account'
