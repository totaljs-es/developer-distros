#!/usr/bin/env python3
# TotalVM clipboard agent — bridges the Linux clipboard with the Mac host over
# vsock, so copy & paste works in both directions inside the VM.
#
# Wire protocol (matches the host's ClipboardBridge):
#   [1 byte type][4 bytes big-endian length][payload]   ; type 0x01 = UTF-8 text
#
# The host (TotalVM.app) listens on a fixed vsock port; we connect to the host
# CID and reconnect if the link drops (VM pause/resume, app relaunch). Text only.

import os
import socket
import struct
import subprocess
import threading
import time

HOST_CID = socket.VMADDR_CID_HOST  # 2 — the Mac
PORT = 7771
TYPE_TEXT = 0x01
POLL_INTERVAL = 0.5
RECONNECT_BACKOFF = 2.0
MAX_PAYLOAD = 8 * 1024 * 1024


def get_clipboard():
    """Current CLIPBOARD selection text, or None if unavailable."""
    try:
        result = subprocess.run(
            ["xclip", "-selection", "clipboard", "-o"],
            capture_output=True, timeout=2,
        )
        if result.returncode == 0:
            return result.stdout.decode("utf-8", "replace")
    except Exception:
        pass
    return None


def set_clipboard(text):
    """Own both CLIPBOARD and PRIMARY so Ctrl-V and middle-click both paste it."""
    data = text.encode("utf-8")
    for selection in ("clipboard", "primary"):
        try:
            subprocess.run(
                ["xclip", "-selection", selection],
                input=data, timeout=2,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass


class Bridge:
    def __init__(self, sock):
        self.sock = sock
        # The last text seen in either direction — so we never bounce back what
        # we just applied (which would loop the two clipboards endlessly).
        self.last_text = get_clipboard() or ""
        self.send_lock = threading.Lock()
        self.alive = True

    def send_text(self, text):
        payload = text.encode("utf-8")
        if len(payload) > MAX_PAYLOAD:
            return
        header = struct.pack("!BI", TYPE_TEXT, len(payload))
        with self.send_lock:
            self.sock.sendall(header + payload)

    def _recv_exact(self, count):
        buffer = b""
        while len(buffer) < count:
            chunk = self.sock.recv(count - len(buffer))
            if not chunk:
                return None
            buffer += chunk
        return buffer

    def reader(self):
        """Host → guest: apply incoming text to the Linux clipboard."""
        while self.alive:
            header = self._recv_exact(5)
            if header is None:
                break
            msg_type, length = struct.unpack("!BI", header)
            if length > MAX_PAYLOAD:
                break
            payload = self._recv_exact(length) if length else b""
            if payload is None:
                break
            if msg_type == TYPE_TEXT:
                text = payload.decode("utf-8", "replace")
                if text != self.last_text:
                    self.last_text = text
                    set_clipboard(text)
        self.alive = False

    def poller(self):
        """Guest → host: push new local copies to the Mac."""
        while self.alive:
            time.sleep(POLL_INTERVAL)
            text = get_clipboard()
            if not text or text == self.last_text:
                continue
            self.last_text = text
            try:
                self.send_text(text)
            except Exception:
                self.alive = False
                break


def run_once():
    sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect((HOST_CID, PORT))
    sock.settimeout(None)
    bridge = Bridge(sock)
    threading.Thread(target=bridge.poller, daemon=True).start()
    bridge.reader()  # blocks until the connection drops
    bridge.alive = False
    try:
        sock.close()
    except Exception:
        pass


def main():
    # xclip needs an X display; wait for the session if we somehow start early.
    while "DISPLAY" not in os.environ:
        time.sleep(1)
    while True:
        try:
            run_once()
        except Exception:
            pass
        time.sleep(RECONNECT_BACKOFF)


if __name__ == "__main__":
    main()
