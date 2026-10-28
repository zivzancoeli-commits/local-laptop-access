#!/bin/bash
# Installs the hotspot on this Apple laptop. Does not turn it on.
# The first run asks for the Wi-Fi name, both passwords, and the address.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
HOME_DIR="$HOME"
CONFIG="$HOME_DIR/.config/moonlight-web"
SUN="$HOME_DIR/.config/sunshine"

pause() {
  echo
  read -r -p "Press Return to close."
}

if [ -f "$CONFIG/bin/eli-internet-root" ] && grep -q 'SSID="Eli-internet"' "$CONFIG/bin/eli-internet-root"; then
  echo "This Mac already hosts Eli-internet."
  echo "This installer is for a different Mac, so nothing was changed."
  pause
  exit 1
fi

install_sunshine() {
  if [ -d /Applications/Sunshine.app ]; then
    return 0
  fi
  local asset work dmg mount app script
  case "$(uname -m)" in
    arm64) asset="Sunshine-macOS-arm64.dmg" ;;
    x86_64) asset="Sunshine-macOS-x86_64.dmg" ;;
    *)
      echo "This Mac is $(uname -m). There is no Sunshine installer for it."
      return 1
      ;;
  esac
  echo "Downloading Sunshine from its official release. This Mac needs internet for this step."
  work="$(mktemp -d)"
  dmg="$work/Sunshine.dmg"
  mount="$work/mount"
  mkdir -p "$mount"
  if ! curl -fL --retry 3 --retry-delay 2 -o "$dmg" \
    "https://github.com/LizardByte/Sunshine/releases/download/v2026.914.233613/${asset}"; then
    rm -rf "$work"
    echo "Sunshine could not be downloaded."
    return 1
  fi
  if ! hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount" >/dev/null; then
    rm -rf "$work"
    echo "The Sunshine download could not be opened."
    return 1
  fi
  app="$(find "$mount" -maxdepth 3 -name 'Sunshine.app' -type d | head -1)"
  if [ -z "$app" ]; then
    hdiutil detach "$mount" >/dev/null 2>&1 || true
    rm -rf "$work"
    echo "The Sunshine download did not contain the app."
    return 1
  fi
  script="$work/install-sunshine.sh"
  printf '#!/bin/bash\nditto %q /Applications/Sunshine.app\n' "$app" > "$script"
  chmod 755 "$script"
  if ! osascript -e "do shell script \"/bin/bash $(printf %q "$script")\" with administrator privileges with prompt \"Install Sunshine\""; then
    hdiutil detach "$mount" >/dev/null 2>&1 || true
    rm -rf "$work"
    echo "Sunshine was not installed."
    return 1
  fi
  hdiutil detach "$mount" >/dev/null 2>&1 || true
  rm -rf "$work"
}

if ! install_sunshine; then
  pause
  exit 1
fi

if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
  echo "This Apple laptop needs Rosetta once, so the stream program can run."
  if ! osascript -e 'do shell script "softwareupdate --install-rosetta --agree-to-license" with administrator privileges with prompt "Allow this Apple laptop to run the stream program"'; then
    echo "Rosetta was not installed, so nothing else was changed."
    pause
    exit 1
  fi
fi

xattr -dr com.apple.quarantine "$ROOT" 2>/dev/null || true

mkdir -p "$CONFIG/bin" "$CONFIG/logs" "$CONFIG/server" "$SUN" \
  "$HOME_DIR/Library/LaunchAgents"

echo "Choose the Wi-Fi name, the passwords, and the address."
if ! python3 "$ROOT/payload/moonlight-web/bin/host-settings.py" ask "$CONFIG/host-settings.json" 192.168.2.1; then
  echo "Setup was cancelled. Nothing else was changed."
  pause
  exit 1
fi

echo "Copying files..."
rsync -a "$ROOT/payload/moonlight-web/bin/" "$CONFIG/bin/"
rsync -a "$ROOT/payload/moonlight-web/static/" "$CONFIG/static/"
cp -p "$ROOT/payload/moonlight-web/start.sh" "$CONFIG/start.sh"
cp -p "$ROOT/payload/moonlight-web/web-server" "$CONFIG/web-server"
cp -p "$ROOT/payload/moonlight-web/streamer" "$CONFIG/streamer"
cp -p "$ROOT/payload/sunshine/sunshine.conf" "$SUN/sunshine.conf"
cp -p "$ROOT/payload/sunshine/keep-lid-awake.m" "$SUN/keep-lid-awake.m"
cp -p "$ROOT/payload/sunshine/stream-session.sh" "$SUN/stream-session.sh"
cp -p "$ROOT/payload/sunshine/set-stream-display.swift" "$SUN/set-stream-display.swift"
cp -p "$ROOT/payload/sunshine/hide-host-cursor.swift" "$SUN/hide-host-cursor.swift"

