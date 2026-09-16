#!/usr/bin/env python3
"""Drive fm-watch and fm-branch-outcome live for supervision noise-fix scenarios."""
import os
import re
import subprocess
import tempfile
import time
import hashlib
import textwrap
from pathlib import Path

ROOT = Path("/home/nunoras/.no-mistakes/worktrees/53c53b70f8b7/01M2KKX2SM77NW3MHQF6NG4ZS6")
EV = Path("/home/nunoras/.no-mistakes/evidence/01M2KKX2SM77NW3MHQF6NG4ZS6/manual-live")
EV.mkdir(parents=True, exist_ok=True)
WATCH = ROOT / "bin/fm-watch.sh"
DRAIN = ROOT / "bin/fm-wake-drain.sh"
OUTCOME = ROOT / "bin/fm-branch-outcome.sh"
results = []


def hash_text(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()


def seen_sig(path: Path) -> str:
    st = path.stat()
    return f"{st.st_size}:{int(st.st_mtime)}"


def write_index(state: Path, task: str, seq: int) -> None:
    status = state / f"{task}.status"
    script = f"""
set -e
. "{ROOT}/bin/fm-classify-lib.sh"
status="{status}"
size=$(LC_ALL=C stat -c '%s' "$status")
ident=$(_fm_open_decisions_file_ident "$status")
printf 'fm-branch-outcome-index-v1\\t{seq}\\t%s\\t%s\\n' "$size" "$ident" > "{state}/.{task}.branch-outcome-index"
"""
    subprocess.check_call(["bash", "-c", script])


def make_case(name: str):
    base = Path(tempfile.mkdtemp(prefix=f"live-{name}-"))
    state = base / "state"
    fakebin = base / "fakebin"
    state.mkdir()
    fakebin.mkdir()
    tmux = fakebin / "tmux"
    tmux.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env bash
            set -e
            case "$1" in
              list-windows)
                printf '%s\\n' "${FM_FAKE_TMUX_WINDOW:-}"
                ;;
              capture-pane)
                if [ -n "${FM_FAKE_TMUX_CAPTURE:-}" ] && [ -f "$FM_FAKE_TMUX_CAPTURE" ]; then
                  cat "$FM_FAKE_TMUX_CAPTURE"
                else
                  printf ''
                fi
                ;;
              display-message)
                printf '%s\\n' "${FM_FAKE_TMUX_CURRENT_COMMAND:-bash}"
                ;;
              *) exit 0 ;;
            esac
            """
        )
    )
    tmux.chmod(0o755)
    crew = fakebin / "fm-crew-state.sh"
    crew.write_text(
        textwrap.dedent(
            """\
            #!/usr/bin/env bash
            printf '%s\\n' "${FM_FAKE_CREW_STATE:-state: unknown · source: none · no current-state source available}"
            """
        )
    )
    crew.chmod(0o755)
    return base, state, fakebin


def wait_absorb(state: Path, proc, needle: str, timeout=25.0):
    triage = state / ".watch-triage.log"
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            text = triage.read_text(errors="replace") if triage.exists() else ""
            return False, f"exited early rc={proc.returncode}\n{text}"
        if triage.exists():
            text = triage.read_text(errors="replace")
            if needle in text:
                return True, text
        time.sleep(0.1)
    t = triage.read_text(errors="replace") if triage.exists() else ""
    return False, t


def wait_exit(proc, timeout=20.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return True
        time.sleep(0.1)
    proc.terminate()
    try:
        proc.wait(2)
    except Exception:
        proc.kill()
    return False


def start_watch(state, fakebin, out, extra_env=None, poll="3"):
    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{fakebin}:{env.get('PATH', '')}",
            "FM_STATE_OVERRIDE": str(state),
            "FM_CREW_STATE_BIN": str(fakebin / "fm-crew-state.sh"),
            "FM_POLL": poll,
            "FM_SIGNAL_GRACE": "1",
            "FM_CHECK_INTERVAL": "999999",
            "FM_HEARTBEAT": "999999",
            "FM_FAKE_CREW_STATE": "state: unknown · source: none · no current-state source available",
        }
    )
    if extra_env:
        env.update(extra_env)
    outf = open(out, "w")
    p = subprocess.Popen(["bash", str(WATCH)], env=env, stdout=outf, stderr=subprocess.STDOUT)
    return p, outf


def stop(p, outf=None):
    if p.poll() is None:
        p.terminate()
        try:
            p.wait(3)
        except Exception:
            p.kill()
    if outf:
        outf.close()


# ---------- Scenario 1: covered turn-end absorbed ----------
base, state, fakebin = make_case("covered")
window = "test:live-covered"
(state / "covered.status").write_text("done: PR https://example.test/pr/9 checks green\n")
(state / "covered.meta").write_text(f"window={window}\nkind=ship\nharness=pi\n")
write_index(state, "covered", 7)
(state / ".seen-covered_status").write_text(seen_sig(state / "covered.status"))
(state / "covered.turn-ended").write_text("")
out = base / "watch.out"
p, of = start_watch(state, fakebin, out, {"FM_FAKE_TMUX_WINDOW": window})
ok, triage = wait_absorb(state, p, "absorbed benign signal (outcome-covered)")
out_txt = out.read_text() if out.exists() else ""
queue = (state / ".wake-queue").read_text() if (state / ".wake-queue").exists() else ""
key = window.replace(":", "_").replace("/", "_").replace(".", "_")
marker = state / f".turnend-covered-since-{key}"
passed = ok and not out_txt.strip() and not queue.strip() and marker.exists()
results.append(("covered-turnend-absorbed", passed))
(EV / "01-covered-turnend-absorb.txt").write_text(
    f"passed={passed}\ntriage_hit={ok}\nwatch.out=[{out_txt}]\nqueue=[{queue}]\n"
    f"marker={marker.exists()}\nindex={(state / '.covered.branch-outcome-index').read_text()}\n"
    f"status={(state / 'covered.status').read_text()}\ntriage_tail=\n{triage[-2000:]}\n"
)
stop(p, of)

# ---------- Scenario 2: first sight decision surfaces ----------
base, state, fakebin = make_case("firstsight")
window = "test:live-first"
(state / "first.status").write_text("")
write_index(state, "first", 9)
(state / "first.status").write_text("needs-decision: choose deploy target\n")
(state / "first.meta").write_text(f"window={window}\nkind=ship\nharness=pi\n")
(state / "first.turn-ended").write_text("")
out = base / "watch.out"
p, of = start_watch(state, fakebin, out, {"FM_FAKE_TMUX_WINDOW": window})
exited = wait_exit(p)
out_txt = out.read_text() if out.exists() else ""
drain = subprocess.run(
    ["bash", str(DRAIN)],
    env={**os.environ, "FM_STATE_OVERRIDE": str(state)},
    capture_output=True,
    text=True,
)
passed = exited and "signal:" in out_txt and "\tsignal\t" in drain.stdout
results.append(("first-sight-decision-surfaces", passed))
(EV / "02-first-sight-decision.txt").write_text(
    f"passed={passed}\nexited={exited}\nwatch.out=\n{out_txt}\ndrain=\n{drain.stdout}\n"
    f"status={(state / 'first.status').read_text()}\n"
)
stop(p, of)

# ---------- Scenario 3: terminal rehash absorbed ----------
base, state, fakebin = make_case("term")
window = "test:live-term"
capture = base / "pane.txt"
capture.write_text("finished, awaiting teardown")
(state / "term.meta").write_text(f"window={window}\nkind=ship\n")
(state / "term.status").write_text("done: PR https://example.test/pr/3\n")
write_index(state, "term", 12)
(state / ".seen-term_status").write_text(seen_sig(state / "term.status"))
key = window.replace(":", "_").replace("/", "_").replace(".", "_")
(state / f".hash-{key}").write_text(hash_text("finished, awaiting teardown"))
(state / f".count-{key}").write_text("1\n")
out = base / "watch.out"
p, of = start_watch(
    state,
    fakebin,
    out,
    {
        "FM_FAKE_TMUX_WINDOW": window,
        "FM_FAKE_TMUX_CAPTURE": str(capture),
    },
    poll="1",
)
ok, triage = wait_absorb(state, p, "absorbed stale (outcome-covered):")
out_txt = out.read_text() if out.exists() else ""
queue = (state / ".wake-queue").read_text() if (state / ".wake-queue").exists() else ""
shared = state / f".paused-resurfaced-{key}"
passed = ok and not out_txt.strip() and not queue.strip() and not shared.exists()
results.append(("terminal-rehash-absorbed", passed))
(EV / "03-terminal-rehash-absorb.txt").write_text(
    f"passed={passed}\nwatch.out=[{out_txt}]\nqueue=[{queue}]\nshared_throttle={shared.exists()}\n"
    f"index={(state / '.term.branch-outcome-index').read_text()}\ntriage_tail=\n{triage[-2000:]}\n"
)
stop(p, of)

# ---------- Scenario 4: static pane stays silent after absorb + repaint ----------
base, state, fakebin = make_case("static")
window = "test:live-static"
capture = base / "pane.txt"
key = window.replace(":", "_").replace("/", "_").replace(".", "_")
(state / "static.meta").write_text(f"window={window}\nkind=ship\nharness=grok\nbackend=tmux\n")
(state / "static.status").write_text("done: PR https://example.test/pr/21 checks green\n")
(state / ".seen-static_status").write_text(seen_sig(state / "static.status"))
write_index(state, "static", 14)
os.utime(state / ".static.branch-outcome-index", (time.time() - 3600, time.time() - 3600))


def run_round(mode, text=None):
    if text is not None:
        capture.write_text(text)
        (state / f".hash-{key}").write_text(hash_text(text))
        (state / f".count-{key}").write_text("1\n")
    outp = base / "watch.out"
    outp.write_text("")
    env_extra = {
        "FM_FAKE_TMUX_WINDOW": window,
        "FM_FAKE_TMUX_CAPTURE": str(capture),
        "FM_FAKE_TMUX_CURRENT_COMMAND": "grok",
        "FM_WATCH_HANDLING_SUCCESSOR": "1",
        "FM_PAUSE_RESURFACE_SECS": "600",
    }
    p, of = start_watch(state, fakebin, outp, env_extra, poll="1")
    if mode == "absorb":
        ok, t = wait_absorb(state, p, f"absorbed stale (outcome-covered): {window}")
        stop(p, of)
        return ok, outp.read_text() if outp.exists() else "", t
    beat = state / ".last-watcher-beat"
    if beat.exists():
        beat.unlink()

    def wait_beat(prev=None, timeout=30):
        d = time.time() + timeout
        while time.time() < d:
            if p.poll() is not None:
                return None
            if beat.exists():
                cur = beat.read_text()
                if prev is None or cur != prev:
                    return cur
            time.sleep(0.05)
        return None

    b1 = wait_beat()
    b2 = wait_beat(b1) if b1 is not None else None
    b3 = wait_beat(b2) if b2 is not None else None
    alive = p.poll() is None and b3 is not None
    out_txt = outp.read_text() if outp.exists() else ""
    stop(p, of)
    return alive and not out_txt.strip(), out_txt, f"beats={b1!r}->{b2!r}->{b3!r}"


ok1, o1, t1 = run_round("absorb", "finished, awaiting teardown")
ok2, o2, t2 = run_round("poll")
ok3, o3, t3 = run_round("absorb", "finished, awaiting teardown (repaint)")
ok4, o4, t4 = run_round("poll")
queue = (state / ".wake-queue").read_text() if (state / ".wake-queue").exists() else ""
passed = ok1 and ok2 and ok3 and ok4 and not queue.strip()
results.append(("static-covered-pane-stays-silent", passed))
(EV / "04-static-pane-silent.txt").write_text(
    f"passed={passed}\nok={[ok1, ok2, ok3, ok4]}\nouts={[o1, o2, o3, o4]!r}\n"
    f"notes={[str(t1)[-200:], t2, str(t3)[-200:], t4]!r}\nqueue=[{queue}]\n"
)

# ---------- Scenario 5: post-steer stop surfaces ----------
base, state, fakebin = make_case("steer")
window = "test:live-steer"
(state / "steered.status").write_text("done: PR https://example.test/pr/9 checks green\n")
(state / "steered.meta").write_text(f"window={window}\nkind=ship\nharness=pi\n")
write_index(state, "steered", 7)
os.utime(state / ".steered.branch-outcome-index", (time.time() - 3600, time.time() - 3600))
(state / ".seen-steered_status").write_text(seen_sig(state / "steered.status"))
inbox = state / "steered.inbox" / "handled"
inbox.mkdir(parents=True)
(inbox / "001.msg").write_text("schema=fm-task-inbox.v1\nat=now\n--\nfix the failing CI check\n")
(state / "steered.turn-ended").write_text("")
out = base / "watch.out"
p, of = start_watch(state, fakebin, out, {"FM_FAKE_TMUX_WINDOW": window})
exited = wait_exit(p)
out_txt = out.read_text() if out.exists() else ""
drain = subprocess.run(
    ["bash", str(DRAIN)],
    env={**os.environ, "FM_STATE_OVERRIDE": str(state)},
    capture_output=True,
    text=True,
)
passed = (
    exited
    and f"signal: {state}/steered.turn-ended" in out_txt
    and "\tsignal\t" in drain.stdout
    and "steered.turn-ended" in drain.stdout
)
results.append(("post-steer-stop-surfaces", passed))
(EV / "05-post-steer-surfaces.txt").write_text(
    f"passed={passed}\nexited={exited}\nwatch.out=\n{out_txt}\ndrain=\n{drain.stdout}\n"
)

# ---------- Scenario 6: display-only mark-processed via real CLI ----------
# Reconstruct home the way fm-branch-supervision tests do.
src = (ROOT / "tests/fm-branch-supervision.test.sh").read_text()
# Find home bootstrap helpers
home_helper = None
for pat in [
    r"make_home\(\)\s*\{.*?^\}",
    r"new_home\(\)\s*\{.*?^\}",
    r"setup_home\(\)\s*\{.*?^\}",
]:
    m = re.search(pat, src, re.M | re.S)
    if m:
        home_helper = m.group(0)
        break

# Extract the display-only test body roughly and run via bash using wake-helpers patterns
script = textwrap.dedent(
    f"""
