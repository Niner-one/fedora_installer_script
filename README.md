# Fedora Hyprland installer

`fedora_install.sh` installs packages, third-party repositories, a Flatpak remote,
and Noctalia/greetd packages, then enables the greetd service. It copies `config/`
from the same cloned repository as the script into the invoking user's `~/.config`, backing up
replaced entries as `<name>.bak.<timestamp>`, and offers to reboot. Review the
package list and the system changes in the script before running it.

Clone the repository with its `config/` directory intact. The installer checks
for `config/hypr/hyprland.lua` before changing the system, regardless of the
directory you run it from. Review the dotfiles, especially hardware-specific
settings and commands in `config/hypr/startup.lua`, before installation. GTK
bookmarks are created for the target user during installation.

Greeter accounts, state directories, greetd configuration, and PAM integration
are left to the installed packages. The installer does not write greeter or
greetd configuration or run a separate greeter setup script.
The bundled `config/noctalia-greeter/greeter.toml` is available for manual use.
The `config/noctalia-greeter/` directory is excluded from the user's `~/.config`
installation.

Before deploying dotfiles, the installer makes the `~/.config` directory owned
by the invoking user and grants its owner read, write, and search permissions.
This repairs a directory left owned by root or without owner write permission.
Existing group/other permissions and ownership of files inside it are preserved.

On a Fedora system, run the cloned script from your regular account with
`sudo bash /path/to/fedora_installer_script/fedora_install.sh`. The script needs `dnf` with COPR
support, `rpm`, `sudo`, network access, and an interactive terminal. Optional
Flatpak applications and browsers can be declined; Satty and Starship failures
produce warnings. A failure to install core packages or deploy the dotfiles
stops the installer. Keep backups of any existing desktop configuration before
running.

## Validation

Run `bash tests/installer_smoke.sh` as your normal user before installation.
The tests use temporary files and mocked system commands to check configuration
backups, config directory permissions, greeter config exclusion, and failure
handling. They require Bash and standard Linux command-line utilities; they do not install packages or
start services. Package availability and the live login session still require
verification on Fedora. The installer refuses to enable greetd or change the
boot target if the Hyprland session file is missing.