cp -p "$ROOT/payload/moonlight-web/server/config.json" "$CONFIG/server/config.json"
python3 "$CONFIG/bin/host-settings.py" apply-config "$CONFIG/server/config.json" "$CONFIG/host-settings.json" "$HOME_DIR"

python3 - "$HOME_DIR" "$ROOT/payload/sunshine/apps.json" "$SUN/apps.json" << 'PY'
import sys
from pathlib import Path
home, src, dest = sys.argv[1:]
Path(dest).write_text(Path(src).read_text().replace("__HOME__", home))
PY

python3 - "$HOME_DIR" "$ROOT/payload/launchagent.plist" "$HOME_DIR/Library/LaunchAgents/dev.moonlight.web.plist" << 'PY'
import sys
from pathlib import Path
home, src, dest = sys.argv[1:]
Path(dest).parent.mkdir(parents=True, exist_ok=True)
Path(dest).write_text(Path(src).read_text().replace("__HOME__", home))
PY

python3 "$CONFIG/bin/host-settings.py" apply-user "$CONFIG/server/data.json" "$CONFIG/host-settings.json"

echo "Installing helpers..."
PRE="$ROOT/payload/prebuilt"
if [ ! -x "$PRE/eli-host" ] || [ ! -x "$PRE/eli-clamshell-awake" ] || [ ! -x "$PRE/keep-lid-awake" ] || [ ! -x "$PRE/set-stream-display" ] || [ ! -x "$PRE/hide-host-cursor" ]; then
  echo "The helper programs are missing from this folder, so nothing else was changed."
  pause
  exit 1
fi
cp -p "$PRE/eli-host" "$CONFIG/bin/eli-host"
cp -p "$PRE/eli-clamshell-awake" "$CONFIG/bin/eli-clamshell-awake"
cp -p "$PRE/keep-lid-awake" "$SUN/keep-lid-awake"
cp -p "$PRE/set-stream-display" "$SUN/set-stream-display"
cp -p "$PRE/hide-host-cursor" "$SUN/hide-host-cursor"
chmod 755 "$CONFIG/bin/eli-host" "$CONFIG/bin/eli-clamshell-awake" \
  "$CONFIG/bin/eli-internet-root" "$CONFIG/bin/eli-buttons" \
  "$CONFIG/bin/stream-on" "$CONFIG/bin/stream-off" "$CONFIG/bin/eli-dhcp.py" \
  "$CONFIG/bin/wifi-link" "$CONFIG/bin/host-settings.py" "$CONFIG/start.sh" \
  "$SUN/keep-lid-awake" "$SUN/set-stream-display" "$SUN/hide-host-cursor" \
  "$SUN/stream-session.sh" \
  "$CONFIG/web-server" "$CONFIG/streamer"
codesign --force --sign - "$CONFIG/bin/eli-host" "$CONFIG/bin/eli-clamshell-awake" \
  "$SUN/keep-lid-awake" "$SUN/set-stream-display" "$SUN/hide-host-cursor" >/dev/null

TMP="$(mktemp -d)"
cat > "$TMP/turn-on.applescript" << 'EOF'
set homePath to POSIX path of (path to home folder)
if homePath ends with "/" then set homePath to text 1 thru -2 of homePath
set dirPath to homePath & "/.config/moonlight-web"
set statusFile to dirPath & "/eli-switch.status"
set commandFile to dirPath & "/eli-switch.command"
set buttonsBin to dirPath & "/bin/eli-buttons"
set rootBin to dirPath & "/bin/eli-internet-root"

display notification "Turning on the internet and the stream" with title "Turn On"

try
	do shell script quoted form of buttonsBin & " ready"
on error
	try
		do shell script quoted form of rootBin & " install" with prompt "Let Turn On and Turn Off work with one click" with administrator privileges
	on error
		display dialog "Turn On needs that password once. Nothing was changed." buttons {"OK"} default button 1
		return
	end try
	set ready to false
	repeat with i from 1 to 30
		try
			do shell script quoted form of buttonsBin & " ready"
			set ready to true
			exit repeat
		end try
		delay 1
	end repeat
	if ready is false then
		display dialog "Turn On could not get ready. Nothing was changed." buttons {"OK"} default button 1
		return
	end if