set -euo pipefail
ROOT="{ROOT}"
cd "$ROOT"
. "$ROOT/tests/fixtures.sh" 2>/dev/null || true
# Prefer the test file's own home helper if present via sourcing partial
# Fallback: create a minimal home that fm-branch-outcome accepts.
home=$(mktemp -d /tmp/live-display-home-XXXXXX)
export FM_HOME="$home"
mkdir -p "$home"
# Probe append
set +e
out=$(FM_HOME="$home" "$ROOT/bin/fm-branch-outcome.sh" append --task task-a --verdict captain --summary 'display only result' --action none 2>&1)
rc=$?
set -e
echo "PROBE_APPEND rc=$rc"
echo "$out"
# If that failed, look for required layout by reading error
if [ "$rc" -ne 0 ]; then
  # Try creating state dir layouts commonly used
  mkdir -p "$home/state" "$home/.firstmate" "$home/data"
  set +e
  out=$(FM_HOME="$home" "$ROOT/bin/fm-branch-outcome.sh" append --task task-a --verdict captain --summary 'display only result' --action none 2>&1)
  rc=$?
  set -e
  echo "PROBE_APPEND2 rc=$rc"
  echo "$out"
fi
"""
)
r = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
(EV / "06-display-probe.txt").write_text(
    f"stdout:\n{r.stdout}\nstderr:\n{r.stderr}\nhome_helper=\n{home_helper or ''}\n"
)

# Run the actual display-only behavioral test from the suite as a live product CLI exercise
# by re-executing just that one test function after sourcing helpers from the test file.
focused = textwrap.dedent(
    f"""
