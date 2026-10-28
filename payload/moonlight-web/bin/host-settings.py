#!/usr/bin/env python3
"""First-run choices for the hotspot name, passwords, and web address."""
from __future__ import annotations

import hashlib
import json
import re
import secrets
import shlex
import subprocess
import sys
from pathlib import Path

# The other computer has no internet, so the address has to be this computer
# on the hotspot. The port stays in a small range that does not collide with
# Sunshine. https needs a certificate the browser would reject.
PORT_MIN = 8080
PORT_MAX = 8099

NAME_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9 -]{0,30}[A-Za-z0-9])?$")
WIFI_RE = re.compile(r"^[!-~]{8,63}$")
USER_RE = re.compile(r"^[A-Za-z0-9]{1,32}$")
WEB_RE = re.compile(r"^[!-~]{4,64}$")


class Cancelled(Exception):
    pass


def parse_url(url: str, host: str) -> tuple[int, str]:
    match = re.fullmatch(
        rf"http://{re.escape(host)}:(808[0-9]|809[0-9])(/[A-Za-z0-9-]{{1,20}})?",
        url.strip(),
    )
    if not match:
        raise ValueError(
            f"Use http://{host} and a port from {PORT_MIN} to {PORT_MAX}. "
            "You can add one short path, such as /play. "
            f"Example: http://{host}:8080"
        )
    port = int(match.group(1))
    if not PORT_MIN <= port <= PORT_MAX:
        raise ValueError(f"The port has to be from {PORT_MIN} to {PORT_MAX}.")
    return port, match.group(2) or ""


def normalize(raw: dict, host: str) -> dict:
    name = str(raw.get("internet_name", "")).strip()
    wifi = str(raw.get("internet_password", ""))
    user = str(raw.get("username", "")).strip()
    web = str(raw.get("password", ""))
    url = str(raw.get("url", "")).strip()
    if not NAME_RE.fullmatch(name):
        raise ValueError(
            "The Wi-Fi name needs 1 to 32 letters, numbers, spaces, or hyphens, "
            "and it cannot start or end with a space or a hyphen."
        )
    if not WIFI_RE.fullmatch(wifi):
        raise ValueError(
            "The Wi-Fi password needs 8 to 63 letters, numbers, or symbols, with no spaces."
        )
    if not USER_RE.fullmatch(user):
        raise ValueError("The website username needs 1 to 32 letters and numbers.")
    if not WEB_RE.fullmatch(web):
        raise ValueError(
            "The website password needs 4 to 64 letters, numbers, or symbols, with no spaces."
        )
    port, path = parse_url(url, host)
    return {
        "internet_name": name,
        "internet_password": wifi,
        "username": user,
        "password": web,
        "url": f"http://{host}:{port}{path}",
        "port": port,
        "path": path,
        "host": host,
    }


def load(path: Path, host: str) -> dict:
    data = json.loads(path.read_text())
    saved_host = str(data.get("host") or host)
    return normalize(data, saved_host)


def note(settings: dict) -> str:
    return (
        "On the other computer:\n\n"
        f"1. Join Wi-Fi {settings['internet_name']}\n"
        f"2. Password {settings['internet_password']}\n"
        f"3. Open {settings['url']}\n"
        f"4. Log in\n"
        f"   username {settings['username']}\n"
        f"   password {settings['password']}\n\n"
        "That computer can be a Windows laptop or an Apple laptop.\n"
        "It does not need anything installed.\n"
        "If the browser says there is no internet, type the address anyway.\n"
    )


def card(settings: dict) -> str:
    return (
        "Internet and streaming are on.\n\n"
        f"On the other computer, join Wi-Fi {settings['internet_name']}\n"
        f"password {settings['internet_password']}\n"
        f"then open {settings['url']}\n\n"
        "Website login\n"
        f"username {settings['username']}\n"
        f"password {settings['password']}\n\n"
        "That computer can be a Windows laptop or an Apple laptop.\n"
        "Keep the phone plugged in. Click Turn Off when this computer should sleep."
    )


