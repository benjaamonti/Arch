#!/usr/bin/env bash
# =============================================================================
#  Hyprland Installation Script — Arch Linux
#  Usage: sudo bash install-hyprland.sh [options]
#
#  Options:
#    -nv    Install NVIDIA drivers automatically (default: ask, default answer: no)
# =============================================================================

set -euo pipefail

# ── Flag parsing ─────────────────────────────────────────────────────────────
NVIDIA_FLAG=false
for arg in "$@"; do
    case "$arg" in
        -nv) NVIDIA_FLAG=true ;;
        *)   echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}${BOLD}[*]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[!]${RESET} $*"; }
die()     { echo -e "${RED}${BOLD}[✗]${RESET} $*" >&2; exit 1; }

# ── Root / user detection ─────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
[[ -n "$REAL_USER" ]] || die "Could not detect the real user. Set SUDO_USER."
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

info "Running as root, acting on behalf of: ${BOLD}$REAL_USER${RESET}"

# ── Run a command as the real (non-root) user ─────────────────────────────────
as_user() { sudo -u "$REAL_USER" env HOME="$REAL_HOME" "$@"; }

# ── Script location (for bundled assets) ─────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_SRC="$SCRIPT_DIR/assets/background/bootloader.png"

# =============================================================================
#  STEP 1 — System update
# =============================================================================
info "Updating system..."
pacman -Syu --noconfirm
success "System up to date."

# =============================================================================
#  STEP 2 — Enable multilib repository
# =============================================================================
info "Enabling [multilib] repository..."
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    pacman -Sy --noconfirm
    success "[multilib] enabled."
else
    success "[multilib] already enabled — skipping."
fi

# =============================================================================
#  STEP 3 — Install yay (AUR helper) if not present
# =============================================================================
if ! command -v yay &>/dev/null; then
    info "yay not found — installing..."

    BUILDDIR="$(mktemp -d)"
    trap 'rm -rf "$BUILDDIR"' EXIT

    pacman -S --noconfirm --needed git base-devel

    # mktemp creates a root-owned 0700 dir — the user can't clone into it without this
    chown "$REAL_USER:$REAL_USER" "$BUILDDIR"

    as_user git clone https://aur.archlinux.org/yay.git "$BUILDDIR/yay"
    as_user bash -c "cd '$BUILDDIR/yay' && makepkg -si --noconfirm"

    success "yay installed."
else
    success "yay already installed — skipping."
fi

# =============================================================================
#  STEP 4 — Remove unwanted packages
# =============================================================================
info "Removing unwanted packages (vim, htop) if present..."
for pkg in vim htop; do
    if pacman -Q "$pkg" &>/dev/null; then
        pacman -Rns --noconfirm "$pkg"
        success "  Removed: $pkg"
    else
        info "  Not installed, skipping: $pkg"
    fi
done

# =============================================================================
#  STEP 5 — Base packages
# =============================================================================
BASE_PACMAN=(
    # Core
    git curl wget base base-devel

    # Shell & terminal
    kitty zsh

    # CLI tools
    fzf bat lsd ripgrep jq btop fastfetch

    # System
    plocate man-db flatpak

    # Fonts
    ttf-cascadia-code-nerd

    # Apps
    firefox vlc vlc-plugins-all micro waybar nautilus wlogout

    # Hyprland utilities
    hyprpaper hyprlock hypridle grim slurp wl-clipboard dunst libnotify
    brightnessctl playerctl pavucontrol
    xdg-desktop-portal-hyprland polkit-gnome

    # Network & bluetooth
    networkmanager iwd network-manager-applet blueman

    # App launcher
    rofi
)

BASE_AUR=(
    # Shell
    zsh-theme-powerlevel10k-git
    zsh-autosuggestions
    zsh-syntax-highlighting

    # Tools
    scrub
    mdcat

    # Desktop integrations
    nautilus-open-any-terminal
    paccache-hook
)

info "Installing base packages..."
pacman -S --noconfirm --needed "${BASE_PACMAN[@]}"
success "Base pacman packages installed."

