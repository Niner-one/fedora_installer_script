# Fedora Hyprland installer

`fedora_install.sh` installs packages, third-party repositories, a Flatpak remote,
and a Noctalia/greetd login session. It copies `config/` from the same cloned
repository as the script into the invoking user's `~/.config`, backing up
replaced entries as `<name>.bak.<timestamp>`, and offers to reboot. Review the
package list and the system changes in the script before running it.

Clone the repository with its `config/` directory intact. The installer checks
for `config/hypr/hyprland.lua` before changing the system, regardless of the
directory you run it from. Review the dotfiles, especially hardware-specific
settings and commands in `config/hypr/startup.lua`, before installation. GTK
bookmarks are created for the target user during installation.

The bundled login greeter configuration is `config/noctalia-greeter/greeter.toml`.
The installer places it at `/var/lib/noctalia-greeter/greeter.toml` with
`greeter:greeter` ownership and `0640` permissions. It backs up an existing file
as `greeter.toml.bak`, retaining older backups with numbered suffixes. The
`noctalia-greeter/` directory is excluded from the user's `~/.config`
installation. If the source directory is absent, the existing greeter
configuration is left in place; a present directory must contain `greeter.toml`.

On a Fedora system, run the cloned script from your regular account with
`sudo bash /path/to/fedora_installer_script/fedora_install.sh`. The script needs `dnf` with COPR
support, `rpm`, `sudo`, network access, and an interactive terminal. Optional
Flatpak applications and browsers can be declined; Satty and Starship failures
produce warnings. A failure to install core packages or deploy the dotfiles
stops the installer. Keep backups of any existing desktop configuration before
running.