def emit_shell(settings: dict) -> None:
    values = {
        "SSID": settings["internet_name"],
        "PASSWORD": settings["internet_password"],
        "WEB_USER": settings["username"],
        "WEB_PASSWORD": settings["password"],
        "WEB_URL": settings["url"],
        "WEB_PORT": str(settings["port"]),
        "WEB_PATH": settings["path"],
    }
    for key, value in values.items():
        print(f"{key}={shlex.quote(value)}")


def apply_user(data_path: Path, settings: dict) -> None:
    data_path.parent.mkdir(parents=True, exist_ok=True)
    if data_path.exists():
        data = json.loads(data_path.read_text())
    else:
        data = {}
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", settings["password"].encode(), salt, 600000, dklen=32)
    user = {
        "role_id": 1000000002,
        "name": settings["username"],
        "password": {"salt": salt.hex(), "hash": digest.hex(), "iterations": 600000},
        "client_unique_id": settings["username"],
    }
    users = data.get("users") if isinstance(data.get("users"), dict) else {}
    users["1000000001"] = user
    roles = data.get("roles") if isinstance(data.get("roles"), dict) else {}
    roles.setdefault(
        "1000000002",
        {
            "name": "Admin",
            "ty": "Admin",
            "default_settings": {
                "bitrate": 12000,
                "fps": 60,
                "videoFrameQueueSize": 1,
                "videoSize": "1080p",
                "videoSizeCustom": {"width": 1920, "height": 1080},
                "videoCodec": "h264",
                "forceVideoElementRenderer": False,
                "canvasRenderer": False,
                "canvasVsync": False,
                "audioSampleQueueSize": 4,
                "dataTransport": "webrtc",
                "mouseMode": "follow",
            },
            "permissions": {
                "allow_add_hosts": True,
                "maximum_bitrate_kbps": None,
                "allow_codec_h264": True,
                "allow_codec_h265": True,
                "allow_codec_av1": True,
                "allow_hdr": True,
                "allow_transport_webrtc": True,
                "allow_transport_websockets": True,
            },
        },
    )
    data.update(
        {
            "version": "3",
            "users": users,
            "hosts": data.get("hosts") if isinstance(data.get("hosts"), dict) else {},
            "roles": roles,
        }
    )
    data_path.write_text(json.dumps(data, indent=2) + "\n")
    data_path.chmod(0o600)


def apply_config(config_path: Path, settings: dict, home: str) -> None:
    data = json.loads(config_path.read_text()) if config_path.exists() else {}
    web = data.setdefault("web_server", {})
    web["bind_address"] = f"0.0.0.0:{settings['port']}"
    web["url_path_prefix"] = settings["path"]
    web["certificate"] = None
    web["session_cookie_secure"] = False
    moonlight = data.setdefault("moonlight", {})
    moonlight["pair_device_name"] = "host"
    data["streamer_path"] = f"{home}/.config/moonlight-web/streamer"
    log = data.setdefault("log", {})
    log["file_path"] = f"{home}/.config/moonlight-web/logs/web-server.log"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(data, indent=2) + "\n")