info "Installing base AUR packages..."
if ! as_user yay -S --noconfirm --needed "${BASE_AUR[@]}"; then
    warn "Batch AUR install failed — retrying packages individually..."
    for pkg in "${BASE_AUR[@]}"; do
        if as_user yay -S --noconfirm --needed "$pkg"; then
            success "  $pkg"
        else
            warn "  FAILED: $pkg"
            printf '%s\n' "$pkg" >> "$REAL_HOME/hyprland-failed.txt"
        fi
    done
else
    success "Base AUR packages installed."
fi


# =============================================================================
#  STEP 6 — Hyprland build dependencies (pacman)
# =============================================================================
PACMAN_DEPS=(
    # Build tools
    ninja gcc cmake meson cpio

    # XCB / X11 libraries
    libxcb xcb-proto xcb-util xcb-util-keysyms
    xcb-util-wm xcb-util-errors
    libxfixes libx11 libxcomposite libxrender libxcursor
    xorg-xwayland

    # Wayland / graphics
    pixman wayland-protocols cairo pango
    libxkbcommon libinput

    # Misc
    re2 muparser
)

info "Installing pacman dependencies..."
pacman -S --noconfirm --needed "${PACMAN_DEPS[@]}"
success "Pacman dependencies installed."

# =============================================================================
#  STEP 7 — Hyprland (stable, from official repos)
# =============================================================================
info "Installing hyprland..."
pacman -S --noconfirm --needed hyprland
success "hyprland installed."

# =============================================================================
#  STEP 8 — AUR packages (yay)
# =============================================================================
# Stable Hypr-ecosystem packages (non-git, from AUR or official)
HYPR_STABLE=(
    aquamarine
    hyprlang
    hyprcursor
    hyprutils
    hyprgraphics
)

# Bleeding-edge -git builds + other AUR packages
AUR_PKGS=(
    # Display / output
    libliftoff
    libdisplay-info

    # Build / header deps
    tomlplusplus
    glaze

    # Hypr ecosystem — git
    hyprlang-git
    hyprcursor-git
    hyprwayland-scanner-git
    hyprutils-git
    hyprgraphics-git
    aquamarine-git
    hyprland-qtutils-git
)

install_aur_batch() {
    local label="$1"; shift
    local pkgs=("$@")

    info "Installing ${label}..."

    # Attempt batch install first — better dependency resolution, no sudo timeout risk
    if as_user yay -S --noconfirm --needed "${pkgs[@]}"; then
        success "${label} installed."
        return 0
    fi

    # Batch failed — retry individually to isolate which packages are broken
    warn "Batch install failed for ${label} — retrying individually..."
    local failed=()
    for pkg in "${pkgs[@]}"; do
        if as_user yay -S --noconfirm --needed "$pkg"; then
            success "  $pkg"
        else
            warn "  FAILED: $pkg"
            failed+=("$pkg")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        warn "The following ${label} packages failed to install:"
        for p in "${failed[@]}"; do echo -e "  ${RED}• $p${RESET}"; done
        printf '%s\n' "${failed[@]}" >> "$REAL_HOME/hyprland-failed.txt"
    fi
}

install_aur_batch "stable Hypr ecosystem packages" "${HYPR_STABLE[@]}"
install_aur_batch "AUR / -git packages" "${AUR_PKGS[@]}"

# =============================================================================
#  STEP 9 — SDDM (display manager) + astronaut theme
# =============================================================================
info "Installing SDDM..."
pacman -S --noconfirm --needed sddm
systemctl enable sddm
success "SDDM installed and enabled."

info "Installing sddm-astronaut-theme..."
as_user yay -S --noconfirm --needed sddm-astronaut-theme

# Copy the theme to a custom folder so pacman updates don't overwrite our edits
SDDM_SRC="/usr/share/sddm/themes/sddm-astronaut-theme"
SDDM_CUSTOM="/usr/share/sddm/themes/sddm-astronaut-custom"
if [[ -d "$SDDM_SRC" ]]; then
    cp -r "$SDDM_SRC" "$SDDM_CUSTOM"
    success "Theme copied to sddm-astronaut-custom."
else
    die "sddm-astronaut-theme not found at $SDDM_SRC after install."
fi

# Write SDDM config pointing at our custom copy
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=sddm-astronaut-custom
EOF

