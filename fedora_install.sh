#!/bin/bash

export LC_MESSAGES=C
export LANG=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Ensure running as root before collecting interactive input.
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

if ! command -v dnf >/dev/null 2>&1 || ! command -v rpm >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: dnf, rpm and sudo are required on Fedora." >&2
    exit 1
fi

FEDORA_VERSION=$(rpm -E '%fedora')
if [[ ! "$FEDORA_VERSION" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Could not determine the Fedora release from rpm." >&2
    exit 1
fi

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER=$(logname 2>/dev/null || true)
fi

if [[ -z "$ACTUAL_USER" || "$ACTUAL_USER" == root ]] || ! id -u "$ACTUAL_USER" >/dev/null 2>&1; then
    echo "ERROR: Run this script with sudo from your normal user account." >&2
    exit 1
fi

ACTUAL_USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
if [[ -z "$ACTUAL_USER_HOME" || ! -d "$ACTUAL_USER_HOME" ]]; then
    echo "ERROR: Could not determine home directory for user '$ACTUAL_USER'." >&2
    exit 1
fi

CONFIG_DIR="$ACTUAL_USER_HOME/.config"
CONFIG_SOURCE_DIR="$ACTUAL_USER_HOME/config_files"
if [[ ! -f "$CONFIG_SOURCE_DIR/hypr/hyprland.lua" ]]; then
    echo "ERROR: Missing $CONFIG_SOURCE_DIR/hypr/hyprland.lua. Add the Hyprland dotfiles to ~/config_files before running the installer." >&2
    exit 1
fi

# --- Pre-flight confirmation ---
echo "This script installs a Hyprland session and copies ~/config_files into ~/.config. Review the changes before proceeding."
while true; do
    read -r -p "Would you like to proceed? (y/n): " proceed || exit 1
    case "$proceed" in
        y|Y|yes|YES)
            echo "Great! Proceeding with installation..."
            break
            ;;
        n|N|no|NO)
            echo "Fair enough, Have a nice day."
            exit 0
            ;;
        *)
            echo "Please answer 'y' or 'n'."
            ;;
    esac
done

INSTALL_NVIDIA_OPTIONAL=0
while true; do
    echo ""
    read -r -p "Are you using an Nvidia GPU? (y/n): " nvidia_choice || exit 1
    case "$nvidia_choice" in
        y|Y|yes|YES)
            INSTALL_NVIDIA_OPTIONAL=1
            echo "Nvidia-specific Hyprland options will be enabled."
            break
            ;;
        n|N|no|NO)
            INSTALL_NVIDIA_OPTIONAL=0
            echo "Skipping Nvidia-specific Hyprland options."
            break
            ;;
        *)
            echo "Please answer 'y' or 'n'."
            ;;
    esac
done

echo "Enabling COPR repository: lionheartp/Hyprland..."
if ! dnf copr --help >/dev/null 2>&1; then
    echo "ERROR: The dnf COPR plugin is required to enable the Hyprland repositories." >&2
    exit 1
fi
if ! dnf -y copr enable lionheartp/Hyprland; then
    echo "ERROR: Failed to enable COPR repository lionheartp/Hyprland."
    exit 1
fi

echo "Enabling COPR repository: leloubil/wl-clip-persist..."
if ! dnf -y copr enable leloubil/wl-clip-persist; then
    echo "ERROR: Failed to enable COPR repository leloubil/wl-clip-persist."
    exit 1
fi

echo "Enabling COPR repository: tofik/nwg-shell..."
if ! dnf -y copr enable tofik/nwg-shell; then
    echo "ERROR: Failed to enable COPR repository tofik/nwg-shell."
    exit 1
fi

echo "Installing RPM Fusion repositories..."
if ! dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$FEDORA_VERSION.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$FEDORA_VERSION.noarch.rpm"; then
    echo "ERROR: Failed to install RPM Fusion repositories."
    exit 1
fi

echo "Updating system packages..."
if ! dnf upgrade -y; then
    echo "ERROR: Failed to update system packages. Aborting installation." >&2
    exit 1
fi

echo "Installing Flatpak..."
if ! dnf -y install flatpak; then
    echo "ERROR: Failed to install Flatpak."
    exit 1