set -euo pipefail
cd "{ROOT}"
# Extract defs up to the bulk run of branch-supervision is hard; instead invoke the full
# single-test by patching: run the whole test file is already done. Drive CLI directly
# mirroring the assertions.
. tests/fixtures.sh
home=$(fm_test_home display-only-live 2>/dev/null || mktemp -d /tmp/dol-XXXXXX)
export FM_HOME="$home"
OUTCOME=bin/fm-branch-outcome.sh
# Discover home layout from a successful append by reading tests/fixtures or binary
# Use python-less pure bash following the test at line ~840
set +e
# Source the test's make_home if we can find it in fixtures
type fm_test_home >/dev/null 2>&1
echo "fm_test_home=$?"
ls "$home" | head
# Read how branch-supervision creates homes - print first 120 lines of fixtures
"""
)
r2 = subprocess.run(["bash", "-c", focused], capture_output=True, text=True)
(EV / "06b-fixtures-probe.txt").write_text(r2.stdout + "\n---\n" + r2.stderr)

print("RESULTS")
for name, ok in results:
    print(f"SCENARIO|{name}|{'PASS' if ok else 'FAIL'}")
all_ok = all(ok for _, ok in results)
print(f"ALL_WATCH_OK={all_ok}")
raise SystemExit(0 if all_ok else 1)
