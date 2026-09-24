#!/usr/bin/env python3
"""Deliver a per-bridge credential to a Lumina Bridge over USB serial.

Bridge firmware 1.3.0+ (esp32-bridge/src/main.cpp, "Serial console"). The
credential comes from provision_bridge_account.js on stdin and goes straight
to the bridge; it is never printed or written to disk here.

Run with the PlatformIO Python (it has pyserial):
    node tools/provision_bridge_account.js --device=<ID> --confirm --emit-credential \\
      | ~/.platformio/penv/Scripts/python.exe tools/provision_bridge_serial.py --port COM9

Other modes (no stdin):
    --id      print what the bridge reports (deviceId, version, credential?, authMode)
    --clear   remove the stored credential (bench / return-to-legacy only)

Opening the port usually resets an ESP32 dev board; the console answers a few
seconds after reset, before Wi-Fi, so this works on a unit sitting in the
captive portal too. Exit codes: 0 ok, 2 wrong device, 3 bridge refused,
4 timeout, 5 bad input.
"""

import argparse
import json
import sys
import time

import serial

# Bridge log lines worth showing while it signs in. Nothing the firmware prints
# contains the password, but only known-safe prefixes are echoed anyway.
SAFE_PREFIXES = ("LUMINA-", "[Auth]", "Signing in", "  Token obtained", "  Auth failed",
                 "[Registry]", "Firebase Auth", "Device ID", "[Boot]")


def read_lines(port, until, timeout):
    """Yield decoded lines until `until(line)` is truthy or the timeout expires."""
    deadline = time.time() + timeout
    buf = b""
    while time.time() < deadline:
        chunk = port.read(256)
        if not chunk:
            continue
        buf += chunk
        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            line = raw.decode("utf-8", "replace").rstrip("\r")
            yield line
            if until(line):
                return


def query_id(port, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        port.write(b"LUMINA-ID\n")
        for line in read_lines(port, lambda l: l.startswith("LUMINA-ID "), 1.5):
            if line.startswith("LUMINA-ID "):
                return json.loads(line[len("LUMINA-ID "):])
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", required=True)
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--timeout", type=float, default=45.0)
    ap.add_argument("--expect-device", help="refuse unless the bridge reports this deviceId")
    ap.add_argument("--force", action="store_true", help="replace an existing credential")
    ap.add_argument("--id", action="store_true", help="only report the bridge's identity")
    ap.add_argument("--clear", action="store_true", help="remove the stored credential")
    args = ap.parse_args()

    cred = None
    if not (args.id or args.clear):
        text = sys.stdin.readline()
        try:
            cred = json.loads(text)
            assert cred["uid"].startswith("bridge_") and "@" in cred["email"] and len(cred["password"]) >= 16
        except Exception:
            print("stdin must be the one-line JSON from provision_bridge_account.js --emit-credential",
                  file=sys.stderr)
            return 5

    with serial.Serial(args.port, args.baud, timeout=0.2) as port:
        ident = query_id(port, args.timeout)
        if ident is None:
            print(f"no LUMINA-ID answer on {args.port} within {args.timeout:.0f}s "
                  "(is this bridge firmware 1.3.0+?)", file=sys.stderr)
            return 4
        print(f"bridge: {json.dumps(ident)}")
        device = ident.get("deviceId", "")
        if args.expect_device and device != args.expect_device.upper():
            print(f"WRONG DEVICE: expected {args.expect_device}, bridge says {device}", file=sys.stderr)
            return 2
        if args.id:
            return 0

        if args.clear:
            port.write(b"LUMINA-CRED-CLEAR\n")
            for line in read_lines(port, lambda l: l.startswith("LUMINA-CRED-CLEAR"), 10):
                if line.startswith("LUMINA-CRED-CLEAR"):
                    print(line)
                    return 0 if line.endswith("OK") else 3
            return 4

        if cred["uid"] != f"bridge_{device}":
            print(f"WRONG DEVICE: credential is for {cred['uid']}, bridge is {device}", file=sys.stderr)
            return 2
        payload = dict(cred, force=True) if args.force else cred
        port.write(b"LUMINA-PROVISION " + json.dumps(payload).encode() + b"\n")
        result = None
        for line in read_lines(port, lambda l: l.startswith("LUMINA-PROVISION "), 10):
            if line.startswith("LUMINA-PROVISION "):
                result = line
        if result is None:
            print("no LUMINA-PROVISION answer", file=sys.stderr)
            return 4
        print(result)
        if not result.startswith(f"LUMINA-PROVISION OK {device}"):
            return 3

        # Watch the bridge sign in as itself (it applies the credential on its
        # next loop pass; if it is still inside setup(), at the end of setup).
        print("watching sign-in (up to 90 s)...")
        signed_in = False
        for line in read_lines(port, lambda l: "Token obtained" in l or "Auth failed" in l, 90):
            if line.startswith(SAFE_PREFIXES):
                print("  " + line)
            if "Token obtained" in line:
                signed_in = True
        if not signed_in:
            print("did not see a successful sign-in; check authMode with --id and the heartbeat",
                  file=sys.stderr)
            return 4
        ident = query_id(port, 10) or {}
        print(f"bridge now: {json.dumps(ident)}")
        # A fallback (e.g. uid_mismatch) also ends in "Token obtained" — as the
        # shared account. Only per_bridge is success.
        if ident.get("credential") and ident.get("authMode") == "per_bridge":
            return 0
        print("bridge is NOT signed in as its own account — see the [Auth] lines above",
              file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
