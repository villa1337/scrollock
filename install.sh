#!/usr/bin/env bash
set -euo pipefail

# Scrollock installer
# Usage: curl -sSf https://raw.githubusercontent.com/villa1337/scrollock/main/install.sh | bash
#
# What this does:
#   1. Installs the scrollock binary via cargo
#   2. Installs udev rules for device access
#   3. Adds your user to the 'input' group (permanent fix)
#   4. Applies immediate permissions (no relogin required)
#   5. Detects your mouse and writes config
#   6. Installs and starts the systemd user service
#
# Requirements: Rust toolchain (cargo), systemd, Linux/Wayland

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
step()  { echo -e "\n${BOLD}→ $*${NC}"; }

# --- Preflight checks ---
step "Checking requirements..."

if ! command -v cargo &>/dev/null; then
    error "Rust toolchain not found. Install it first:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi
info "Rust toolchain found"

if [[ "$(uname)" != "Linux" ]]; then
    error "Scrollock only supports Linux"
    exit 1
fi

if [[ -z "${XDG_SESSION_TYPE:-}" ]] && [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    warn "Could not confirm Wayland session (works best on Wayland, may work on X11)"
fi

# --- Install binary ---
step "Building and installing scrollock..."

cargo install --git https://github.com/villa1337/scrollock --bin scrollock --bin slk 2>&1 | tail -5
info "Binary installed to ~/.cargo/bin/scrollock (alias: slk)"

# Ensure cargo bin is in PATH
if ! echo "$PATH" | grep -q "$HOME/.cargo/bin"; then
    export PATH="$HOME/.cargo/bin:$PATH"
    warn "Added ~/.cargo/bin to PATH for this session"
    warn "Add to your shell profile: export PATH=\"\$HOME/.cargo/bin:\$PATH\""
fi

# --- Install indicator script ---
step "Installing scroll indicator overlay..."

INDICATOR_PATH="$HOME/.local/bin/scrollock-indicator"
mkdir -p "$HOME/.local/bin"

cat > "$INDICATOR_PATH" << 'INDICATOR_EOF'
#!/usr/bin/env python3
"""Scrollock indicator: transparent overlay showing scroll mode is active."""
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gdk', '4.0')
from gi.repository import Gtk, Gdk, GLib
import signal, sys

ICON_SIZE = 48

class IndicatorWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="scrollock-indicator")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(ICON_SIZE, ICON_SIZE)
        self.set_deletable(False)
        label = Gtk.Label()
        label.set_markup(f'<span font_desc="{ICON_SIZE - 16}" foreground="#FFD700">⇕</span>')
        label.set_halign(Gtk.Align.CENTER)
        label.set_valign(Gtk.Align.CENTER)
        css = Gtk.CssProvider()
        css.load_from_string("window { background-color: rgba(0,0,0,0.75); border-radius: 24px; }")
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.set_child(label)
        self.present()

class IndicatorApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="com.villa1337.scrollock.indicator")
    def do_activate(self):
        IndicatorWindow(self).present()

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    IndicatorApp().run([])
INDICATOR_EOF

chmod +x "$INDICATOR_PATH"
info "Indicator installed to $INDICATOR_PATH"

# --- Setup udev rules + permissions ---
step "Setting up device permissions (requires sudo)..."

# Create udev rule
UDEV_RULE="/etc/udev/rules.d/60-scrollock.rules"
sudo tee "$UDEV_RULE" > /dev/null << 'UDEV_EOF'
# Scrollock: grant seat user access to input devices and uinput
ACTION!="add|change", GOTO="scrollock_end"
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
KERNEL=="event[0-9]*", SUBSYSTEM=="input", ENV{ID_INPUT_MOUSE}=="1", TAG+="uaccess"
LABEL="scrollock_end"
UDEV_EOF
info "Udev rule installed at $UDEV_RULE"

# Reload udev
sudo udevadm control --reload-rules
sudo udevadm trigger
info "Udev rules reloaded"

# Add user to input group (permanent, survives reboots — needs relogin normally)
if ! groups | grep -q '\binput\b'; then
    sudo usermod -aG input "$USER"
    info "Added $USER to 'input' group (permanent)"
else
    info "User already in 'input' group"
fi

# Apply immediate permissions (no relogin required)
# Find the user's mouse device
MOUSE_EVENT=""
for dev in /dev/input/event*; do
    if udevadm info --query=property "$dev" 2>/dev/null | grep -q "ID_INPUT_MOUSE=1"; then
        MOUSE_EVENT="$dev"
        break
    fi
done

if [[ -n "$MOUSE_EVENT" ]]; then
    sudo setfacl -m "u:$USER:rw" "$MOUSE_EVENT" 2>/dev/null || true
    sudo setfacl -m "m::rw" "$MOUSE_EVENT" 2>/dev/null || true
    info "Immediate permissions set on $MOUSE_EVENT"
else
    warn "Could not auto-detect mouse device for immediate permissions"
fi

# uinput permissions
sudo setfacl -m "u:$USER:rw" /dev/uinput 2>/dev/null || true
sudo setfacl -m "m::rw" /dev/uinput 2>/dev/null || true
info "Immediate permissions set on /dev/uinput"

# --- Setup and start ---
step "Detecting mouse and creating config..."

# Run scrollock --setup (interactive mouse detection + config write)
scrollock --setup --install-udev-rule 2>/dev/null || scrollock --setup 2>/dev/null || {
    # If --setup fails, create a minimal config
    CONFIG_DIR="$HOME/.config/scrollock"
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config.toml" << 'CONFIG_EOF'
mode = "toggle"
hold_threshold_ms = 155
CONFIG_EOF
    warn "Auto-detection failed. Edit ~/.config/scrollock/config.toml to add your mouse."
    warn "Run 'scrollock --list-devices' to find your mouse, then add [device_match] section."
}

# Ensure toggle mode is set in config
CONFIG_FILE="$HOME/.config/scrollock/config.toml"
if [[ -f "$CONFIG_FILE" ]] && ! grep -q "^mode" "$CONFIG_FILE"; then
    sed -i '1i mode = "toggle"\nhold_threshold_ms = 155\n' "$CONFIG_FILE"
fi

info "Config saved to ~/.config/scrollock/config.toml"

step "Installing and starting service..."

scrollock --install-service 2>/dev/null && info "Service installed" || warn "Service install failed — try manually: scrollock --install-service"
scrollock --start 2>/dev/null && info "Service started!" || warn "Service start failed — try manually: scrollock --start"

# --- Done ---
echo ""
echo -e "${BOLD}${GREEN}✓ Scrollock installed successfully!${NC}"
echo ""
echo "  Usage:"
echo "    • Double middle-click → enter scroll mode (locked)"
echo "    • Hold middle button ~140ms → enter scroll mode (locked)"
echo "    • Move mouse to scroll (speed follows distance)"
echo "    • Any click → exit scroll mode"
echo ""
echo "  Commands:"
echo "    scrollock --start / --stop / --restart"
echo "    slk --start  (short alias)"
echo ""
echo "  Config: ~/.config/scrollock/config.toml"
echo "  Logs:   journalctl --user -u scrollock -f"
echo ""
