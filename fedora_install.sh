#!/bin/bash

export LC_MESSAGES=C
export LANG=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Ensure running as root before collecting interactive input.
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

if ! command -v dnf >/dev/null 2>&1; then
    echo "ERROR: dnf was not found. This installer is intended for Fedora."
    exit 1
fi

# --- Pre-flight confirmation ---
echo "This script will install custom dot-files for Hyprland (trimmed/personal edition). Use at your own risk."
while true; do
    read -r -p "Would you like to proceed? (y/n): " proceed
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
    read -r -p "Are you using an Nvidia GPU? (y/n): " nvidia_choice
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
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; then
    echo "ERROR: Failed to install RPM Fusion repositories."
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
    read -r -p "Do you want to install optional Flatpak packages? (y/n): " flatpak_choice
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
# You said you'll install your browser yourself - just pick 0 here. The prompt
# is left in (rather than deleted) in case you ever want it on a future machine.
BROWSER_CHOICE="none"
while true; do
    echo ""
    echo "Browser setup option:"
    echo "  0. Skip browser installation (recommended - you're installing your own)"
    echo "  1. Firefox"
    echo "  2. Brave"
    echo "  3. Vivaldi"
    read -r -p "Choose browser option (0-3): " browser_choice
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

# --- Configuration ---
# Get the actual user running the script (not root)
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER=$(logname 2>/dev/null)
fi

if [ -z "$ACTUAL_USER" ] || [ "$ACTUAL_USER" = "root" ]; then
    echo "ERROR: Could not determine a non-root target user. Run this script with sudo from your normal user account."
    exit 1
fi

ACTUAL_USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
if [ -z "$ACTUAL_USER_HOME" ] || [ ! -d "$ACTUAL_USER_HOME" ]; then
    echo "ERROR: Could not determine home directory for user '$ACTUAL_USER'."
    exit 1
fi

REPO_DIR="$SCRIPT_DIR"
CONFIG_DIR="$ACTUAL_USER_HOME/.config"

# Validate repo directory
if [ ! -d "$REPO_DIR/.config" ]; then
    echo "ERROR: Script must be run from the repository root directory."
    exit 1
fi

if [ ! -d "$REPO_DIR/.config/hypr" ]; then
    echo "ERROR: Could not find the Hyprland config directory inside your repository at '$REPO_DIR/.config/hypr'."
    exit 1
fi

# --- Gaming package selection ---
INSTALL_GAMING_PACKAGES=0
while true; do
    echo ""
    read -r -p "Do you want to install gaming packages (steam, mangohud, wine, winetricks)? (y/n): " gaming_choice
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
    read -r -p "Do you want to install Bluetooth packages and enable the Bluetooth service? (y/n): " bluetooth_choice
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

# NOTE: The EasyEffects / Dolby audio prompt from the upstream script has been
# removed entirely on purpose - you said you don't use either, so there is
# nothing to add to PACKAGES and no Dolby PipeWire profile step to run.

# Define the list of core packages to install using dnf.
# Some packages are provided by COPR or third-party repositories.
PACKAGES=(
    # --- Core session / login (required for Hyprland + Noctalia Greeter to boot) ---
    dbus                        # D-Bus for greetd / greeter session plumbing
    polkit                      # Polkit backend service (decides what's allowed)
    xfce-polkit                 # Polkit authentication agent (shows the prompt) - matches your live startup.lua
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
    qt6ct                          # Qt platform theme - referenced directly in startup.lua's env table
    matugen                        # Noctalia's wallpaper-based color-scheme generator
    xdg-user-dirs                   # Manage user directories (~/Downloads, ~/Pictures, etc.)

    # --- Power management (laptop-relevant, always kept) ---
    power-profiles-daemon            # Power profile switching
    upower                            # Battery/power status
    cpupower                          # CPU frequency scaling utilities

    # --- Confirmed required by your live keybind.lua / startup.lua / satty.sh ---
    wl-clip-persist                    # Clipboard persistence - started in exec_once
    thunar                              # File manager - SUPER+E
    grim                                  # Screenshot capture - used by both hyprshot and satty.sh
    slurp                                  # Region selector - used by both hyprshot and satty.sh
    hyprshot                                # SUPER+PrintScreen / Alt+PrintScreen / Shift+PrintScreen
    kitty                                    # Terminal itself - SUPER+Return (NOT in the upstream array, added here)
    kitty-shell-integration                   # Kitty shell integration
    kitty-terminfo                              # Kitty terminfo
    jq                                            # Required by SUPER+SHIFT+CTRL+arrow move/swap binds (NOT in the upstream array, added here)

    # --- Your explicit keeps ---
    unrar                            # RAR archive support
    unzip                             # ZIP archive support
    p7zip                              # 7z archive support
    p7zip-plugins                       # Additional 7z formats
    fastfetch                            # System info display
    fish                                  # Shell
    grub2-tools                            # GRUB tooling
    os-prober                               # OS prober for GRUB (dual-boot detection)
    pavucontrol                              # PulseAudio/PipeWire volume control

    # --- Not explicitly discussed during trimming - kept by default, see chat notes ---
    nwg-look                          # GTK look-and-feel config - README-recommended for theming
    nwg-displays                       # Monitor layout tool - README-recommended for hyprland.conf setup
    gst-plugins-good                    # GStreamer plugins (broad codec/media support)
    gst-plugins-ugly                     # GStreamer plugins (nonfree codecs, from RPM Fusion)
    gst-libav                             # GStreamer plugins (ffmpeg-backed codecs)
    dejavu-sans-fonts                      # Fallback font - kept to avoid missing-glyph rendering
    google-noto-emoji-fonts                 # Emoji fallback font
)