def osascript(source: str, args: list[str]) -> str:
    result = subprocess.run(
        ["osascript", "-e", source, *args],
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise Cancelled()
    return result.stdout.strip()


def ask_text(prompt: str, default: str) -> str:
    return osascript(
        '''
on run argv
  set thePrompt to item 1 of argv
  set theDefault to item 2 of argv
  set theResult to display dialog thePrompt default answer theDefault buttons {"Cancel", "Next"} default button "Next"
  return text returned of theResult
end run
''',
        [prompt, default],
    )


def ask_choice(prompt: str, buttons: list[str], default: str) -> str:
    return osascript(
        '''
on run argv
  set thePrompt to item 1 of argv
  set buttonA to item 2 of argv
  set buttonB to item 3 of argv
  set theDefault to item 4 of argv
  set theResult to display dialog thePrompt buttons {buttonA, buttonB} default button theDefault
  return button returned of theResult
end run
''',
        [prompt, buttons[0], buttons[1], default],
    )


def ask_field(prompt: str, default: str, check) -> str:
    current = default
    while True:
        value = ask_text(prompt, current)
        try:
            return check(value)
        except ValueError as error:
            ask_choice(str(error), ["OK", "Cancel"], "OK")
            current = value


def ask(path: Path, host: str) -> None:
    if path.exists():
        try:
            current = load(path, host)
        except (OSError, ValueError, json.JSONDecodeError):
            current = None
        if current is not None:
            choice = ask_choice(
                "This computer is already set up.\n\n"
                f"Wi-Fi: {current['internet_name']}\n"
                f"Wi-Fi password: {current['internet_password']}\n"
                f"Address: {current['url']}\n"
                f"Website username: {current['username']}\n"
                f"Website password: {current['password']}\n\n"
                "Keep these?",
                ["Change", "Keep"],
                "Keep",
            )
            if choice == "Keep":
                return

    name = ask_field(
        "Name the Wi-Fi the other computer will join.\n\n"
        "Use 1 to 32 letters, numbers, spaces, or hyphens.\n"
        "Do not start or end with a space.",
        "host-internet",
        lambda value: normalize({"internet_name": value, "internet_password": "Password1", "username": "user", "password": "password", "url": f"http://{host}:8080"}, host)["internet_name"],
    )
    wifi = ask_field(
        "Choose the Wi-Fi password.\n\n"
        "Use 8 to 63 letters, numbers, or symbols. No spaces.\n"
        "This is the Wi-Fi password, not the website password.",
        "",
        lambda value: normalize({"internet_name": name, "internet_password": value, "username": "user", "password": "password", "url": f"http://{host}:8080"}, host)["internet_password"],
    )
    while True:
        again = ask_text("Type the Wi-Fi password again.", "")
        if again == wifi:
            break
        ask_choice("Those Wi-Fi passwords did not match.", ["OK", "Cancel"], "OK")
    user = ask_field(
        "Choose the website username.\n\nUse 1 to 32 letters and numbers.",
        "user",
        lambda value: normalize({"internet_name": name, "internet_password": wifi, "username": value, "password": "password", "url": f"http://{host}:8080"}, host)["username"],
    )
    web = ask_field(
        "Choose the website password.\n\nUse 4 to 64 letters, numbers, or symbols. No spaces.",
        "",
        lambda value: normalize({"internet_name": name, "internet_password": wifi, "username": user, "password": value, "url": f"http://{host}:8080"}, host)["password"],
    )
    while True:
        again = ask_text("Type the website password again.", "")
        if again == web:
            break
        ask_choice("Those website passwords did not match.", ["OK", "Cancel"], "OK")
    url = ask_field(
        "Choose the address the other computer will open.\n\n"
        f"It has to start with http://{host}\n"
        f"The port has to be {PORT_MIN} to {PORT_MAX}.\n"
        "You can add a short path such as /play.\n"
        "https and any other address will not work, because that computer has no internet.",
        f"http://{host}:8080",
        lambda value: normalize({"internet_name": name, "internet_password": wifi, "username": user, "password": web, "url": value}, host)["url"],
    )
    settings = normalize(
        {
            "internet_name": name,
            "internet_password": wifi,
            "username": user,
            "password": web,
            "url": url,
        },
        host,
    )
    choice = ask_choice(
        "The other computer will use:\n\n"
        f"Wi-Fi: {settings['internet_name']}\n"
        f"Wi-Fi password: {settings['internet_password']}\n"
        f"Address: {settings['url']}\n"
        f"Website username: {settings['username']}\n"
        f"Website password: {settings['password']}",
        ["Start over", "Save"],
        "Save",
    )
    if choice != "Save":
        return ask(path, host)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(settings, indent=2) + "\n")
    path.chmod(0o600)


