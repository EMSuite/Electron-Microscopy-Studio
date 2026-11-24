# tools/size-table/size_table.py: the size table's harness (#904, plan row X12). For each generated file it launches the app fresh,
# opens the file through the agent door's open_file (the code path File > Open takes), waits until the open has landed and every room
# is idle, then reads the app's own footprint from get_window: at rest, and the peak since launch. One launch per file, so the peak is
# that open's alone. Standard library only.
#
#   python3 -I -B size_table.py --app "/Applications/Electron Microscopy Studio.app" --agent-folder <folder> --out <dir> <file>...
#   python3 -I -B size_table.py --self-test
#
# Before a run: in the build under test, Settings > Agents, door on, runs allowed, Agent folder = --agent-folder (the generated files
# must be inside it). Copy Connection Command and put the Bearer value alone in $TMPDIR/door-token (chmod 600); never print it.
# The app is started by its executable so its pid is known; it is ended by that pid (TERM, then KILL after 30 s), never by name.
#
# The door has no "open finished" event, so the harness asks get_window every half second while an open runs (as door-check does).
# It also holds the cap: when the app's footprint (what the size rule counts; mapped file pages are not in it) passes --cap-gb, the
# app is ended by its pid and the row says so, so a room over the cap is a row, not a lost run.
#
# Out: results.json (one row a file) and table.md (the rows for docs/performance.md). Exit 0 when every file was measured, 1 when
# one failed to open or timed out (its row says why), 2 when the door, the token or the app is missing.
import argparse
import json
import os
import plistlib
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

GIB = 1 << 30

ROOM_OF_KIND = {"image-tiff": "Image", "image-mrc": "Image", "stack-tiff": "Image", "eels-hspy": "EELS", "eds-hspy": "EDS",
                "patterns-h5": "Patterns"}


class Door:
    def __init__(self, port, token):
        self.url = f"http://127.0.0.1:{port}/mcp"
        self.token = token
        self.session = None
        self.next_id = 1

    def rpc(self, method, params=None, notification=False, timeout=60):
        body = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if not notification:
            body["id"] = self.next_id
            self.next_id += 1
        request = urllib.request.Request(self.url, data=json.dumps(body).encode(), method="POST")
        request.add_header("Authorization", f"Bearer {self.token}")
        request.add_header("Content-Type", "application/json")
        request.add_header("Accept", "application/json, text/event-stream")
        if self.session:
            request.add_header("Mcp-Session-Id", self.session)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            self.session = response.headers.get("Mcp-Session-Id") or self.session
            text = response.read().decode()
        if text.startswith(("event", "data")):
            text = [line[5:] for line in text.splitlines() if line.startswith("data:")][-1]
        return json.loads(text) if text.strip() else None

    def start(self):
        self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "size-table", "version": "1"}})
        self.rpc("notifications/initialized", notification=True)

    def call(self, tool, **arguments):
        answer = self.rpc("tools/call", {"name": tool, "arguments": arguments}) or {}
        if "error" in answer:
            return True, answer["error"].get("message", str(answer["error"]))
        result = answer.get("result", {})
        text = "\n".join(c.get("text", "") for c in result.get("content", []) if c.get("type") == "text")
        try:
            value = json.loads(text)
        except ValueError:
            value = text
        return bool(result.get("isError")), value


def kind_of(path):
    stem = Path(path).name
    return next((k for k in ROOM_OF_KIND if stem.startswith(k)), "")


def landed(window, name):
    """The open is over: no open runs, no room is busy, and the file is in (an Open Files row read, or a room's document) or refused."""
    if window.get("opening") or window.get("busy_rooms"):
        return None
    if any(f.get("name") == name and f.get("state") == "read" for f in window.get("files", [])):
        return "read"
    if name in window.get("room_files", []):
        return "read"
    if window.get("error"):
        return "refused"
    if not any(f.get("name") == name for f in window.get("files", [])):
        return "refused"  # no row and no room holds it: the open ended without the file (its refusal is in the log)
    return None


def factors(stored, baseline, peak, rest):
    """Peak and rest over the stored bytes, each counted above the footprint of the empty app (the design's factor)."""
    return round((peak - baseline) / stored, 2), round((rest - baseline) / stored, 2)


def executable(app):
    info = plistlib.loads((Path(app) / "Contents" / "Info.plist").read_bytes())
    return Path(app) / "Contents" / "MacOS" / info["CFBundleExecutable"]


def end(process):
    if process.poll() is not None:
        return
    os.kill(process.pid, signal.SIGTERM)
    try:
        process.wait(30)
    except subprocess.TimeoutExpired:
        os.kill(process.pid, signal.SIGKILL)
        process.wait()


