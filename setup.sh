#!/usr/bin/env bash
# =============================================================================
#  Arch Linux Post-Install Setup Script
# =============================================================================

set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET} $*" >&2; }

# Draw a progress bar: draw_progress current total label
draw_progress() {
    local current=$1 total=$2 label=$3
    local width=36
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=0; i<empty;  i++ )); do bar+="░"; done
    local pct=$(( current * 100 / total ))
    printf "\r  ${CYAN}[${bar}]${RESET} ${BOLD}%3d%%${RESET} (%d/%d) %s" "$pct" "$current" "$total" "$label"
    [[ "$current" -eq "$total" ]] && echo
}

# Check whether a package exists in the repos (not just installed)
pkg_exists_in_repos() {
    pacman -Si "$1" &>/dev/null
}

# Ask the user what to do on failure. Returns 0 to continue, 1 to abort.
ask_on_error() {
    local msg="$1"
    error "$msg"
    echo -e "${YELLOW}What would you like to do?${RESET}"
    select choice in "Skip and continue" "Abort script"; do
        case "$REPLY" in
            1) warn "Skipping."; return 0 ;;
            2) error "Aborting."; exit 1 ;;
        esac
    done
}

# Run a command as the normal user (not root)
run_as_user() {
    sudo -u "$USERNAME" "$@"
}

# Argument parsing
YES_MODE=false
for arg in "$@"; do
    [[ "$arg" == "-y" ]] && YES_MODE=true
done

# Require root
if [[ "$EUID" -ne 0 ]]; then
    error "Please run this script as root (e.g. sudo ./setup.sh)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME=""
USER_HOME=""

# Detect the non-root user who invoked sudo
if [[ -z "${SUDO_USER:-}" || "${SUDO_USER:-}" == "root" ]]; then
    error "Could not detect a non-root user. Please run with: sudo ./setup.sh"
    exit 1
fi
USERNAME="${SUDO_USER}"
USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
info "Detected user: ${USERNAME} (home: ${USER_HOME})"

# ── Configuration ─────────────────────────────────────────────────────────────

# Packages to install via pacman
PACKAGES_INSTALL=(
    git
    curl
    wget
    base
    base-devel
    kitty
    zsh
    fzf
    bat
    lsd
    locate
    vlc
    firefox
    micro
    btop
    flatpak
    fastfetch
    ripgrep
    jq
    # Add more packages here...
)

# Packages to remove via pacman
PACKAGES_REMOVE=(
    nano
    # GNOME Games
    gnome-2048
    aisleriot
    gnome-nibbles
    five-or-more
    four-in-a-row
    hitori
    lightsoff
    gnome-klotski
    gnome-mahjongg
    gnome-mines
    quadrapassel
    iagno
    gnome-robots
    gnome-chess
    gnome-sudoku
    swell-foop
    tali
    gnome-taquin
    gnome-tetravex
    # More GNOME bloat
    yelp
    gnome-maps
    gnome-characters
    gnome-font-viewer
    gnome-contacts
    evolution
    rhythmbox
    gnome-music
    gnome-logs
    totem
    malcontent
    gnome-connections
    evince
    gnome-tour
    epiphany
    celluloid
    showtime
    decibels
    # Unwanted default tools
    vim
    htop
    # Add more packages here...
)

# AUR packages to install via yay
PACKAGES_AUR=(
    zsh-theme-powerlevel10k-git
    zsh-autosuggestions
    zsh-syntax-highlighting
    scrub
    nautilus-open-any-terminal
    paccache-hook
    systemd-boot-pacman-hook
    mdcat
    # Add more AUR packages here...
)

# Flatpak apps to install
PACKAGES_FLATPAK=(
    com.github.tchx84.Flatseal
    com.mattjakeman.ExtensionManager
    org.libreoffice.LibreOffice
    org.localsend.localsend_app
    page.tesk.Refine
    # Add more Flatpak app IDs here...
)

# ── Mirror directories ────────────────────────────────────────────────────────
# The project folder structure mirrors the real filesystem.
# Files under each source subdir are copied to the matching real path.
#
# Expected project layout:
#   home/benja/   →  /home/benja/
#   root/         →  /root/
#   usr/          →  /usr/
MIRROR_DIRS=(
    "home/benja|${USER_HOME}"
    "root|/root"
    "usr|/usr"
)

# ── Multilib repository ───────────────────────────────────────────────────────
echo
info "═══ Enabling multilib repository ═══"
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    info "Enabling [multilib] in /etc/pacman.conf..."
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    success "[multilib] enabled."
else
    warn "[multilib] is already enabled — skipping."
fi

# ── BlackArch repository ──────────────────────────────────────────────────────
echo
info "═══ BlackArch repository ═══"
if grep -q '^\[blackarch\]' /etc/pacman.conf; then
    warn "BlackArch repository is already configured — skipping."