fi

echo "Adding Flathub flatpak remote..."
if ! flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
    echo "ERROR: Failed to add Flathub remote."
    exit 1
fi

# Add more Flatpaks here when you want them installed with the optional prompt.
FLATPAK_OPTIONAL_PACKAGES=(
    com.obsproject.Studio
    com.teamspeak.TeamSpeak
    com.vysp3r.ProtonPlus
    org.gtk.Gtk3theme.adw-gtk3-dark
    org.signal.Signal
    org.upscayl.Upscayl
    io.missioncenter.MissionCenter
)

INSTALL_FLATPAK_OPTIONAL_PACKAGES=0
while true; do
    echo ""
    echo "Optional Flatpak packages:"
    for flatpak_package in "${FLATPAK_OPTIONAL_PACKAGES[@]}"; do
        echo "  - $flatpak_package"
    done
    read -r -p "Do you want to install optional Flatpak packages? (y/n): " flatpak_choice || exit 1
    case "$flatpak_choice" in
        y|Y|yes|YES)
            INSTALL_FLATPAK_OPTIONAL_PACKAGES=1
            echo "Optional Flatpak packages will be installed."
            break
            ;;
        n|N|no|NO)
            INSTALL_FLATPAK_OPTIONAL_PACKAGES=0
            echo "Skipping optional Flatpak packages."
            break
            ;;
        *)
            echo "Please answer 'y' or 'n'."
            ;;
    esac
done

# --- Browser selection ---
BROWSER_CHOICE="none"
while true; do
    echo ""
    echo "Browser setup option:"
    echo "  0. Skip browser installation (recommended - you're installing your own)"
    echo "  1. Firefox"
    echo "  2. Brave"
    echo "  3. Vivaldi"
    read -r -p "Choose browser option (0-3): " browser_choice || exit 1
    case "$browser_choice" in
        0|"")
            BROWSER_CHOICE="none"
            echo "Skipping browser installation."
            break
            ;;
        1)
            BROWSER_CHOICE="firefox"
            echo "Firefox will be installed."
            break
            ;;
        2)
            BROWSER_CHOICE="brave"
            echo "Brave will be installed."
            break
            ;;
        3)
            BROWSER_CHOICE="vivaldi"
            echo "Vivaldi will be installed."
            break
            ;;
        *)
            echo "Please enter 0, 1, 2 or 3."
            ;;
    esac
done

echo "Installing Noctalia Hyprland meta package..."
if ! dnf in noctalia-hyprland-meta -y; then
    echo "ERROR: Failed to install noctalia-hyprland-meta."
    exit 1
fi

# --- Gaming package selection ---
INSTALL_GAMING_PACKAGES=0
while true; do
    echo ""
    read -r -p "Do you want to install gaming packages (steam, mangohud, wine, winetricks)? (y/n): " gaming_choice || exit 1
    case "$gaming_choice" in
        y|Y|yes|YES)
            INSTALL_GAMING_PACKAGES=1
            echo "Gaming packages will be installed."
            break
            ;;
        n|N|no|NO)
            INSTALL_GAMING_PACKAGES=0
            echo "Skipping gaming package installation."
            break
            ;;
        *)
            echo "Please answer 'y' or 'n'."
            ;;
    esac
done

# --- Bluetooth package selection ---
INSTALL_BLUETOOTH_PACKAGES=0
while true; do
    echo ""
    read -r -p "Do you want to install Bluetooth packages and enable the Bluetooth service? (y/n): " bluetooth_choice || exit 1
    case "$bluetooth_choice" in
        y|Y|yes|YES)
            INSTALL_BLUETOOTH_PACKAGES=1
            echo "Bluetooth packages will be installed and service will be enabled."
            break
            ;;
        n|N|no|NO)
            INSTALL_BLUETOOTH_PACKAGES=0
            echo "Skipping Bluetooth package installation and service."
            break
            ;;
        *)
            echo "Please answer 'y' or 'n'."
            ;;
    esac
done