def measure(args, token, path):
    name = Path(path).name
    stored = Path(path).stat().st_size
    row = {"file": name, "kind": kind_of(path), "stored_bytes": stored}
    process = subprocess.Popen([str(executable(args.app))], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        door = Door(args.port, token)
        deadline = time.monotonic() + 90
        while True:
            try:
                door.start()
                break
            except (urllib.error.URLError, ConnectionError):
                if time.monotonic() > deadline or process.poll() is not None:
                    row["note"] = "the door did not answer within 90 s of the launch"
                    return row
                time.sleep(0.5)
        refused, windows = door.call("list_windows")
        if refused or not windows.get("windows"):
            row["note"] = "the app has no window"
            return row
        time.sleep(2)  # the launch settles before the baseline is read
        _, window = door.call("get_window")
        baseline = window["memory"]["footprint_bytes"]
        relative = os.path.relpath(Path(path).resolve(), Path(args.agent_folder).resolve())
        begin = time.monotonic()
        refused, answer = door.call("open_file", path=relative)
        if refused:
            row["note"] = f"open_file refused: {answer}"
            return row
        while True:
            time.sleep(0.5)
            _, window = door.call("get_window")
            footprint = (window.get("memory") or {}).get("footprint_bytes", 0)
            if footprint > args.cap_gb * GIB:
                row["note"] = f"over the cap: {gb(footprint)} of footprint passed {args.cap_gb} GB, the app was ended"
                row["seconds"] = round(time.monotonic() - begin, 1)
                return row
            outcome = landed(window, name)
            if outcome:
                break
            if time.monotonic() - begin > args.timeout:
                row["note"] = f"not open after {args.timeout} s"
                return row
            if process.poll() is not None:
                row["note"] = "the app ended during the open (the memory cap, or a crash)"
                return row
        seconds = time.monotonic() - begin
        time.sleep(3)  # at rest: whatever the open left behind has settled
        _, window = door.call("get_window")
        rest, peak = window["memory"]["footprint_bytes"], window["memory"]["peak_footprint_bytes"]
        peak_factor, rest_factor = factors(stored, baseline, peak, rest)
        _, log = door.call("get_log")
        lines = log.get("lines", []) if isinstance(log, dict) else []
        row.update({"outcome": outcome, "room": window.get("room"), "seconds": round(seconds, 1), "baseline_bytes": baseline,
                    "peak_bytes": peak, "rest_bytes": rest, "peak_factor": peak_factor, "rest_factor": rest_factor,
                    "last_lines": lines[-3:]})
        if outcome == "refused":
            row["note"] = window.get("error") or (lines[-1] if lines else "refused")
        return row
    finally:
        end(process)


def gb(n):
    return f"{n / GIB:.2f} GB"


def table(rows):
    out = ["| Room | File | Stored | Time to open | Peak | At rest | Peak factor | Rest factor | Note |", "|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if "peak_bytes" in r:
            out.append(f"| {r.get('room', '')} | {r['file']} | {gb(r['stored_bytes'])} | {r['seconds']} s | {gb(r['peak_bytes'])} | "
                       f"{gb(r['rest_bytes'])} | {r['peak_factor']} | {r['rest_factor']} | {r.get('note', '')} |")
        else:
            out.append(f"| {ROOM_OF_KIND.get(r['kind'], '')} | {r['file']} | {gb(r['stored_bytes'])} | | | | | | {r.get('note', '')} |")
    return "\n".join(out) + "\n"


def self_test():
    assert factors(GIB, 200 << 20, (200 << 20) + 3 * GIB, (200 << 20) + 2 * GIB) == (3.0, 2.0)
    assert landed({"opening": True, "busy_rooms": [], "files": []}, "a.tif") is None
    assert landed({"opening": False, "busy_rooms": ["EELS"], "files": [], "room_files": ["a.hspy"]}, "a.hspy") is None
    assert landed({"opening": False, "busy_rooms": [], "files": [], "room_files": ["a.hspy"]}, "a.hspy") == "read"
    assert landed({"opening": False, "busy_rooms": [], "files": [{"name": "a.tif", "state": "reading"}], "room_files": []}, "a.tif") is None
    assert landed({"opening": False, "busy_rooms": [], "files": [{"name": "a.tif", "state": "read"}], "room_files": []}, "a.tif") == "read"
    assert landed({"opening": False, "busy_rooms": [], "files": [], "room_files": [], "error": None}, "a.tif") == "refused"
    assert kind_of("/x/eels-hspy-4gb.hspy") == "eels-hspy" and kind_of("/x/other.tif") == ""
    rows = [{"file": "a.tif", "kind": "image-tiff", "stored_bytes": GIB, "room": "Image", "seconds": 1.5, "peak_bytes": 3 * GIB,
             "rest_bytes": 2 * GIB, "peak_factor": 2.8, "rest_factor": 1.8},
            {"file": "b.h5", "kind": "patterns-h5", "stored_bytes": GIB, "note": "not open after 10 s"}]
    lines = table(rows).splitlines()
    assert len(lines) == 4 and "| 2.8 |" in lines[2] and lines[3].startswith("| Patterns | b.h5")
    print("size_table self-test: ok")


def main():
    parser = argparse.ArgumentParser(description="The size table's harness (#904).")
    parser.add_argument("files", nargs="*", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--agent-folder", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--port", type=int, default=47812)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--cap-gb", type=float, default=max(1, os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / GIB - 4),
                        help="end the app when its footprint passes this; default this Mac's memory minus 4 GB, the size rule's margin")
    parser.add_argument("--token-file", type=Path, default=Path(os.environ.get("TMPDIR", "/tmp")) / "door-token")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not (args.app and args.agent_folder and args.out and args.files):
        parser.error("--app, --agent-folder, --out and at least one file are needed")
    if not executable(args.app).exists():
        sys.exit(2)
    try:
        token = args.token_file.read_text().strip()
    except OSError:
        print(f"no door token in {args.token_file}", file=sys.stderr)
        sys.exit(2)
    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    for path in args.files:
        row = measure(args, token, path)
        rows.append(row)
        print(json.dumps({k: v for k, v in row.items() if k != "last_lines"}), flush=True)
        (args.out / "results.json").write_text(json.dumps(rows, indent=1) + "\n")
    (args.out / "table.md").write_text(table(rows))
    sys.exit(0 if all("peak_bytes" in r and r.get("outcome") == "read" for r in rows) else 1)


if __name__ == "__main__":
    main()