# Select the pixel_sakura variant in the custom copy — pacman will never touch this
# To change variant later, edit ConfigFile= in:
# /usr/share/sddm/themes/sddm-astronaut-custom/metadata.desktop
ASTRONAUT_METADATA="${SDDM_CUSTOM}/metadata.desktop"
if [[ -f "$ASTRONAUT_METADATA" ]]; then
    sed -i 's|^ConfigFile=.*|ConfigFile=Themes/pixel_sakura.conf|' "$ASTRONAUT_METADATA"
    success "sddm-astronaut-custom set to pixel_sakura variant."
else
    warn "Could not find custom theme metadata — set variant manually at $ASTRONAUT_METADATA"
fi

# =============================================================================
#  STEP 10 — NVIDIA drivers (optional)
# =============================================================================
INSTALL_NVIDIA=false

if [[ "$NVIDIA_FLAG" == true ]]; then
    INSTALL_NVIDIA=true
else
    echo
    echo -e "${YELLOW}${BOLD}[?]${RESET} Install NVIDIA drivers and configure for Hyprland?"
    echo -e "    (packages: nvidia-dkms, nvidia-utils, nvidia-settings, linux-headers, libva-nvidia-driver, egl-wayland)"
    read -r -p "    [y/N] " _nv_answer
    [[ "${_nv_answer,,}" == "y" ]] && INSTALL_NVIDIA=true
fi