# Define the list of core packages to install using dnf.
# Some packages are provided by COPR or third-party repositories.
PACKAGES=(
    # --- Core session / login (required for Hyprland + Noctalia Greeter to boot) ---
    dbus                        # D-Bus for greetd / greeter session plumbing
    polkit                      # Polkit backend service (decides what's allowed)
    xfce-polkit                 # Polkit authentication agent
    accountsservice              # AccountsService for greeter avatars
    greetd                       # Login manager daemon for Noctalia Greeter
    noctalia-greeter              # Noctalia login greeter for greetd
    hyprland                      # Compositor
    xdg-desktop-portal-hyprland   # Hyprland portal backend
    xdg-desktop-portal-gtk        # GTK implementation of xdg-desktop-portal
    xorg-x11-server-Xwayland      # Xwayland compatibility layer
    mesa-dri-drivers              # OpenGL drivers
    mesa-vulkan-drivers           # Vulkan drivers used by wlroots stack
    qt6-qtbase                    # Qt6 base libraries and tools
    qt6-qtwebsockets               # Websocket support (used by Noctalia)
    qt6ct                          # Qt platform theme
    matugen                        # Noctalia's wallpaper-based color-scheme generator
    xdg-user-dirs                   # Manage user directories (~/Downloads, ~/Pictures, etc.)

    # --- Power management ---
    power-profiles-daemon            # Power profile switching
    upower                            # Battery/power status
    cpupower                          # CPU frequency scaling utilities

    # --- Desktop applications and screenshot tools ---
    wl-clip-persist                    # Clipboard persistence - started in exec_once
    thunar                              # File manager - SUPER+E
    grim                                  # Screenshot capture - used by both hyprshot and satty.sh
    slurp                                  # Region selector - used by both hyprshot and satty.sh
    hyprshot                                # SUPER+PrintScreen / Alt+PrintScreen / Shift+PrintScreen
    kitty                                    # Terminal
    kitty-shell-integration                   # Kitty shell integration
    kitty-terminfo                              # Kitty terminfo
    jq                                            # JSON parser for Satty release metadata

    # --- Utilities ---
    unrar                            # RAR archive support
    unzip                             # ZIP archive support
    p7zip                              # 7z archive support
    p7zip-plugins                       # Additional 7z formats
    fastfetch                            # System info display
    fish                                  # Shell
    grub2-tools                            # GRUB tooling
    os-prober                               # OS prober for GRUB (dual-boot detection)
    pavucontrol                              # PulseAudio/PipeWire volume control

    # --- Media and desktop utilities ---
    nwg-look                          # GTK look-and-feel config
    nwg-displays                       # Monitor layout tool
    gst-plugins-good                    # GStreamer plugins (broad codec/media support)
    gst-plugins-ugly                     # GStreamer plugins (nonfree codecs, from RPM Fusion)
    gst-libav                             # GStreamer plugins (ffmpeg-backed codecs)
    dejavu-sans-fonts                      # Fallback font - kept to avoid missing-glyph rendering
    google-noto-emoji-fonts                 # Emoji fallback font
)

# --- Main Installation Functions ---

install_dnf_packages() {
    dnf install -y "$@"
}

install_gaming_packages() {
    if [ "$INSTALL_GAMING_PACKAGES" -ne 1 ]; then
        return 0
    fi

    echo -e "\n--- Gaming Packages Installation ---"
    echo "Installing gaming packages..."
    if ! dnf in steam mangohud wine winetricks -y; then
        echo "Warning: Some gaming packages failed to install."
    fi
}

install_bluetooth_packages() {
    if [ "$INSTALL_BLUETOOTH_PACKAGES" -ne 1 ]; then
        return 0
    fi

    echo -e "\n--- Bluetooth Installation ---"
    echo "Installing Bluetooth packages..."
    if ! install_dnf_packages bluez blueman; then
        echo "Warning: Some Bluetooth packages failed to install."
    fi

    echo "Enabling Bluetooth service..."
    systemctl enable bluetooth

    if [ $? -ne 0 ]; then
        echo "Warning: Failed to enable Bluetooth service."
    fi
}

ensure_flatpak_available() {
    if command -v flatpak >/dev/null 2>&1; then
        return 0
    fi

    echo "ERROR: Flatpak is not installed yet. Skipping Flatpak-based installs."
    return 1
}