else
    if [[ "$YES_MODE" == true ]]; then
    _blackarch_ans="Y"
    else
        read -rp "$(echo -e "${YELLOW}Do you want to add the BlackArch repository? [Y/n]${RESET} ")" _blackarch_ans
        _blackarch_ans="${_blackarch_ans:-Y}"
    fi

    if [[ "$_blackarch_ans" =~ ^[Yy]$ ]]; then
        STRAP_URL="https://blackarch.org/strap.sh"
        STRAP_PATH="/tmp/strap.sh"

        info "Downloading BlackArch strap.sh..."
        if ! curl -fsSL "$STRAP_URL" -o "$STRAP_PATH"; then
            ask_on_error "Failed to download strap.sh from blackarch.org."
        else
            chmod +x "$STRAP_PATH"
            info "Running strap.sh (this will set up the BlackArch repo and keyring)..."
            if ! bash "$STRAP_PATH"; then
                ask_on_error "strap.sh encountered an error."
            else
                success "BlackArch repository added successfully."
                rm -f "$STRAP_PATH"
            fi
        fi
    else
        warn "Skipping BlackArch repository setup."
    fi
fi

# ── Sync & upgrade ────────────────────────────────────────────────────────────
echo
info "═══ Syncing and upgrading system ═══"
if ! pacman -Syyu --noconfirm; then
    ask_on_error "System upgrade failed."
else
    success "System fully upgraded."
fi

# ── Package removal ───────────────────────────────────────────────────────────
echo
info "═══ Removing packages ═══"