if [[ "$INSTALL_NVIDIA" == true ]]; then
    info "Installing NVIDIA packages..."
    pacman -S --noconfirm --needed \
        nvidia-dkms \
        nvidia-utils \
        nvidia-settings \
        linux-headers \
        libva-nvidia-driver \
        egl-wayland

    # ── mkinitcpio: add NVIDIA modules ────────────────────────────────────────
    info "Configuring mkinitcpio for NVIDIA..."
    MKINIT_CONF="/etc/mkinitcpio.conf"

    # Add modules if not already present
    if ! grep -q "nvidia_drm" "$MKINIT_CONF"; then
        sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$MKINIT_CONF"
        # Clean up any accidental leading space
        sed -i 's/^MODULES=( /MODULES=(/' "$MKINIT_CONF"
    else
        warn "NVIDIA modules already present in mkinitcpio.conf — skipping."
    fi

    # ── Kernel parameter: nvidia_drm.modeset=1 ────────────────────────────────
    info "Adding nvidia_drm.modeset=1 kernel parameter..."

    if [[ -d /boot/loader/entries ]]; then
        # systemd-boot: write to /etc/kernel/cmdline so params survive kernel updates
        # (patching entries directly gets wiped on every kernel reinstall)
        CMDLINE_FILE="/etc/kernel/cmdline"
        if [[ -f "$CMDLINE_FILE" ]]; then
            if ! grep -q "nvidia_drm.modeset" "$CMDLINE_FILE"; then
                sed -i 's/$/ nvidia_drm.modeset=1 nvidia_drm.fbdev=1/' "$CMDLINE_FILE"
                info "  Updated $CMDLINE_FILE"
            else
                warn "nvidia_drm.modeset already in $CMDLINE_FILE — skipping."
            fi
        else
            # File doesn't exist yet — create it from current options line
            local current_opts=""
            for entry in /boot/loader/entries/*.conf; do
                current_opts=$(grep '^options ' "$entry" | sed 's/^options //' | head -1)
                [[ -n "$current_opts" ]] && break
            done
            echo "${current_opts} nvidia_drm.modeset=1 nvidia_drm.fbdev=1" > "$CMDLINE_FILE"
            info "  Created $CMDLINE_FILE"
        fi
        # Also patch current entries so this boot works without a reinstall
        for entry in /boot/loader/entries/*.conf; do
            if ! grep -q "nvidia_drm.modeset" "$entry"; then
                sed -i '/^options / s/$/ nvidia_drm.modeset=1 nvidia_drm.fbdev=1/' "$entry"
            fi
        done
    elif [[ -f /etc/default/grub ]]; then
        # GRUB
        if ! grep -q "nvidia_drm.modeset" /etc/default/grub; then
            sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' /etc/default/grub
            grub-mkconfig -o /boot/grub/grub.cfg
        else
            warn "nvidia_drm.modeset already in GRUB config — skipping."
        fi
    else
        warn "Could not detect bootloader. Add 'nvidia_drm.modeset=1 nvidia_drm.fbdev=1' to your kernel parameters manually."
    fi

    # ── Preserve video memory across suspend ─────────────────────────────────
    info "Enabling NVreg_PreserveVideoMemoryAllocations (suspend fix)..."
    cat > /etc/modprobe.d/nvidia-power.conf << 'EOF'
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
    systemctl enable nvidia-suspend nvidia-hibernate nvidia-resume

    # ── Rebuild initramfs ─────────────────────────────────────────────────────
    info "Rebuilding initramfs..."
    mkinitcpio -P

    # ── Hyprland env vars ─────────────────────────────────────────────────────
    info "Writing NVIDIA env vars for Hyprland..."
    HYPR_ENV_FILE="$REAL_HOME/.config/hypr/nvidia-env.conf"
    as_user mkdir -p "$(dirname "$HYPR_ENV_FILE")"
    cat > "$HYPR_ENV_FILE" << 'EOF'
# NVIDIA environment variables for Hyprland
# Source this file from hyprland.conf with: source = ~/.config/hypr/nvidia-env.conf

env = LIBVA_DRIVER_NAME,nvidia
env = XDG_SESSION_TYPE,wayland
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
env = ELECTRON_OZONE_PLATFORM_HINT,auto
EOF
    chown "$REAL_USER:$REAL_USER" "$HYPR_ENV_FILE"

    echo
    warn "Add this line to your ~/.config/hypr/hyprland.conf:"
    echo -e "  ${BOLD}source = ~/.config/hypr/nvidia-env.conf${RESET}"

    success "NVIDIA setup complete."
else
    info "Skipping NVIDIA setup."
fi


# =============================================================================
#  STEP 11 — GRUB theme (Sleek BigSur + Vimix white icons + custom wallpaper)
# =============================================================================
info "Setting up GRUB theme..."

# Ensure required packages
pacman -S --noconfirm --needed grub os-prober

# Enable os-prober so Windows is detected
if ! grep -q "^GRUB_DISABLE_OS_PROBER=false" /etc/default/grub; then
    if grep -q "GRUB_DISABLE_OS_PROBER" /etc/default/grub; then
        sed -i 's/^#*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    else
        echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
    fi
fi

THEME_BUILDDIR="$(mktemp -d)"
THEME_NAME="sleek-vimix"
THEME_DEST="/boot/grub/themes/$THEME_NAME"

# ── Clone Sleek themes ────────────────────────────────────────────────────────
info "Cloning sleek--themes..."
git clone --depth=1 https://github.com/sandesh236/sleek--themes.git \
    "$THEME_BUILDDIR/sleek"

# BigSur variant folder
SLEEK_SRC="$THEME_BUILDDIR/sleek/BigSur-white"

[[ -d "$SLEEK_SRC" ]] || {
    # Fallback: find the BigSur folder dynamically
    SLEEK_SRC=$(find "$THEME_BUILDDIR/sleek" -maxdepth 2 -iname "*bigsur*" -type d | head -1)
    [[ -d "$SLEEK_SRC" ]] || die "Could not locate BigSur theme folder in sleek--themes."
}

# ── Clone grub2-themes for Vimix white icons ──────────────────────────────────
info "Cloning grub2-themes (vimix white icons)..."
git clone --depth=1 https://github.com/vinceliuice/grub2-themes.git \
    "$THEME_BUILDDIR/grub2"

VIMIX_ICONS=$(find "$THEME_BUILDDIR/grub2" -type d -name "white" | head -1)
[[ -d "$VIMIX_ICONS" ]] || die "Could not locate vimix white icons."

# ── Assemble patched theme ────────────────────────────────────────────────────
info "Assembling patched theme..."
mkdir -p "$THEME_DEST"
cp -r "$SLEEK_SRC"/. "$THEME_DEST/"

# Overwrite sleek icons with vimix white icons
mkdir -p "$THEME_DEST/icons"
cp "$VIMIX_ICONS"/*.png "$THEME_DEST/icons/" 2>/dev/null || \
    cp "$VIMIX_ICONS"/* "$THEME_DEST/icons/"

# ── Apply custom wallpaper ────────────────────────────────────────────────────
if [[ -f "$WALLPAPER_SRC" ]]; then
    info "Applying custom wallpaper..."
    cp "$WALLPAPER_SRC" "$THEME_DEST/background.png"
    # Patch theme.txt to point to our background
    if [[ -f "$THEME_DEST/theme.txt" ]]; then
        sed -i 's|desktop-image:.*|desktop-image: "background.png"|' "$THEME_DEST/theme.txt"
    fi
    success "Custom wallpaper applied."
else
    warn "Wallpaper not found at assets/background/bootloader.png — using BigSur default."
fi

# ── Point GRUB at the theme ───────────────────────────────────────────────────
if grep -q "^GRUB_THEME=" /etc/default/grub; then
    sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_DEST/theme.txt\"|" /etc/default/grub
else
    echo "GRUB_THEME=\"$THEME_DEST/theme.txt\"" >> /etc/default/grub
fi

# Set resolution (1080p default — change if needed)
if grep -q "^GRUB_GFXMODE=" /etc/default/grub; then
    sed -i 's|^GRUB_GFXMODE=.*|GRUB_GFXMODE=1920x1080x32|' /etc/default/grub
else
    echo "GRUB_GFXMODE=1920x1080x32" >> /etc/default/grub
fi

# ── Patch theme title text ────────────────────────────────────────────────────
info "Setting theme title to 'Hello benja,'..."
if [[ -f "$THEME_DEST/theme.txt" ]]; then
    # Replace any existing title-text line, or insert after first line if absent
    if grep -q "title-text:" "$THEME_DEST/theme.txt"; then
        sed -i 's|title-text:.*|title-text: "Hello benja,"|' "$THEME_DEST/theme.txt"
    else
        sed -i '1a title-text: "Hello benja,"' "$THEME_DEST/theme.txt"
    fi
fi

# ── Regenerate GRUB config ────────────────────────────────────────────────────
info "Regenerating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

# ── Rename GRUB entries ───────────────────────────────────────────────────────
# grub.cfg is auto-generated so we patch it post-mkconfig and protect it
# with a pacman hook that re-applies the renames after every grub update.
info "Renaming GRUB entries..."

apply_grub_renames() {
    local cfg="/boot/grub/grub.cfg"
    # Windows → Windows 11 Pro
    sed -i "s/menuentry '[^']*[Ww]indows[^']*'/menuentry 'Windows 11 Pro'/g" "$cfg"
    sed -i 's/menuentry "[^"]*[Ww]indows[^"]*"/menuentry "Windows 11 Pro"/g' "$cfg"
    # linux-lts → Arch LTS
    sed -i "s/menuentry '[^']*lts[^']*'/menuentry 'Arch LTS'/gI" "$cfg"
    sed -i 's/menuentry "[^"]*lts[^"]*"/menuentry "Arch LTS"/gI' "$cfg"
}

apply_grub_renames
success "GRUB entries renamed."

# ── Pacman hook: re-apply renames after grub-mkconfig ────────────────────────
info "Installing pacman hook to preserve entry names on grub updates..."
mkdir -p /etc/pacman.d/hooks

cat > /usr/local/bin/grub-rename-entries << 'HOOK_SCRIPT'
#!/usr/bin/env bash
# Re-applies custom GRUB entry names after grub-mkconfig regenerates grub.cfg
CFG="/boot/grub/grub.cfg"
sed -i "s/menuentry '[^']*[Ww]indows[^']*'/menuentry 'Windows 11 Pro'/g" "$CFG"
sed -i 's/menuentry "[^"]*[Ww]indows[^"]*"/menuentry "Windows 11 Pro"/g' "$CFG"
sed -i "s/menuentry '[^']*lts[^']*'/menuentry 'Arch LTS'/gI" "$CFG"
sed -i 's/menuentry "[^"]*lts[^"]*"/menuentry "Arch LTS"/gI' "$CFG"
HOOK_SCRIPT
chmod +x /usr/local/bin/grub-rename-entries

cat > /etc/pacman.d/hooks/grub-rename-entries.hook << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = grub
Target = linux
Target = linux-lts

[Action]
Description = Reapplying custom GRUB entry names...
When = PostTransaction
Exec = /usr/local/bin/grub-rename-entries
EOF

# Cleanup
rm -rf "$THEME_BUILDDIR"

success "GRUB theme installed."

# =============================================================================
#  STEP 12 — Flatpak packages
# =============================================================================
info "Installing Flatpak packages..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

PACKAGES_FLATPAK=(
    com.github.tchx84.Flatseal
    com.mattjakeman.ExtensionManager
    org.libreoffice.LibreOffice
    org.localsend.localsend_app
    page.tesk.Refine
)

for pkg in "${PACKAGES_FLATPAK[@]}"; do
    if flatpak install --noninteractive flathub "$pkg"; then
        success "  $pkg"
    else
        warn "  FAILED: $pkg"
        printf '%s\n' "$pkg" >> "$REAL_HOME/hyprland-failed.txt"
    fi
done
success "Flatpak packages installed."

# =============================================================================
#  STEP 13 — Mirror config files from repo
# =============================================================================
info "Mirroring config files from repo..."

MIRROR_DIRS=(
    "home/benja|${REAL_HOME}"
    "root|/root"
    "usr|/usr"
)

for entry in "${MIRROR_DIRS[@]}"; do
    src_subdir="${entry%%|*}"
    dst_prefix="${entry##*|}"
    src_path="${SCRIPT_DIR}/${src_subdir}"

    if [[ ! -d "$src_path" ]]; then
        warn "Mirror directory '${src_subdir}/' not found in repo — skipping."
        continue
    fi

    info "Mirroring '${src_subdir}/' → '${dst_prefix}/'"
    while IFS= read -r -d '' file; do
        rel="${file#"${src_path}/"}"
        dst="${dst_prefix}/${rel}"
        dst_dir="$(dirname "$dst")"
        mkdir -p "$dst_dir"
        if cp -a "$file" "$dst"; then
            success "  Copied: ${rel} → ${dst}"
        else
            warn "  Failed to copy: ${file} → ${dst}"
            printf 'mirror: %s\n' "$dst" >> "$REAL_HOME/hyprland-failed.txt"
        fi
    done < <(find "$src_path" -type f -print0)
done

info "Fixing ownership of ${REAL_HOME}..."
chown -R "${REAL_USER}:${REAL_USER}" "$REAL_HOME"
success "Ownership set."

# =============================================================================
#  STEP 14 — Pull configs from ad1822/hyprdots
#  (dunst, rofi, hyprpaper, waybar, NetworkManager)
# =============================================================================
info "Cloning ad1822/hyprdots for config files..."

HYPRDOTS_DIR="$(mktemp -d)"
git clone --depth=1 https://github.com/ad1822/hyprdots.git "$HYPRDOTS_DIR"

# Config folders to copy and their destinations under ~/.config/
declare -A HYPRDOTS_CONFIGS=(
    ["dunst"]="$REAL_HOME/.config/dunst"
    ["rofi"]="$REAL_HOME/.config/rofi"
    ["waybar"]="$REAL_HOME/.config/waybar"
    ["hypr"]="$REAL_HOME/.config/hypr"
)

for src_folder in "${!HYPRDOTS_CONFIGS[@]}"; do
    src="$HYPRDOTS_DIR/$src_folder"
    dst="${HYPRDOTS_CONFIGS[$src_folder]}"

    if [[ ! -d "$src" ]]; then
        warn "hyprdots: '$src_folder/' not found — skipping."
        continue
    fi

    info "  Copying $src_folder → $dst"
    mkdir -p "$dst"
    # -n: don't overwrite files already placed by your own repo mirror (step 13)
    cp -rn "$src"/. "$dst/" 2>/dev/null || true
    success "  $src_folder config applied."
done

# ── NetworkManager + iwd ──────────────────────────────────────────────────────
info "Enabling NetworkManager + iwd..."
systemctl enable NetworkManager
systemctl enable iwd

# Use iwd as the wifi backend for NetworkManager
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-backend.conf << 'EOF'
[device]
wifi.backend=iwd
EOF

for src_folder in "${!HYPRDOTS_CONFIGS[@]}"; do
    chown -R "${REAL_USER}:${REAL_USER}" "${HYPRDOTS_CONFIGS[$src_folder]}" 2>/dev/null || true
done
rm -rf "$HYPRDOTS_DIR"
success "hyprdots configs applied and NetworkManager configured."

# =============================================================================
#  STEP 15 — zsh setup
# =============================================================================
info "Setting zsh as default shell for '${REAL_USER}' and root..."
chsh -s /usr/bin/zsh "$REAL_USER"
chsh -s /usr/bin/zsh root
success "Default shell set to zsh."

# ── zsh-sudo plugin ───────────────────────────────────────────────────────────
info "Installing zsh-sudo plugin..."
ZSH_SUDO_DIR="/usr/share/zsh-sudo"
mkdir -p "$ZSH_SUDO_DIR"
ZSH_SUDO_SRC="${SCRIPT_DIR}/usr/share/zsh-sudo/sudo.plugin.zsh"
if [[ -f "$ZSH_SUDO_SRC" ]]; then
    cp "$ZSH_SUDO_SRC" "${ZSH_SUDO_DIR}/sudo.plugin.zsh"
    success "sudo.plugin.zsh installed."
else
    warn "sudo.plugin.zsh not found in repo at usr/share/zsh-sudo/ — skipping."
fi

# ── Symlink /root/.zshrc → user's .zshrc ─────────────────────────────────────
info "Symlinking /root/.zshrc → ${REAL_HOME}/.zshrc..."
ln -sf "${REAL_HOME}/.zshrc" /root/.zshrc
success "/root/.zshrc symlinked."

# =============================================================================
#  STEP 16 — Hide unwanted desktop entries
# =============================================================================
info "Hiding unwanted desktop entries..."

HIDDEN_ENTRIES=(
    /usr/share/applications/avahi-discover.desktop
    /usr/share/applications/bssh.desktop
    /usr/share/applications/bvnc.desktop
    /usr/share/applications/qv4l2.desktop
    /usr/share/applications/qvidcap.desktop
    /usr/share/applications/btop.desktop
    /usr/share/applications/micro.desktop
    /usr/share/applications/cmake-gui.desktop
    /usr/share/applications/lstopo.desktop
    /usr/share/applications/nvtop.desktop
)

for entry in "${HIDDEN_ENTRIES[@]}"; do
    if [[ -f "$entry" ]]; then
        if ! grep -q '^NoDisplay=true' "$entry"; then
            echo 'NoDisplay=true' >> "$entry"
            success "  Hidden: $(basename "$entry")"
        else
            info "  Already hidden: $(basename "$entry")"
        fi
    fi
done

# =============================================================================
#  STEP 17 — Set kitty as default terminal in Nautilus
# =============================================================================
info "Configuring nautilus-open-any-terminal to use kitty..."
_uid=$(id -u "$REAL_USER")
_bus="unix:path=/run/user/${_uid}/bus"

# Session bus may not be running at install time; suppress errors gracefully
if sudo -u "$REAL_USER" env \
        DBUS_SESSION_BUS_ADDRESS="$_bus" \
        XDG_RUNTIME_DIR="/run/user/${_uid}" \
        gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty 2>/dev/null; then
    success "Kitty set as default terminal for Nautilus."
else
    warn "Could not set kitty via gsettings (session bus not running) — will apply on first login via ~/.profile."
    cat >> "${REAL_HOME}/.profile" << 'EOF'

# Set kitty as default terminal for nautilus-open-any-terminal (applied once on login)
if command -v gsettings &>/dev/null; then
    gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty 2>/dev/null || true
fi
EOF
    chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.profile"
fi

# =============================================================================
#  STEP 18 — Omarchy Waybar (exact files from basecamp/omarchy)
# =============================================================================
info "Installing Omarchy Waybar config..."

WAYBAR_DIR="${REAL_HOME}/.config/waybar"
OMARCHY_DIR_TMP="$(mktemp -d)"
git clone --depth=1 https://github.com/basecamp/omarchy.git "$OMARCHY_DIR_TMP"

mkdir -p "$WAYBAR_DIR"

# Copy config.jsonc and style.css exactly as omarchy ships them
if [[ ! -f "${WAYBAR_DIR}/config.jsonc" ]]; then
    cp "$OMARCHY_DIR_TMP/config/waybar/config.jsonc" "${WAYBAR_DIR}/config.jsonc"

    # ── Strip omarchy-specific modules that require omarchy scripts ───────────
    # Removes: custom/omarchy, custom/update, custom/screenrecording-indicator
    # and their full definition blocks from the config
    python3 - "${WAYBAR_DIR}/config.jsonc" << 'PYEOF'
import re, sys

with open(sys.argv[1], 'r') as f:
    content = f.read()

# Remove from modules-left/center arrays
content = re.sub(r',?\s*"custom/omarchy"', '', content)
content = re.sub(r',?\s*"custom/update"', '', content)
content = re.sub(r',?\s*"custom/screenrecording-indicator"', '', content)

# Remove full module definition blocks (handles trailing comma)
# Matches "key": { ... } blocks including nested braces
def remove_block(text, key):
    pattern = rf'(\s*"{re.escape(key)}"\s*:\s*\{{)'
    m = re.search(pattern, text)
    if not m:
        return text
    start = m.start()
    # find matching closing brace
    depth = 0
    i = m.end() - 1
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    # include optional trailing comma and newline
    end = i + 1
    while end < len(text) and text[end] in ' \t':
        end += 1
    if end < len(text) and text[end] == ',':
        end += 1
    if end < len(text) and text[end] == '\n':
        end += 1
    return text[:start] + text[end:]

for mod in ('custom/omarchy', 'custom/update', 'custom/screenrecording-indicator'):
    content = remove_block(content, mod)

with open(sys.argv[1], 'w') as f:
    f.write(content)
PYEOF

    success "Waybar config.jsonc copied from omarchy (omarchy-specific modules removed)."
else
    info "Waybar config.jsonc already exists (from repo mirror) — skipping."
fi

if [[ ! -f "${WAYBAR_DIR}/style.css" ]]; then
    cp "$OMARCHY_DIR_TMP/config/waybar/style.css" "${WAYBAR_DIR}/style.css"
    success "Waybar style.css copied from omarchy."
else
    info "Waybar style.css already exists (from repo mirror) — skipping."
fi

# ── style.css imports ~/.config/omarchy/current/theme/waybar.css ─────────────
# Without full omarchy installed this import fails and waybar won't start.
# Create a minimal Catppuccin Mocha stub so the bar loads correctly.
OMARCHY_THEME_DIR="${REAL_HOME}/.config/omarchy/current/theme"
if [[ ! -f "${OMARCHY_THEME_DIR}/waybar.css" ]]; then
    mkdir -p "$OMARCHY_THEME_DIR"
    cat > "${OMARCHY_THEME_DIR}/waybar.css" << 'EOF'
/* Catppuccin Mocha — omarchy waybar.css stub */
@define-color background #1e1e2e;
@define-color foreground #cdd6f4;
EOF
    success "Created omarchy theme stub at ${OMARCHY_THEME_DIR}/waybar.css"