def check() -> None:
    host = "192.168.2.1"
    good = {
        "internet_name": "host-internet",
        "internet_password": "Password123",
        "username": "user",
        "password": "password",
        "url": "http://192.168.2.1:8080/play",
    }
    settings = normalize(good, host)
    assert settings["port"] == 8080
    assert settings["path"] == "/play"
    assert settings["url"] == "http://192.168.2.1:8080/play"
    bad = [
        {**good, "internet_name": "end-"},
        {**good, "internet_name": ""},
        {**good, "internet_name": "a" * 33},
        {**good, "internet_password": "short"},
        {**good, "internet_password": "has space1"},
        {**good, "username": "a b"},
        {**good, "password": "abc"},
        {**good, "url": "https://192.168.2.1:8080"},
        {**good, "url": "http://10.0.0.1:8080"},
        {**good, "url": "http://192.168.2.1:8079"},
        {**good, "url": "http://192.168.2.1:8100"},
        {**good, "url": "http://192.168.2.1:8080/play/more"},
        {**good, "url": "http://192.168.2.1:8080/"},
    ]
    for item in bad:
        try:
            normalize(item, host)
        except ValueError:
            continue
        raise SystemExit(f"accepted a bad choice: {item}")
    win = normalize({**good, "url": "http://192.168.137.1:8099"}, "192.168.137.1")
    assert win["port"] == 8099
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / "data.json"
        apply_user(dest, settings)
        saved = json.loads(dest.read_text())
        saved["hosts"] = {"1": {"name": "keep"}}
        dest.write_text(json.dumps(saved))
        apply_user(dest, settings)
        again = json.loads(dest.read_text())
        pw = again["users"]["1000000001"]["password"]
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            settings["password"].encode(),
            bytes.fromhex(pw["salt"]),
            pw["iterations"],
            dklen=32,
        )
        assert digest.hex() == pw["hash"]
        assert again["hosts"]["1"]["name"] == "keep"
        assert settings["url"] in note(settings)
    print("check ok")


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else ""
    if command == "check":
        check()
        return 0
    if command == "ask":
        try:
            ask(Path(argv[2]), argv[3])
        except Cancelled:
            print("Setup was cancelled. Nothing was changed.")
            return 1
        return 0
    if command == "shell":
        host = argv[3] if len(argv) > 3 else "192.168.2.1"
        emit_shell(load(Path(argv[2]), host))
        return 0
    if command == "note":
        host = argv[3] if len(argv) > 3 else "192.168.2.1"
        print(note(load(Path(argv[2]), host)))
        return 0
    if command == "card":
        host = argv[3] if len(argv) > 3 else "192.168.2.1"
        path = Path(argv[2]) if len(argv) > 2 else None
        if path and path.exists():
            settings = load(path, host)
        else:
            settings = normalize(
                {
                    "internet_name": "host-internet",
                    "internet_password": "Password123",
                    "username": "user",
                    "password": "password",
                    "url": f"http://{host}:8080",
                },
                host,
            )
        print(card(settings))
        return 0
    if command == "apply-user":
        settings = load(Path(argv[3]), "192.168.2.1")
        apply_user(Path(argv[2]), settings)
        return 0
    if command == "apply-config":
        settings = load(Path(argv[3]), "192.168.2.1")
        apply_config(Path(argv[2]), settings, argv[4])
        return 0
    print(
        "usage: host-settings.py ask FILE HOST | shell FILE | card FILE | "
        "apply-user DATA SETTINGS | apply-config CONFIG SETTINGS HOME | check",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Cancelled:
        print("Setup was cancelled. Nothing was changed.")
        raise SystemExit(1)
