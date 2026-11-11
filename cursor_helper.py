#!/usr/bin/env python3
"""
Helper for cursorSpotlight DMS plugin on Niri / Wayland.
Monitors mouse/touchpad devices via python-evdev for global click events
(BTN_LEFT, BTN_RIGHT, BTN_MIDDLE) and relative motion while dragging.
"""

import os
import select
import sys
import time

try:
    import evdev
    from evdev import ecodes
except ImportError:
    print("STATUS NO_EVDEV", flush=True)
    sys.exit(0)

BTN_MAP = {
    ecodes.BTN_LEFT: "LEFT",
    ecodes.BTN_RIGHT: "RIGHT",
    ecodes.BTN_MIDDLE: "MIDDLE",
}


def has_all_mouse_permissions() -> bool:
    """Check if all mouse handlers in /proc/bus/input/devices are readable."""
    found_any = False
    try:
        with open("/proc/bus/input/devices", "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        for block in content.split("\n\n"):
            if "mouse" in block and "Handlers=" in block:
                for token in block.split():
                    if token.startswith("event"):
                        dev_path = f"/dev/input/{token}"
                        if os.path.exists(dev_path):
                            found_any = True
                            if not os.access(dev_path, os.R_OK):
                                return False
    except Exception:
        return False
    return found_any


def find_pointer_devices(existing_paths: set):
    """Find readable evdev devices that have BTN_LEFT and pointer axes."""
    found = []
    for path in evdev.list_devices():
        if path in existing_paths:
            continue
        try:
            dev = evdev.InputDevice(path)
            caps = dev.capabilities()
            keys = caps.get(ecodes.EV_KEY, [])
            rels = caps.get(ecodes.EV_REL, [])
            abss = caps.get(ecodes.EV_ABS, [])
            if ecodes.BTN_LEFT in keys and (ecodes.REL_X in rels or ecodes.ABS_X in abss):
                found.append(dev)
            else:
                dev.close()
        except Exception:
            pass
    return found


def main():
    devices = {}  # fd -> InputDevice
    known_paths = set()
    last_scan = 0.0
    last_perm_status = None
    last_move_emit = 0.0
    last_btn_ts = {}  # (btn, val) -> monotonic timestamp (dedup input-remapper + raw)
    acc_dx = 0
    acc_dy = 0

    while True:
        now = time.monotonic()
        scan_interval = 1.0 if last_perm_status != "STATUS OK" else 3.0
        if now - last_scan >= scan_interval:
            last_scan = now
            new_devs = find_pointer_devices(known_paths)
            for d in new_devs:
                devices[d.fd] = d
                known_paths.add(d.path)

            perm_ok = has_all_mouse_permissions() and len(devices) > 0
            status_str = "STATUS OK" if perm_ok else "STATUS NEEDS_PERM"
            if status_str != last_perm_status:
                print(status_str, flush=True)
                last_perm_status = status_str

        if not devices:
            time.sleep(0.5)
            continue

        try:
            r, _, _ = select.select(list(devices.keys()), [], [], 0.3)
        except Exception:
            for fd, d in list(devices.items()):
                try:
                    os.fstat(fd)
                except Exception:
                    known_paths.discard(d.path)
                    devices.pop(fd, None)
            continue

        for fd in r:
            dev = devices.get(fd)
            if not dev:
                continue
            try:
                for event in dev.read():
                    if event.type == ecodes.EV_KEY and event.code in BTN_MAP:
                        btn = BTN_MAP[event.code]
                        val = event.value
                        if val in (0, 1):
                            t = time.monotonic()
                            key = (btn, val)
                            if t - last_btn_ts.get(key, 0.0) > 0.018:
                                last_btn_ts[key] = t
                                if val == 1:
                                    print(f"DOWN {btn}", flush=True)
                                else:
                                    print(f"UP {btn}", flush=True)
                    elif event.type == ecodes.EV_REL:
                        if event.code == ecodes.REL_X:
                            acc_dx += event.value
                        elif event.code == ecodes.REL_Y:
                            acc_dy += event.value
                    elif event.type == ecodes.EV_SYN and (acc_dx != 0 or acc_dy != 0):
                        t = time.monotonic()
                        if t - last_move_emit >= 0.012:
                            print(f"MOVE {acc_dx} {acc_dy}", flush=True)
                            acc_dx = 0
                            acc_dy = 0
                            last_move_emit = t
            except OSError:
                known_paths.discard(dev.path)
                devices.pop(fd, None)
                try:
                    dev.close()
                except Exception:
                    pass


if __name__ == "__main__":
    main()
