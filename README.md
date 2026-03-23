# Arch Linux Post-Install Setup

A single script that turns a fresh Arch Linux + GNOME install into a fully configured personal system — removing bloat, installing preferred packages, setting up zsh with Powerlevel10k, and deploying config files, all in one run.

---

## Requirements

- A fresh Arch Linux install with GNOME
- An internet connection
- Run as your regular user via `sudo` (not directly as root)

---

## Usage

Clone the repo and run the script:

```bash
git clone https://github.com/benjaamonti/Arch.git
cd Arch
chmod +x setup.sh
sudo ./setup.sh
```

Pass `-y` to skip all optional prompts and accept defaults:

```bash
sudo ./setup.sh -y
```

The script detects the invoking user automatically via `$SUDO_USER`, so no hardcoded usernames are needed.

---

## What it does

The script runs in this order:

### 1. Enable multilib
Uncomments the `[multilib]` section in `/etc/pacman.conf` if not already active, giving access to 32-bit libraries needed by tools like Steam and Wine.

### 2. BlackArch repository (optional)
Prompts whether to add the [BlackArch](https://blackarch.org) repository — a large collection of security and penetration testing tools built on top of Arch. Defaults to **yes**. If accepted, downloads and runs the official `strap.sh` installer to set up the repo and keyring.

### 3. System upgrade
Runs `pacman -Syyu` to force-refresh all package databases and upgrade the full system before making any changes.

### 4. Remove packages
Removes GNOME games and other unwanted applications that ship with a default GNOME install. Packages that are not installed are safely skipped.

| Category | Packages |
|---|---|
| GNOME Games | `gnome-2048` `aisleriot` `gnome-nibbles` `five-or-more` `four-in-a-row` `hitori` `lightsoff` `gnome-klotski` `gnome-mahjongg` `gnome-mines` `quadrapassel` `iagno` `gnome-robots` `gnome-chess` `gnome-sudoku` `swell-foop` `tali` `gnome-taquin` `gnome-tetravex` |
| GNOME Bloat | `yelp` `gnome-maps` `gnome-characters` `gnome-font-viewer` `gnome-contacts` `gnome-music` `gnome-logs` `malcontent` `gnome-connections` `gnome-tour` `epiphany` |
| Unused apps | `evolution` `rhythmbox` `totem` `evince` `celluloid` `showtime` `decibels` |
| Replaced tools | `nano` `vim` `htop` |

### 5. Install pacman packages

| Package | Description |
|---|---|
| `git` | Version control |
| `curl` / `wget` | File downloading |
| `base` / `base-devel` | Core system and build tools |
| `kitty` | GPU-accelerated terminal |
| `zsh` | Z shell |
| `fzf` | Fuzzy finder |
| `bat` | `cat` with syntax highlighting |
| `lsd` | Modern `ls` replacement |
| `locate` | Fast file location |
| `vlc` | Media player |
| `firefox` | Web browser |
| `micro` | Modern terminal text editor |
| `btop` | Resource monitor |
| `flatpak` | Universal package format support |
| `fastfetch` | System info tool |
| `ripgrep` | Fast recursive search |
| `jq` | JSON processor |

If running on a laptop, also installs `power-profiles-daemon` for power management.

### 6. Install yay (AUR helper)
Clones, builds, and installs [yay](https://github.com/Jguer/yay) from the AUR as the regular user (required since `makepkg` cannot run as root).

### 7. Install AUR packages

| Package | Description |
|---|---|
| `zsh-theme-powerlevel10k-git` | Fast, highly customizable zsh prompt |
| `zsh-autosuggestions` | Fish-like command suggestions |
| `zsh-syntax-highlighting` | Real-time syntax highlighting in the shell |
| `scrub` | Secure file overwrite / disk scrubbing tool |
| `nautilus-open-any-terminal` | "Open in terminal" option in Files |
| `paccache-hook` | Automatically cleans the pacman package cache |
| `systemd-boot-pacman-hook` | Keeps systemd-boot updated on kernel upgrades |
| `mdcat` | Terminal Markdown renderer |

### 8. Hide unwanted desktop entries
Some packages are kept installed but their launchers are hidden from the app grid by appending `NoDisplay=true` to their `.desktop` files. This applies to tools like `btop`, `micro`, and Avahi/V4L2 utilities that are better accessed from the terminal.

### 9. Install Flatpak packages (optional)
Adds the Flathub remote and installs the following apps:

| App ID | Description |
|---|---|
| `com.github.tchx84.Flatseal` | Flatpak permissions manager |
| `com.mattjakeman.ExtensionManager` | GNOME extensions manager |
| `org.libreoffice.LibreOffice` | Office suite |
| `org.localsend.localsend_app` | Local file sharing |
| `page.tesk.Refine` | GNOME tweaks app |

### 10. Configure zsh
- Sets zsh as the default shell for both the regular user and root
- Installs the `sudo` plugin to `/usr/share/zsh-sudo/` (double-tap `Esc` to prepend `sudo` to any command)
- Symlinks `/root/.zshrc` → `~/.zshrc` so root shares the same shell config

### 11. Deploy config files
The repo mirrors the real filesystem structure. Files are copied to their exact system paths automatically:

```
arch-setup/
├── home/
│   └── benja/                   →  /home/<user>/
│       ├── .p10k.zsh
│       ├── .zshrc
│       └── .config/
│           ├── fastfetch/
│           │   ├── presets/
│           │   │   ├── all.jsonc
│           │   │   ├── archey.jsonc
│           │   │   ├── ci.jsonc
│           │   │   ├── mini.jsonc
│           │   │   ├── neofetch.jsonc
│           │   │   ├── paleofetch.jsonc
│           │   │   └── screenfetch.jsonc
│           │   ├── config.jsonc
│           │   └── mini.jsonc
│           ├── kitty/
│           │   └── kitty.conf
│           └── neofetch/
├── root/                        →  /root/
│   └── .p10k.zsh
└── usr/                         →  /usr/
    └── share/
        └── zsh-sudo/
            └── sudo.plugin.zsh
```

Ownership of all files under the user's home directory is fixed at the end.

### 12. Set kitty as the default terminal in Files
Configures `nautilus-open-any-terminal` to launch kitty when using the "Open in Terminal" option in the Files app.

### 13. Set VLC as default media player
Associates VLC with all common video and audio MIME types via `xdg-mime`.

---

## Error handling

On any failure the script pauses and asks:

```
1) Skip and continue
2) Abort script
```