enable_accounts_daemon() {
    echo -e "\n--- AccountsService Setup ---"
    echo "Enabling accounts-daemon service..."
    if systemctl enable accounts-daemon; then
        echo "accounts-daemon service enabled."
    else
        echo "Warning: Failed to enable accounts-daemon.service."
    fi
}

setup_noctalia_greeter() {
    echo -e "\n--- Noctalia Greeter Setup ---"

    local greetd_config_file="/etc/greetd/config.toml"
    local greeter_user="greeter"
    local session_bin="/usr/bin/noctalia-greeter-session"

    if ! command -v noctalia-greeter-session >/dev/null 2>&1; then
        echo "ERROR: noctalia-greeter-session is missing; refusing to configure greetd." >&2
        return 1
    fi
    session_bin=$(command -v noctalia-greeter-session)

    if ! id -u "$greeter_user" >/dev/null 2>&1; then
        echo "Creating greeter user '$greeter_user'..."
        useradd -r -s /usr/bin/nologin -d /var/lib/noctalia-greeter "$greeter_user" || return 1
    fi

    echo "Preparing greeter state directory..."
    mkdir -p /var/lib/noctalia-greeter || return 1
    chown -R "$greeter_user:$greeter_user" /var/lib/noctalia-greeter || return 1

    if [ -f "$greetd_config_file" ]; then
        cp -a --backup=numbered "$greetd_config_file" "$greetd_config_file.bak" || return 1
    fi

    echo "Writing greetd configuration to $greetd_config_file..."
    mkdir -p /etc/greetd || return 1
    local config_tmp
    config_tmp=$(mktemp /etc/greetd/config.toml.XXXXXXXX) || return 1
    if ! cat > "$config_tmp" <<EOF
[terminal]
vt = 1

[default_session]
command = "$session_bin"
user = "$greeter_user"
EOF
    then
        rm -f "$config_tmp"
        return 1
    fi
    mv -f "$config_tmp" "$greetd_config_file" || { rm -f "$config_tmp"; return 1; }

    if [ -x /usr/share/noctalia-greeter/setup_greetd_pam.sh ]; then
        echo "Configuring greetd PAM integration for Noctalia Greeter..."
        if ! bash /usr/share/noctalia-greeter/setup_greetd_pam.sh; then
            echo "Warning: greetd PAM setup failed."
        fi
    else
        echo "Warning: /usr/share/noctalia-greeter/setup_greetd_pam.sh was not found."
    fi
}

enable_greetd_service() {
    echo -e "\n--- Display Manager Setup ---"
    echo "Enabling greetd service..."
    if ! systemctl enable greetd; then
        echo "ERROR: Failed to enable greetd.service; boot target will not be changed." >&2
        return 1
    fi
    echo "greetd service enabled."

    echo "Setting default boot target to graphical.target..."
    if ! systemctl set-default graphical.target; then
        echo "ERROR: Failed to set the default boot target." >&2
        return 1
    fi
    echo "Default target set to graphical.target."

    local current_target
    current_target=$(systemctl get-default 2>/dev/null || true)
    if [ -n "$current_target" ]; then
        echo "Current default target: $current_target"
    fi
}

install_flatpak_optional_packages() {
    if [ "$INSTALL_FLATPAK_OPTIONAL_PACKAGES" -ne 1 ]; then
        return 0
    fi

    if ! ensure_flatpak_available; then
        return 1
    fi

    echo -e "\n--- Optional Flatpak Packages Installation ---"
    echo "Installing optional Flatpak packages..."

    local flatpak_package
    local failed_packages=()

    for flatpak_package in "${FLATPAK_OPTIONAL_PACKAGES[@]}"; do
        echo "Installing $flatpak_package..."
        if ! flatpak install -y flathub "$flatpak_package"; then
            echo "Warning: Failed to install $flatpak_package."
            failed_packages+=("$flatpak_package")
        fi
    done

    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "Warning: Some optional Flatpak packages failed to install: ${failed_packages[*]}"
    fi
}

