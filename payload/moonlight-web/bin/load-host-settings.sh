# Read the Wi-Fi name, passwords, and address chosen at first setup.
# Safe to source from the user scripts. The root helper has its own copy,
# because launchd runs the installed script from a different folder.
console_home() {
  if [ "$(id -u)" -eq 0 ]; then
    local name dir
    name="$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"
    case "$name" in
      ""|root|loginwindow) ;;
      *)
        dir="$(/usr/bin/dscl . -read "/Users/${name}" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
        if [ -n "$dir" ]; then
          printf '%s\n' "$dir"
          return 0
        fi
        ;;
    esac
  fi
  printf '%s\n' "${HOME:-/var/root}"
}

HOME_DIR="$(console_home)"
CONFIG_DIR="${ELI_CONFIG_DIR:-$HOME_DIR/.config/moonlight-web}"
BIN="${ELI_BIN:-$CONFIG_DIR/bin}"
SSID="host-internet"
PASSWORD="Password123"
WEB_URL="http://192.168.2.1:8080"
WEB_PORT="8080"
WEB_PATH=""
WEB_USER="user"
WEB_PASSWORD="password"
if [ -f "$CONFIG_DIR/host-settings.json" ] && [ -f "$BIN/host-settings.py" ]; then
  settings_shell="$(python3 "$BIN/host-settings.py" shell "$CONFIG_DIR/host-settings.json" 2>/dev/null || true)"
  if [ -n "$settings_shell" ]; then
    eval "$settings_shell"
  fi
fi