# --- Color Functions ---
disable_colors() {
    unset ALL_OFF BOLD BLUE GREEN RED YELLOW CYAN MAGENTA
}

enable_colors() {
    if tput setaf 0 &>/dev/null; then
        ALL_OFF="$(tput sgr0)"
        BOLD="$(tput bold)"
        RED="${BOLD}$(tput setaf 1)"
        GREEN="${BOLD}$(tput setaf 2)"
        YELLOW="${BOLD}$(tput setaf 3)"
        BLUE="${BOLD}$(tput setaf 4)"
        MAGENTA="${BOLD}$(tput setaf 5)"
        CYAN="${BOLD}$(tput setaf 6)"
    else
        ALL_OFF="\e[0m"
        BOLD="\e[1m"
        RED="${BOLD}\e[31m"
        GREEN="${BOLD}\e[32m"
        YELLOW="${BOLD}\e[33m"
        BLUE="${BOLD}\e[34m"
        MAGENTA="${BOLD}\e[35m"
        CYAN="${BOLD}\e[36m"
    fi
    readonly ALL_OFF BOLD BLUE GREEN RED YELLOW CYAN MAGENTA
}

if [[ -t 2 ]]; then
    enable_colors
else
    disable_colors
fi

# --- Main Installation Functions ---

install_dnf_packages() {
    local installable_packages=()
    local unavailable_packages=()
    local pkg

    for pkg in "$@"; do
        if rpm -q "$pkg" >/dev/null 2>&1 || dnf -q list --available "$pkg" >/dev/null 2>&1; then
            installable_packages+=("$pkg")
        else
            unavailable_packages+=("$pkg")
        fi
    done

    if [ ${#unavailable_packages[@]} -gt 0 ]; then
        echo "Skipping unavailable packages: ${unavailable_packages[*]}"
    fi

    if [ ${#installable_packages[@]} -eq 0 ]; then
        echo "ERROR: No installable packages were found in the provided package list."
        return 1
    fi

    dnf install -y "${installable_packages[@]}"
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

    if command -v noctalia-greeter-session >/dev/null 2>&1; then
        session_bin=$(command -v noctalia-greeter-session)
    fi

    if ! id -u "$greeter_user" >/dev/null 2>&1; then
        echo "Creating greeter user '$greeter_user'..."
        useradd -r -s /usr/bin/nologin -d /var/lib/noctalia-greeter "$greeter_user"
    fi

    echo "Preparing greeter state directory..."
    mkdir -p /var/lib/noctalia-greeter
    chown -R "$greeter_user:$greeter_user" /var/lib/noctalia-greeter

    if [ -f "$greetd_config_file" ]; then
        cp -a "$greetd_config_file" "$greetd_config_file.bak.$(date +%s)"
    fi

    echo "Writing greetd configuration to $greetd_config_file..."
    mkdir -p /etc/greetd
    cat > "$greetd_config_file" <<EOF
[terminal]
vt = 1

[default_session]
command = "$session_bin"
user = "$greeter_user"
EOF

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
    if systemctl enable greetd; then
        echo "greetd service enabled."
    else
        echo "Warning: Failed to enable greetd.service."
    fi

    echo "Setting default boot target to graphical.target..."
    if systemctl set-default graphical.target; then
        echo "Default target set to graphical.target."
    else
        echo "Warning: Failed to set default target to graphical.target."
    fi

    local current_target
    current_target=$(systemctl get-default 2>/dev/null || true)
    if [ -n "$current_target" ]; then
        echo "Current default target: $current_target"
    fi
}

# NOTE: install_flatpak_optional_packages, install_browser_choice,
# install_satty_flatpak, and install_starship are defined here at top level.
# In the upstream script these four functions were (accidentally, as far as we
# can tell) defined *inside* deploy_configs()'s success branch, meaning they
# didn't exist yet if that cp ever failed. Moved out here so they always exist.

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
    echo "(Fedora ships no native satty package in its own repos; satty.sh already"
    echo " auto-detects a native binary first and falls back to this Flatpak, so"
    echo " installing it here keeps SUPER+A working either way.)"

    if ! ensure_flatpak_available; then
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "Warning: curl is not installed. Skipping Satty Flatpak install."
        return 0
    fi

    local release_api="https://api.github.com/repos/Satty-org/Satty/releases/latest"
    local release_json
    local asset_name
    local download_url
    local tmp_dir
    local bundle_path

    echo "Fetching latest Satty release metadata..."
    if ! release_json=$(curl -fsSL "$release_api"); then
        echo "Warning: Failed to fetch Satty release metadata. Skipping Satty install."
        return 0
    fi

    asset_name=$(printf '%s\n' "$release_json" | sed -n 's/.*"name": "\(satty-v[^"]*\.flatpak\)".*/\1/p' | head -n 1)
    download_url=$(printf '%s\n' "$release_json" | sed -n 's/.*"browser_download_url": "\(https:[^"]*satty-v[^"]*\.flatpak\)".*/\1/p' | head -n 1)

    if [ -z "$asset_name" ] || [ -z "$download_url" ]; then
        echo "Warning: Could not find a Satty Flatpak asset in the latest release."
        return 0
    fi

    tmp_dir=$(mktemp -d)
    bundle_path="$tmp_dir/$asset_name"

    echo "Downloading $asset_name..."
    if ! curl -fL "$download_url" -o "$bundle_path"; then
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

    if curl -sS https://starship.rs/install.sh | sh -s -- -y; then
        echo "Starship installed successfully."
    else
        echo "Warning: Starship installation failed."
    fi
}

# Deploy configuration files from repo/.config to ~/.config
#
# IMPORTANT if you're re-running this on your existing laptop rather than a
# fresh install: this copies THIS REPO'S .config/hypr over your live
# ~/.config/hypr (after backing the old one up with a .bak.<timestamp>
# suffix). If your live startup.lua/keybind.lua have hand edits you want to
# keep (e.g. the two exec_once lines you removed for gnome-keyring and
# easyeffects), copy your live files into $REPO_DIR/.config/hypr/ BEFORE
# running this script, or this step will overwrite them with the repo's
# template and you'll need to reapply your edits from the backup.
deploy_configs() {
    echo "Deploying configuration files..."

    CONFIG_SOURCE_ROOT="$REPO_DIR/.config"

    if [ ! -d "$CONFIG_SOURCE_ROOT" ]; then
        echo "FATAL ERROR: Could not find the '.config' directory inside your repository at '$REPO_DIR'."
        return
    fi

    # Ensure target .config directory exists
    sudo -u "$ACTUAL_USER" mkdir -p "$CONFIG_DIR"

    # Back up any existing configs that would be overwritten
    BACKUP_TIMESTAMP=$(date +%s)
    echo "Backing up existing configuration files..."

    for item in "$CONFIG_SOURCE_ROOT"/*; do
        name=$(basename "$item")
        target="$CONFIG_DIR/$name"
        if [ "$name" = "hypr" ]; then
            continue
        fi

        if [ -e "$target" ] || [ -L "$target" ]; then
            echo "  -> Backing up: $name to $name.bak.$BACKUP_TIMESTAMP"
            mv "$target" "$CONFIG_DIR/$name.bak.$BACKUP_TIMESTAMP"
        fi
    done

    if [ -e "$CONFIG_DIR/hypr" ] || [ -L "$CONFIG_DIR/hypr" ]; then
        echo "  -> Backing up: hypr to hypr.bak.$BACKUP_TIMESTAMP"
        mv "$CONFIG_DIR/hypr" "$CONFIG_DIR/hypr.bak.$BACKUP_TIMESTAMP"
    fi

    # Copy all configuration files from repo/.config to ~/.config
    echo "Copying configuration files from $CONFIG_SOURCE_ROOT to $CONFIG_DIR..."
    cp -rf "$CONFIG_SOURCE_ROOT"/* "$CONFIG_DIR"/

    if [ $? -eq 0 ]; then
        echo "Configuration files copied successfully!"
        chown -R "$ACTUAL_USER:$ACTUAL_USER" "$CONFIG_DIR"
    else
        echo "ERROR: Failed to copy configuration files."
    fi
}

# Updates the polkit-agent startup line if it's still on the old
# polkit-gnome pattern. If your startup.lua already has the xfce-polkit
# line (which yours does), this is a no-op and says so instead of printing
# a confusing "not found" warning.
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
        sed -i "/polkit-gnome-authentication-agent-1/c\\${xfce_polkit_line}" "$startup_file"
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
            sed -i 's|^local enable_nvidia_optional = false$|local enable_nvidia_optional = true|' "$startup_file"
        else
            echo "Warning: Expected Nvidia toggle line not found in '$startup_file'."
        fi
    fi
}

# NOTE: The upstream update_hypr_keybind_config() function (which rewrote an
# inline "| satty --filename -" call into a flatpak run command) has been
# removed. Your Satty invocation lives in Scripts/satty.sh, which already
# auto-detects native vs. Flatpak satty on its own - there's nothing left in
# keybind.lua for that function to patch.

# Set executable permissions for scripts
set_permissions() {
    SCRIPTS_PATH="$ACTUAL_USER_HOME/.config/hypr/Scripts"

    if [ -d "$SCRIPTS_PATH" ]; then
        echo "Setting execution permissions for scripts..."
        find "$SCRIPTS_PATH" -type f -exec chmod +x {} \;
    else
        echo "Warning: Hyprland scripts directory '$SCRIPTS_PATH' not found."
    fi
}

# Set default file manager to Thunar
set_default_file_manager() {
    echo ""
    echo "Setting Thunar as default file manager..."
    sudo -u "$ACTUAL_USER" mkdir -p "$ACTUAL_USER_HOME/.config"
    sudo -u "$ACTUAL_USER" xdg-mime default thunar.desktop inode/directory application/x-gnome-saved-search
    echo "Default file manager set to Thunar."
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

    local config_source="$REPO_DIR/backup/.config"

    if [[ ! -d "$config_source" ]]; then
        echo "No backup folder found at $REPO_DIR/backup/.config"
        echo "Skipping backup config restoration."
        return 0
    fi

    echo "Found backup configs at: $config_source"
    read -r -p "Do you want to restore config files from backup? (y/N): " backup_response

    if [[ "$backup_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Copying config files from backup to $CONFIG_DIR..."
        cp -rf "$config_source"/* "$CONFIG_DIR"/

        if [ $? -eq 0 ]; then
            echo "Config files copied successfully!"
            chown -R "$ACTUAL_USER:$ACTUAL_USER" "$CONFIG_DIR"

            if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
                echo "Detected Hyprland environment. Reloading Hyprland to apply new configs..."
                hyprctl reload 2>/dev/null || echo "Note: Could not reload Hyprland. You may need to restart it manually."
                sleep 2
            fi
        else
            echo "ERROR: Failed to copy backup config files."
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
setup_noctalia_greeter
enable_greetd_service

echo "Updating user directories..."
sudo -u "$ACTUAL_USER" xdg-user-dirs-update

if [ $? -ne 0 ]; then
    echo "Warning: Failed to update user directories."
fi

echo "Base package installation complete!"
echo "--------------------------------------------------------"
echo "Proceeding with post-install configuration..."
echo "--------------------------------------------------------"

echo "Updating system packages before installing Noctalia..."
dnf upgrade -y

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to update system packages. Aborting installation."
    exit 1
fi

set_default_file_manager
deploy_configs
copy_backup_configs
update_hypr_startup_config
create_thunar_bookmarks
set_permissions
install_flatpak_optional_packages
install_browser_choice
install_satty_flatpak
install_starship
post_install_hyprland_checks

sudo -u "$ACTUAL_USER" xdg-mime default thunar.desktop inode/directory
sudo -u "$ACTUAL_USER" xdg-mime default thunar.desktop application/x-gnome-saved-search

echo ""
echo "Installation complete! Time to reboot."
while true; do
    read -r -p "Would you like to reboot now? (y/n): " reboot_choice
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