install_browser_choice() {
    if [ "$BROWSER_CHOICE" = "none" ]; then
        return 0
    fi

    if [ "$BROWSER_CHOICE" != "firefox" ] && ! ensure_flatpak_available; then
        return 1
    fi

    echo -e "\n--- Browser Installation ---"

    case "$BROWSER_CHOICE" in
        firefox)
            echo "Installing Firefox via dnf..."
            if ! dnf in firefox -y; then
                echo "Warning: Firefox installation failed."
            fi
            ;;
        brave)
            echo "Installing Brave via Flatpak..."
            if ! flatpak install -y flathub com.brave.Browser; then
                echo "Warning: Brave installation failed."
            fi
            ;;
        vivaldi)
            echo "Installing Vivaldi via Flatpak..."
            if ! flatpak install -y flathub com.vivaldi.Vivaldi; then
                echo "Warning: Vivaldi installation failed."
            fi
            ;;
        *)
            echo "Warning: Unknown browser choice '$BROWSER_CHOICE'. Skipping browser installation."
            ;;
    esac
}

install_satty_flatpak() {
    echo -e "\n--- Satty Flatpak Installation ---"
    echo "Installing the Satty Flatpak from its GitHub release."

    if ! ensure_flatpak_available; then
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "Warning: curl is not installed. Skipping Satty Flatpak install."
        return 0
    fi

    local release_api="https://api.github.com/repos/Satty-org/Satty/releases/latest"
    local release_json
    local download_url
    local tmp_dir
    local bundle_path

    echo "Fetching latest Satty release metadata..."
    if ! release_json=$(curl -fsSL "$release_api"); then
        echo "Warning: Failed to fetch Satty release metadata. Skipping Satty install."
        return 0
    fi

    download_url=$(printf '%s\n' "$release_json" | jq -r '[.assets[]? | select(.name | test("^satty-v[^/]+[.]flatpak$")) | .browser_download_url | select(test("^https://github[.]com/Satty-org/Satty/releases/download/[^/]+/satty-v[^/]+[.]flatpak$"))][0] // empty')

    if [ -z "$download_url" ]; then
        echo "Warning: Could not find a Satty Flatpak asset in the latest release."
        return 0
    fi

    tmp_dir=$(mktemp -d) || return 1
    bundle_path="$tmp_dir/${download_url##*/}"

    echo "Downloading ${bundle_path##*/}..."
    if ! curl -fL --retry 2 --connect-timeout 15 --max-time 180 "$download_url" -o "$bundle_path"; then
        echo "Warning: Failed to download Satty Flatpak bundle."
        rm -rf "$tmp_dir"
        return 0
    fi

    echo "Installing Satty Flatpak bundle..."
    if flatpak install -y --system "$bundle_path"; then
        echo "Satty Flatpak installed successfully."
    else
        echo "Warning: Satty Flatpak installation failed."
    fi

    rm -rf "$tmp_dir"
}

install_starship() {
    echo -e "\n--- Starship Installation ---"
    echo "Installing Starship prompt..."

    if dnf install -y starship; then
        echo "Starship installed successfully."
    else
        echo "Warning: Starship installation failed."
    fi
}

# Deploy configuration files from ~/config_files to ~/.config, backing up originals.
deploy_configs() {
    echo "Deploying configuration files..."

    local config_source_root="$CONFIG_SOURCE_DIR"
    local stage_dir item name target backup

    sudo -u "$ACTUAL_USER" mkdir -p "$CONFIG_DIR" || return 1
    stage_dir=$(sudo -u "$ACTUAL_USER" mktemp -d "$CONFIG_DIR/.installer-stage.XXXXXXXX") || return 1
    if ! sudo -u "$ACTUAL_USER" cp -a "$config_source_root/." "$stage_dir/"; then
        echo "ERROR: Failed to stage configuration files." >&2
        sudo -u "$ACTUAL_USER" rm -rf -- "$stage_dir"
        return 1
    fi

    for item in "$stage_dir"/* "$stage_dir"/.[!.]* "$stage_dir"/..?*; do
        [[ -e "$item" || -L "$item" ]] || continue
        name=${item##*/}
        target="$CONFIG_DIR/$name"
        backup=""
        if [[ -e "$target" || -L "$target" ]]; then
            backup="$target.bak.$(date +%s)"
            if [[ -e "$backup" || -L "$backup" ]]; then
                echo "ERROR: Backup path already exists: $backup" >&2
                sudo -u "$ACTUAL_USER" rm -rf -- "$stage_dir"
                return 1
            fi
            if ! sudo -u "$ACTUAL_USER" mv -- "$target" "$backup"; then
                sudo -u "$ACTUAL_USER" rm -rf -- "$stage_dir"
                return 1
            fi
            echo "Backed up $name to ${backup##*/}."
        fi
        if ! sudo -u "$ACTUAL_USER" mv -- "$item" "$target"; then
            if [[ -n "$backup" ]]; then
                sudo -u "$ACTUAL_USER" mv -- "$backup" "$target"
            fi
            sudo -u "$ACTUAL_USER" rm -rf -- "$stage_dir"
            return 1
        fi
    done
    sudo -u "$ACTUAL_USER" rmdir -- "$stage_dir" || return 1
    echo "Configuration files deployed successfully."
}

