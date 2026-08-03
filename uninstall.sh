#!/usr/bin/env bash
set -euo pipefail

# Scrollock uninstaller
# Removes all traces: binary, config, service, udev rule, indicator

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
step()  { echo -e "\n${BOLD}→ $*${NC}"; }

step "Stopping service..."
systemctl --user stop scrollock.service 2>/dev/null && info "Service stopped" || warn "Service not running"
systemctl --user disable scrollock.service 2>/dev/null && info "Service disabled" || true

step "Removing service file..."
rm -f "$HOME/.config/systemd/user/scrollock.service" && info "Service file removed" || true
systemctl --user daemon-reload 2>/dev/null

step "Removing config..."
rm -rf "$HOME/.config/scrollock" && info "Config removed (~/.config/scrollock/)" || true

step "Removing binaries..."
rm -f "$HOME/.cargo/bin/scrollock" "$HOME/.cargo/bin/slk" && info "Binaries removed" || true

step "Removing indicator..."
rm -f "$HOME/.local/bin/scrollock-indicator" && info "Indicator removed" || true

step "Removing udev rule (requires sudo)..."
sudo rm -f /etc/udev/rules.d/60-scrollock.rules && info "Udev rule removed" || warn "Failed (may need sudo)"
sudo udevadm control --reload-rules 2>/dev/null || true

step "Removing user from input group (optional)..."
echo "  Skipping — other tools may need the 'input' group."
echo "  To remove manually: sudo gpasswd -d $USER input"

# Also clean up legacy wheeltani traces
step "Cleaning legacy Wayland-Wheeltani traces..."
systemctl --user stop wayland-wheeltani.service 2>/dev/null || true
systemctl --user disable wayland-wheeltani.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/wayland-wheeltani.service" 2>/dev/null || true
rm -rf "$HOME/.config/wayland-wheeltani" 2>/dev/null || true
rm -f "$HOME/.cargo/bin/wayland-wheeltani" "$HOME/.cargo/bin/wlw" 2>/dev/null || true
sudo rm -f /etc/udev/rules.d/60-wayland-wheeltani.rules 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true
info "Legacy traces cleaned"

echo ""
echo -e "${BOLD}${GREEN}✓ Scrollock fully uninstalled.${NC}"
echo ""