end try

do shell script "rm -f " & quoted form of statusFile & "; printf start > " & quoted form of (commandFile & ".tmp") & " && mv " & quoted form of (commandFile & ".tmp") & " " & quoted form of commandFile

set outcome to ""
repeat with i from 1 to 50
	try
		set outcome to do shell script "head -1 " & quoted form of statusFile
	end try
	if outcome is "on" or outcome is "cable" or outcome is "failed" then exit repeat
	delay 1
end repeat

if outcome is "cable" then
	display dialog "The phone cable is not sharing internet, so Wi-Fi was left as it is.

Unlock the phone, turn on Personal Hotspot, and use a data cable. Then click Turn On again." buttons {"OK"} default button 1
	return
end if
if outcome is not "on" then
	display dialog "The internet did not stay on, so it was turned back off." buttons {"OK"} default button 1
	return
end if

try
	do shell script dirPath & "/bin/stream-on"
on error errText
	display dialog "Internet is on, but the stream did not start.

" & errText buttons {"OK"} default button 1
	return
end try

set card to "Internet and streaming are on."
try
	set card to do shell script quoted form of (dirPath & "/bin/host-settings.py") & " card " & quoted form of (dirPath & "/host-settings.json")
end try
display dialog card buttons {"OK"} default button 1
EOF

cat > "$TMP/turn-off.applescript" << 'EOF'
set homePath to POSIX path of (path to home folder)
if homePath ends with "/" then set homePath to text 1 thru -2 of homePath
set dirPath to homePath & "/.config/moonlight-web"
set statusFile to dirPath & "/eli-switch.status"
set commandFile to dirPath & "/eli-switch.command"
set buttonsBin to dirPath & "/bin/eli-buttons"
set rootBin to dirPath & "/bin/eli-internet-root"

display notification "Turning off the internet hotspot and the stream" with title "Turn Off"

set usingService to false
try
	do shell script quoted form of buttonsBin & " ready"
	set usingService to true
end try

if usingService then
	do shell script "rm -f " & quoted form of statusFile & "; printf stop > " & quoted form of (commandFile & ".tmp") & " && mv " & quoted form of (commandFile & ".tmp") & " " & quoted form of commandFile
	set outcome to ""
	repeat with i from 1 to 25
		try
			set outcome to do shell script "head -1 " & quoted form of statusFile
		end try
		if outcome is "off" then exit repeat
		delay 1
	end repeat
else
	try
		set stillUp to do shell script dirPath & "/bin/wifi-link still-up"
	on error
		set stillUp to "no"
	end try
	if stillUp is "yes" then
		try
			do shell script quoted form of rootBin & " stop" with prompt "Turn host-internet off" with administrator privileges
		end try
	end if
end if

try
	do shell script dirPath & "/bin/stream-off"
end try

display dialog "Internet and streaming are off. This Mac can sleep again." buttons {"OK"} default button 1
EOF

rm -rf "$HOME_DIR/Desktop/Turn On.app" "$HOME_DIR/Desktop/Turn Off.app"
osacompile -o "$HOME_DIR/Desktop/Turn On.app" "$TMP/turn-on.applescript"
osacompile -o "$HOME_DIR/Desktop/Turn Off.app" "$TMP/turn-off.applescript"
codesign --force --sign - "$HOME_DIR/Desktop/Turn On.app" "$HOME_DIR/Desktop/Turn Off.app" >/dev/null
rm -rf "$TMP"

echo "One password lets Turn On and Turn Off work later without asking again."
if ! osascript -e "do shell script \"/bin/bash $(printf %q "$CONFIG/bin/eli-internet-root") install\" with administrator privileges with prompt \"Let Turn On and Turn Off work with one click\""; then
  echo "The password step was cancelled. Click Turn On on the desktop and enter it there."
fi

python3 "$CONFIG/bin/host-settings.py" note "$CONFIG/host-settings.json" > "$HOME_DIR/Desktop/How to join.txt"
echo
echo "Installed."
echo "A file named How to join.txt is on the desktop."
echo "Plug the phone into this Mac with a data cable, unlock it, and turn on Personal Hotspot."
echo "Then click Turn On on the desktop."
python3 "$CONFIG/bin/host-settings.py" note "$CONFIG/host-settings.json"
pause