# Updates the polkit-agent startup line if it's still on the old polkit-gnome pattern.
update_hypr_startup_config() {
    local startup_file="$ACTUAL_USER_HOME/.config/hypr/startup.lua"
    local polkit_gnome_match='polkit-gnome-authentication-agent-1'
    local xfce_polkit_line='    "sleep 1 && /usr/libexec/xfce-polkit",'

    if [ ! -f "$startup_file" ]; then
        echo "Warning: Hyprland startup file '$startup_file' not found."
        return 0
    fi

    if grep -qF "/usr/libexec/xfce-polkit" "$startup_file"; then
        echo "startup.lua already starts xfce-polkit - nothing to change."
    elif grep -qF "$polkit_gnome_match" "$startup_file"; then
        echo "Updating Hyprland startup command in $startup_file..."
        sudo -u "$ACTUAL_USER" sed -i "/polkit-gnome-authentication-agent-1/c\\${xfce_polkit_line}" "$startup_file"
        if grep -qF "/usr/libexec/xfce-polkit" "$startup_file"; then
            echo "Hyprland xfce-polkit startup command updated successfully."
        else
            echo "Warning: Failed to update polkit startup command in '$startup_file'."
        fi
    else
        echo "Warning: No recognized polkit startup line found in '$startup_file'. Add one manually:"
        echo "  $xfce_polkit_line"
    fi

    if [ "$INSTALL_NVIDIA_OPTIONAL" -eq 1 ]; then
        if grep -qF 'local enable_nvidia_optional = false' "$startup_file"; then
            echo "Enabling Nvidia-specific Hyprland options in $startup_file..."
            sudo -u "$ACTUAL_USER" sed -i 's|^local enable_nvidia_optional = false$|local enable_nvidia_optional = true|' "$startup_file"
        else
            echo "Warning: Expected Nvidia toggle line not found in '$startup_file'."
        fi
    fi
}

# Set executable permissions for scripts
set_permissions() {
    local scripts_path="$ACTUAL_USER_HOME/.config/hypr/Scripts"

    if [ -d "$scripts_path" ]; then
        echo "Setting execution permissions for scripts..."
        sudo -u "$ACTUAL_USER" find "$scripts_path" -type f -exec chmod +x {} +
    else
        echo "Warning: Hyprland scripts directory '$scripts_path' not found."
    fi
}

# Set default file manager to Thunar
set_default_file_manager() {
    echo ""
    echo "Setting Thunar as default file manager..."
    if sudo -u "$ACTUAL_USER" mkdir -p "$ACTUAL_USER_HOME/.config" &&
        sudo -u "$ACTUAL_USER" xdg-mime default thunar.desktop inode/directory application/x-gnome-saved-search; then
        echo "Default file manager set to Thunar."
    else
        echo "Warning: Failed to set Thunar as default file manager." >&2
    fi
}

# Create GTK bookmarks for Thunar
create_thunar_bookmarks() {
    echo ""
    echo "Creating Thunar bookmarks..."

    local gtk_dir="$ACTUAL_USER_HOME/.config/gtk-3.0"
    local bookmarks_file="$gtk_dir/bookmarks"

    sudo -u "$ACTUAL_USER" mkdir -p "$gtk_dir"

    sudo -u "$ACTUAL_USER" tee "$bookmarks_file" >/dev/null <<EOF
file://$ACTUAL_USER_HOME/Documents
file://$ACTUAL_USER_HOME/Downloads
file://$ACTUAL_USER_HOME/Pictures
file://$ACTUAL_USER_HOME/Music
file://$ACTUAL_USER_HOME/Videos
file://$ACTUAL_USER_HOME/.config/hypr
EOF

    echo "Thunar bookmarks created at $bookmarks_file."
}