fi

rm -rf "$OMARCHY_DIR_TMP"
chown -R "${REAL_USER}:${REAL_USER}" "$WAYBAR_DIR" "${REAL_HOME}/.config/omarchy"
success "Omarchy Waybar installed."

# =============================================================================
#  STEP 19 — BrewLand hyprlock + hypridle configs
# =============================================================================
info "Cloning BeetleBot/BrewLand for hyprlock + hypridle configs..."

BREWLAND_DIR="$(mktemp -d)"
git clone --depth=1 --branch stable \
    https://github.com/BeetleBot/BrewLand.git "$BREWLAND_DIR"

HYPR_CONF_DIR="${REAL_HOME}/.config/hypr"
mkdir -p "$HYPR_CONF_DIR"

for conf in hyprlock.conf hypridle.conf; do
    # BrewLand may keep them directly in hypr/ or in hypr/HLconfigs/
    src=$(find "$BREWLAND_DIR/hypr" -name "$conf" | head -1)
    if [[ -z "$src" ]]; then
        warn "BrewLand: $conf not found — skipping."
        continue
    fi
    dst="${HYPR_CONF_DIR}/$conf"
    if [[ ! -f "$dst" ]]; then
        cp "$src" "$dst"
        success "  $conf copied from BrewLand."
    else
        info "  $conf already exists (from repo mirror) — skipping."
    fi
done

rm -rf "$BREWLAND_DIR"
chown -R "${REAL_USER}:${REAL_USER}" "$HYPR_CONF_DIR"
success "BrewLand hyprlock + hypridle configs installed."


echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo
echo -e "  SDDM will greet you on next boot."
echo -e "  Config location: ${BOLD}~/.config/hypr/hyprland.conf${RESET}"
echo

if [[ -f "$REAL_HOME/hyprland-failed.txt" ]]; then
    warn "Some packages failed. See: ${BOLD}~/hyprland-failed.txt${RESET}"
fi