_to_remove=()
_total=${#PACKAGES_REMOVE[@]}
_count=0
info "Checking which packages are installed..."
for pkg in "${PACKAGES_REMOVE[@]}"; do
    _count=$(( _count + 1 ))
    draw_progress "$_count" "$_total" "$pkg"
    if pacman -Qi "$pkg" &>/dev/null; then
        _to_remove+=("$pkg")
    fi
done
echo  # newline after progress bar

if [[ ${#_to_remove[@]} -gt 0 ]]; then
    info "Packages to remove (${#_to_remove[@]}):"
    for pkg in "${_to_remove[@]}"; do
        echo "    - $pkg"
    done
    echo
    if ! pacman -Rdd --noconfirm "${_to_remove[@]}"; then
        ask_on_error "Failed to remove one or more packages."
    else
        success "All packages removed successfully."
    fi
else
    warn "No listed packages were installed — nothing to remove."
fi


echo
info "═══ Installing pacman packages ═══"

_to_install=()
_total=${#PACKAGES_INSTALL[@]}
_count=0
info "Checking which packages need to be installed..."
for pkg in "${PACKAGES_INSTALL[@]}"; do
    _count=$(( _count + 1 ))
    draw_progress "$_count" "$_total" "$pkg"
    if pacman -Qi "$pkg" &>/dev/null; then
        : # already installed, skip silently
    elif ! pkg_exists_in_repos "$pkg"; then
        : # not in repos, will warn after loop
        warn "  Package '$pkg' not found in repos — skipping."
    else
        _to_install+=("$pkg")
    fi
done
echo  # newline after progress bar

if [[ ${#_to_install[@]} -gt 0 ]]; then
    info "Packages to install (${#_to_install[@]}):"
    for pkg in "${_to_install[@]}"; do
        echo "    - $pkg"
    done
    echo
    if ! pacman -S --noconfirm "${_to_install[@]}"; then
        ask_on_error "Failed to install one or more packages."
    else
        success "All packages installed successfully."
    fi
else
    warn "No packages to install."
fi

# ── Install yay ───────────────────────────────────────────────────────────────
echo
info "═══ Installing yay (AUR helper) ═══"

if command -v yay &>/dev/null; then
    warn "yay is already installed — skipping."
else
    YAY_BUILD_DIR="/tmp/yay-build"
    rm -rf "$YAY_BUILD_DIR"

    # Allow passwordless sudo so makepkg doesn't prompt during build
    SUDOERS_TMP="/etc/sudoers.d/99-setup-nopwd"
    echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
    chmod 440 "$SUDOERS_TMP"

    info "Cloning yay from AUR..."
    if ! run_as_user git clone https://aur.archlinux.org/yay.git "$YAY_BUILD_DIR"; then
        rm -f "$SUDOERS_TMP"
        ask_on_error "Failed to clone yay repository."
    else
        info "Building and installing yay (this may take a moment)..."
        if ! run_as_user bash -c "cd '${YAY_BUILD_DIR}' && makepkg -si --noconfirm"; then
            rm -f "$SUDOERS_TMP"
            ask_on_error "Failed to build/install yay."
        else
            success "yay installed successfully."
            rm -rf "$YAY_BUILD_DIR"
        fi
    fi

    rm -f "$SUDOERS_TMP"
fi

# ── AUR package installation ──────────────────────────────────────────────────
echo
info "═══ Installing AUR packages ═══"

if ! command -v yay &>/dev/null; then
    ask_on_error "yay is not available — cannot install AUR packages."
else
    # Allow the user to sudo without password temporarily so yay doesn't prompt
    SUDOERS_TMP="/etc/sudoers.d/99-setup-nopwd"
    echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
    chmod 440 "$SUDOERS_TMP"

    _total=${#PACKAGES_AUR[@]}
    _count=0
    for pkg in "${PACKAGES_AUR[@]}"; do
        _count=$(( _count + 1 ))
        draw_progress "$_count" "$_total" "$pkg"
        if pacman -Qi "$pkg" &>/dev/null; then
            warn "'$pkg' is already installed — skipping."
        else
            if ! run_as_user yay -S --noconfirm "$pkg" &>/dev/null; then
                ask_on_error "Failed to install AUR package '$pkg'."
            else
                success "Installed (AUR): $pkg"
            fi
        fi
    done

    # Remove the temporary NOPASSWD rule
    rm -f "$SUDOERS_TMP"
    success "Sudo password requirement restored."
fi

# ── Hide unwanted desktop entries ─────────────────────────────────────────────
echo
info "═══ Hiding unwanted desktop entries ═══"

HIDDEN_ENTRIES=(
    # Avahi (keep installed, hide from launcher)
    /usr/share/applications/avahi-discover.desktop
    /usr/share/applications/bssh.desktop
    /usr/share/applications/bvnc.desktop
    # V4L2 (keep installed, hide from launcher)
    /usr/share/applications/qv4l2.desktop
    /usr/share/applications/qvidcap.desktop
    # Terminal tools (keep installed, hide from launcher)
    /usr/share/applications/btop.desktop
    /usr/share/applications/micro.desktop
    /usr/share/applications/cmake-gui.desktop
)

for entry in "${HIDDEN_ENTRIES[@]}"; do
    if [[ -f "$entry" ]]; then
        # Append NoDisplay=true to hide from app launcher without deleting
        if ! grep -q '^NoDisplay=true' "$entry"; then
            echo 'NoDisplay=true' >> "$entry"
            success "Hidden: $(basename "$entry")"
        else
            warn "Already hidden: $(basename "$entry")"
        fi
    else
        warn "Desktop entry not found: $entry — skipping."
    fi
done

# ── Flatpak packages ──────────────────────────────────────────────────────────
echo
info "═══ Installing Flatpak packages ═══"

if [[ ${#PACKAGES_FLATPAK[@]} -eq 0 ]]; then
    warn "No Flatpak packages defined — skipping."
elif ! command -v flatpak &>/dev/null; then
    warn "Flatpak is not installed — skipping."
else
    if [[ "$YES_MODE" == true ]]; then
        _install_flatpaks="Y"
    else
        read -rp "$(echo -e "${YELLOW}Do you want to install Flatpak packages? [Y/n]${RESET} ")" _install_flatpaks
        _install_flatpaks="${_install_flatpaks:-Y}"
    fi

    if [[ "$_install_flatpaks" =~ ^[Yy]$ ]]; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

        _total=${#PACKAGES_FLATPAK[@]}
        _count=0
        _failed=0
        for app in "${PACKAGES_FLATPAK[@]}"; do
            _count=$(( _count + 1 ))
            draw_progress "$_count" "$_total" "$app"
            if flatpak list --app --columns=application | grep -q "^${app}$"; then
                warn "'$app' is already installed — skipping."
            elif ! flatpak install --noninteractive flathub "$app" &>/dev/null; then
                ask_on_error "Failed to install Flatpak: '$app'."
                _failed=$(( _failed + 1 ))
            fi
        done
        echo

        if [[ "$_failed" -eq 0 ]]; then
            success "All Flatpak packages installed successfully."
        else
            warn "$(( _total - _failed ))/${_total} Flatpak packages installed (${_failed} failed)."
        fi
    else
        warn "Skipping Flatpak package installation."
    fi
fi

# ── zsh setup ─────────────────────────────────────────────────────────────────
echo
info "═══ Configuring zsh ═══"

info "Setting zsh as default shell for '${USERNAME}'..."
if ! usermod --shell /usr/bin/zsh "$USERNAME"; then
    ask_on_error "Failed to set zsh shell for '${USERNAME}'."
else
    success "Default shell set to zsh for '${USERNAME}'."
fi

info "Setting zsh as default shell for root..."
if ! usermod --shell /usr/bin/zsh root; then
    ask_on_error "Failed to set zsh shell for root."
else
    success "Default shell set to zsh for root."
fi

info "Setting up zsh-sudo plugin..."
ZSH_SUDO_DIR="/usr/share/zsh-sudo"
ZSH_SUDO_SRC="${SCRIPT_DIR}/usr/share/zsh-sudo/sudo.plugin.zsh"

mkdir -p "$ZSH_SUDO_DIR"

if [[ -f "$ZSH_SUDO_SRC" ]]; then
    if ! cp "$ZSH_SUDO_SRC" "${ZSH_SUDO_DIR}/sudo.plugin.zsh"; then
        ask_on_error "Failed to copy sudo.plugin.zsh to ${ZSH_SUDO_DIR}."
    else
        success "sudo.plugin.zsh installed to ${ZSH_SUDO_DIR}."
    fi
else
    warn "sudo.plugin.zsh not found at '${ZSH_SUDO_SRC}' — will be handled by config mirror."
fi

info "Symlinking ${USER_HOME}/.zshrc → /root/.zshrc..."
if [[ -f "/root/.zshrc" && ! -L "/root/.zshrc" ]]; then
    backup="/root/.zshrc.bak_$(date +%Y%m%d_%H%M%S)"
    warn "Backing up existing /root/.zshrc → $backup"
    mv /root/.zshrc "$backup"
fi

if ! ln -sf "${USER_HOME}/.zshrc" /root/.zshrc; then
    ask_on_error "Failed to symlink .zshrc for root."
else
    success "Symlinked /root/.zshrc → ${USER_HOME}/.zshrc"
fi

# ── Config files (directory mirror) ──────────────────────────────────────────
echo
info "═══ Copying config files ═══"

for entry in "${MIRROR_DIRS[@]}"; do
    src_subdir="${entry%%|*}"
    dst_prefix="${entry##*|}"
    src_path="${SCRIPT_DIR}/${src_subdir}"

    if [[ ! -d "$src_path" ]]; then
        warn "Mirror directory '${src_subdir}/' not found in project — skipping."
        continue
    fi

    info "Mirroring '${src_subdir}/' → '${dst_prefix}/'"

    while IFS= read -r -d '' file; do
        rel="${file#"${src_path}/"}"
        dst="${dst_prefix}/${rel}"
        dst_dir="$(dirname "$dst")"

        mkdir -p "$dst_dir"

        if [[ -e "$dst" && ! -L "$dst" ]]; then
            backup="${dst}.bak_$(date +%Y%m%d_%H%M%S)"
            warn "Backing up '${dst}' → '${backup}'"
            cp -a "$dst" "$backup"
        fi

        if ! cp -a "$file" "$dst"; then
            ask_on_error "Failed to copy '${file}' → '${dst}'."
        else
            success "Copied: ${rel} → ${dst}"
        fi
    done < <(find "$src_path" -type f -print0)
done

info "Fixing ownership of ${USER_HOME}..."
chown -R "${USERNAME}:${USERNAME}" "$USER_HOME"
success "Ownership set for ${USER_HOME}."

# ── Open in kitty option in Files ────────────────────────────────────────────
echo
info "═══ Setting open in kitty option in Files ═══"
run_as_user gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty
nautilus -q

# ── Default media player (VLC) ───────────────────────────────────────────────
echo
info "═══ Setting VLC as default media player ═══"

if ! command -v vlc &>/dev/null; then
    warn "VLC does not appear to be installed — skipping mime defaults."
else
    VIDEO_MIMES=(
        video/mp4
        video/x-matroska
        video/x-mkv
        video/webm
        video/x-msvideo
        video/mpeg
        video/quicktime
        video/x-flv
        video/3gpp
        video/x-ms-wmv
        video/ogg
        video/x-ogm+ogg
    )

    AUDIO_MIMES=(
        audio/mpeg
        audio/x-flac
        audio/flac
        audio/ogg
        audio/x-wav
        audio/mp4
        audio/x-m4a
        audio/aac
        audio/x-ms-wma
    )

    ALL_MIMES=( "${VIDEO_MIMES[@]}" "${AUDIO_MIMES[@]}" )
    _total=${#ALL_MIMES[@]}
    _count=0
    _failed=0

    for mime in "${ALL_MIMES[@]}"; do
        _count=$(( _count + 1 ))
        draw_progress "$_count" "$_total" "$mime"
        if ! run_as_user xdg-mime default vlc.desktop "$mime"; then
            warn "Failed to set default for: $mime"
            _failed=$(( _failed + 1 ))
        fi
    done
    echo  # newline after progress bar

    if [[ "$_failed" -eq 0 ]]; then
        success "VLC set as default for all ${_total} media MIME types."
    else
        warn "VLC set as default for $(( _total - _failed ))/${_total} MIME types (${_failed} failed)."
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo
success "═══ Setup complete! ═══"
info "Please run on kitty pacman -Rns gnome-console"
info "Reboot for shell changes and Flatpak installation to take effect."