# Copy backup config files if available
copy_backup_configs() {
    echo -e "\n--- Optional: Copy Backup Configs ---"

    local config_source="$SCRIPT_DIR/backup/.config"

    if [[ ! -d "$config_source" ]]; then
        echo "No backup folder found at $SCRIPT_DIR/backup/.config"
        echo "Skipping backup config restoration."
        return 0
    fi

    echo "Found backup configs at: $config_source"
    read -r -p "Do you want to restore config files from backup? (y/N): " backup_response || return 1

    if [[ "$backup_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Copying config files from backup to $CONFIG_DIR..."
        sudo -u "$ACTUAL_USER" cp -R "$config_source/." "$CONFIG_DIR/"

        if [ $? -eq 0 ]; then
            echo "Config files copied successfully!"
            if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
                echo "Detected Hyprland environment. Reloading Hyprland to apply new configs..."
                hyprctl reload 2>/dev/null || echo "Note: Could not reload Hyprland. You may need to restart it manually."
                sleep 2
            fi
        else
            echo "ERROR: Failed to copy backup config files." >&2
            return 1
        fi
    else
        echo "Skipping backup config restoration."
    fi
}

post_install_hyprland_checks() {
    local session_file="/usr/share/wayland-sessions/hyprland.desktop"

    echo -e "\n--- Hyprland Session Sanity Check ---"

    if [ ! -f "$session_file" ]; then
        echo "Warning: $session_file was not found."
        echo "greetd will not be able to launch Hyprland if no Wayland session is installed."
        echo "Try: dnf install -y hyprland"
    else
        echo "Found Hyprland session file: $session_file"
    fi

    if systemctl list-unit-files | grep -q '^greetd\.service'; then
        echo "Detected greetd on this system."
        if ! systemctl is-enabled greetd >/dev/null 2>&1; then
            echo "Note: greetd.service is not enabled."
            echo "Enable it with: systemctl enable greetd"
        fi
    fi
}

# --- Main Installation Flow ---

echo "Starting Hyprland Dotfiles Installation..."

echo "Installing required core packages via dnf..."
echo "installing core packages in 3..."
echo "2..."
echo "1!"
echo "Please Wait..."
if ! install_dnf_packages "${PACKAGES[@]}"; then
    echo "ERROR: Failed to install core packages. Aborting installation."
    exit 1
fi

install_gaming_packages
install_bluetooth_packages
enable_accounts_daemon
setup_noctalia_greeter || exit 1

echo "Updating user directories..."
sudo -u "$ACTUAL_USER" xdg-user-dirs-update

if [ $? -ne 0 ]; then
    echo "Warning: Failed to update user directories."
fi

echo "Base package installation complete!"
echo "--------------------------------------------------------"
echo "Proceeding with post-install configuration..."
echo "--------------------------------------------------------"

deploy_configs || { echo "ERROR: Configuration deployment failed; installation stopped." >&2; exit 1; }
copy_backup_configs || { echo "ERROR: Backup config restoration failed; installation stopped." >&2; exit 1; }
update_hypr_startup_config
create_thunar_bookmarks
set_permissions
set_default_file_manager
enable_greetd_service || exit 1
install_flatpak_optional_packages
install_browser_choice
install_satty_flatpak
install_starship
post_install_hyprland_checks

echo ""
echo "Installation complete! Time to reboot."
while true; do
    read -r -p "Would you like to reboot now? (y/n): " reboot_choice || exit 1
    case "$reboot_choice" in
        y|Y|yes|YES)
            echo "Rebooting now..."
            sudo reboot now
            break
            ;;
        n|N|no|NO)
            echo ""
            echo "Installation complete! Reboot whenever you're ready."
            break
            ;;
        *)
            echo "Please answer 'y' or 'n'."
            ;;
    esac
done
