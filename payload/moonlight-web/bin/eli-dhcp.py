#!/usr/bin/env python3
"""Stay-running DHCP for Eli-internet. macOS bootpd exits when idle and drops the other computer."""
from __future__ import annotations

import socket
import struct
import time

SERVER = "192.168.2.1"
MASK = "255.255.255.0"
LEASE = 86400
FIRST = 2
LAST = 200
IP_BOUND_IF = 25

leases: dict[bytes, int] = {}
used: set[int] = set()


def ip_bytes(text: str) -> bytes:
    return bytes(int(part) for part in text.split("."))


def pick(mac: bytes, requested: int | None) -> int:
    if requested and FIRST <= requested <= LAST and (requested not in used or leases.get(mac) == requested):
        leases[mac] = requested
        used.add(requested)
        return requested
    current = leases.get(mac)
    if current:
        return current
    start = FIRST + (mac[-1] % (LAST - FIRST + 1))
    for offset in range(LAST - FIRST + 1):
        candidate = FIRST + ((start - FIRST + offset) % (LAST - FIRST + 1))
        if candidate not in used:
            leases[mac] = candidate
            used.add(candidate)
            return candidate
    raise RuntimeError("no addresses left")


def option(data: bytes, code: int) -> bytes | None:
    i = 0
    while i < len(data):
        kind = data[i]
        if kind == 255:
            return None
        if kind == 0:
            i += 1
            continue
        if i + 1 >= len(data):
            return None
        length = data[i + 1]
        if kind == code:
            return data[i + 2 : i + 2 + length]
        i += 2 + length
    return None


def build(pkt: bytes, kind: int, host: int) -> bytes:
    xid = pkt[4:8]
    flags = pkt[10:12]
    giaddr = pkt[24:28]
    chaddr = pkt[28:44]
    cookie = b"\x63\x82\x53\x63"
    opts = b"".join(
        [
            bytes([53, 1, kind]),
            bytes([54, 4]) + ip_bytes(SERVER),
            bytes([51, 4]) + struct.pack("!I", LEASE),
            bytes([1, 4]) + ip_bytes(MASK),
            bytes([255]),
        ]
    )
    header = struct.pack(
        "!BBBB4sHH4s4s4s4s",
        2,
        pkt[1],
        pkt[2],
        0,
        xid,
        0,
        struct.unpack("!H", flags)[0],
        b"\x00\x00\x00\x00",
        ip_bytes(f"192.168.2.{host}"),
        ip_bytes(SERVER),
        giaddr,
    )
    return header + chaddr + (b"\x00" * 192) + cookie + opts


def main() -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        sock.setsockopt(socket.IPPROTO_IP, IP_BOUND_IF, socket.if_nametoindex("ap1"))
    except OSError:
        pass
    # Broadcast discovers are sent to 255.255.255.255. A socket bound only to
    # 192.168.2.1 never sees them, so a new computer never gets an address.
    sock.bind(("0.0.0.0", 67))
    print("eli-dhcp listening on 192.168.2.1", flush=True)
    while True:
        pkt, _addr = sock.recvfrom(2048)
        if len(pkt) < 240 or pkt[236:240] != b"\x63\x82\x53\x63":
            continue
        msg = option(pkt[240:], 53)
        if not msg:
            continue
        mac = pkt[28:34]
        requested = option(pkt[240:], 50)
        want = requested[3] if requested and len(requested) == 4 and requested[:3] == ip_bytes("192.168.2")[:3] else None
        try:
            host = pick(mac, want)
        except RuntimeError:
            continue
        if msg[0] == 1:
            reply = build(pkt, 2, host)
        elif msg[0] == 3:
            reply = build(pkt, 5, host)
        else:
            continue
        sent = False
        flags = struct.unpack("!H", pkt[10:12])[0]
        dests = ("255.255.255.255", "192.168.2.255") if flags & 0x8000 else ("192.168.2.255", "255.255.255.255")
        for dest in dests:
            try:
                sock.sendto(reply, (dest, 68))
                sent = True
                break
            except OSError as exc:
                print(f"send {dest} failed: {exc}", flush=True)
        if not sent:
            continue
        print(f"{time.strftime('%H:%M:%S')} {mac.hex()} -> 192.168.2.{host} type {msg[0]}", flush=True)


if __name__ == "__main__":
    main()
