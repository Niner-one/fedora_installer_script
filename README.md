# Fedora Hyprland installer

`fedora_install.sh` installs packages, third-party repositories, a Flatpak remote,
and a Noctalia/greetd login session. It copies the invoking user's
`~/config_files/` directory into `~/.config`, backing up replaced entries as
`<name>.bak.<timestamp>`, and offers to reboot. Review the package list and the
system changes in the script before running it.

Before installation, place the dotfiles in `~/config_files/`, with
`~/config_files/hypr/hyprland.lua` present. The installer checks for that file
before changing the system. Review the dotfiles, especially hardware-specific
settings and commands in `~/config_files/hypr/startup.lua`, before installation.
GTK bookmarks are created for the target user during installation.

On a Fedora system, with the required dotfiles present, run it from your regular
account with `sudo bash fedora_install.sh`. The script needs `dnf` with COPR
support, `rpm`, `sudo`, network access, and an interactive terminal. Optional
Flatpak applications and browsers can be declined; Satty and Starship failures
produce warnings. A failure to install core packages or deploy the dotfiles
stops the installer. Keep backups of any existing desktop configuration before
running.
