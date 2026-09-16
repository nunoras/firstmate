#!/usr/bin/env bash
set -u
ROOT=/home/nunoras/.no-mistakes/worktrees/53c53b70f8b7/01M2KKX2SM77NW3MHQF6NG4ZS6
EV=/home/nunoras/.no-mistakes/evidence/01M2KKX2SM77NW3MHQF6NG4ZS6/manual-live
mkdir -p "$EV"
cd "$ROOT"

# Source triage helpers by creating a thin wrapper inside tests/ so BASH_SOURCE works,
# then removing it after.
wrap=tests/.live-drive-wrap.sh
awk '
  /^test_status_span_actionable_classifier$/ { exit }
  { print }
' tests/fm-watch-triage.test.sh > "$wrap"
# Append only the scenario driver, no bulk tests
cat >> "$wrap" <<'INNER'

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; return 1; }
report() { echo "SCENARIO|$1|$2"; }

# 1 covered turn-end absorb
{
  dir=$(make_case live-covered-absorb); state="$dir/state"; fakebin="$dir/fakebin"
  out="$dir/watch.out"
  window="test:live-covered"
  printf 'done: PR https://example.test/pr/9 checks green\n' > "$state/covered.status"
  printf 'window=%s\nkind=ship\nharness=pi\n' "$window" > "$state/covered.meta"
  write_covered_outcome_index "$state" covered 7
  prime_status_seen "$state" "$state/covered.status"
  : > "$state/covered.turn-ended"
  key=$(printf '%s' "$window" | tr ':/.' '___')
  export FM_FAKE_CREW_STATE='state: unknown · source: none · no current-state source available'
  PATH="$fakebin:$PATH" FM_FAKE_TMUX_WINDOW="$window" \
    FM_STATE_OVERRIDE="$state" FM_CREW_STATE_BIN="$fakebin/fm-crew-state.sh" \
    FM_POLL=3 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$WATCH" > "$out" &
  pid=$!
  if wait_for_absorbed "$state" "$pid" "absorbed benign signal (outcome-covered)" \
    && [ ! -s "$out" ] && [ ! -s "$state/.wake-queue" ] \
    && [ -s "$state/.turnend-covered-since-$key" ]; then
    report covered-turnend-absorbed PASS
  else
    report covered-turnend-absorbed FAIL
  fi
  {
    echo "watch.out:"; cat "$out" 2>/dev/null || true
    echo "queue:"; cat "$state/.wake-queue" 2>/dev/null || echo empty
    echo "marker:"; cat "$state/.turnend-covered-since-$key" 2>/dev/null || true
    echo "index:"; cat "$state/.covered.branch-outcome-index"
    echo "triage:"; grep -F "outcome-covered" "$state/.watch-triage.log" 2>/dev/null || true
  } > "$EV/01-covered-turnend-absorb.txt"
  reap "$pid" 2>/dev/null || true
  unset FM_FAKE_CREW_STATE
}

# 2 first sight decision
{
  dir=$(make_case live-first-sight); state="$dir/state"; fakebin="$dir/fakebin"
  out="$dir/watch.out"; drain_out="$dir/drain.out"
  window="test:live-first"
  : > "$state/first.status"
  write_covered_outcome_index "$state" first 9
  printf 'needs-decision: choose deploy target\n' > "$state/first.status"
  printf 'window=%s\nkind=ship\nharness=pi\n' "$window" > "$state/first.meta"
  : > "$state/first.turn-ended"
  export FM_FAKE_CREW_STATE='state: unknown · source: none · no current-state source available'
  PATH="$fakebin:$PATH" FM_FAKE_TMUX_WINDOW="$window" \
    FM_STATE_OVERRIDE="$state" FM_CREW_STATE_BIN="$fakebin/fm-crew-state.sh" \
    FM_POLL=3 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$WATCH" > "$out" &
  pid=$!
  if wait_for_exit "$pid" 100 \
    && grep -E "signal:" "$out" >/dev/null \
    && FM_STATE_OVERRIDE="$state" "$DRAIN" > "$drain_out" 2>/dev/null \
    && grep "$(printf '\tsignal\t')" "$drain_out" >/dev/null; then
    report first-sight-decision-surfaces PASS
  else
    report first-sight-decision-surfaces FAIL
  fi
  {
    echo "watch.out:"; cat "$out"
    echo "drain:"; cat "$drain_out"
    echo "status:"; cat "$state/first.status"
  } > "$EV/02-first-sight-decision.txt"
  unset FM_FAKE_CREW_STATE
}

# 3 terminal rehash absorb
{
  dir=$(make_case live-term); state="$dir/state"; fakebin="$dir/fakebin"
  out="$dir/watch.out"; capture_file="$dir/pane.txt"
  window="test:live-term"
  printf 'finished, awaiting teardown' > "$capture_file"
  printf 'window=%s\nkind=ship\n' "$window" > "$state/term.meta"
  printf 'done: PR https://example.test/pr/3\n' > "$state/term.status"
  write_covered_outcome_index "$state" term 12
  sig=$(seen_sig "$state/term.status"); printf '%s' "$sig" > "$state/.seen-term_status"
  key=$(printf '%s' "$window" | tr ':/.' '___')
  pane_hash=$(hash_text "finished, awaiting teardown")
  printf '%s' "$pane_hash" > "$state/.hash-$key"
  printf '1\n' > "$state/.count-$key"
  PATH="$fakebin:$PATH" FM_FAKE_TMUX_WINDOW="$window" FM_FAKE_TMUX_CAPTURE="$capture_file" \
    FM_STATE_OVERRIDE="$state" FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$WATCH" > "$out" &
  pid=$!
  if wait_for_absorbed "$state" "$pid" "absorbed stale (outcome-covered):" \
    && [ ! -s "$out" ] && [ ! -s "$state/.wake-queue" ] \
    && [ ! -e "$state/.paused-resurfaced-$key" ]; then
    report terminal-rehash-absorbed PASS
  else
    report terminal-rehash-absorbed FAIL
  fi
  {
    echo "watch.out:"; cat "$out" 2>/dev/null || true
    echo "shared:"; ls "$state/.paused-resurfaced-$key" 2>&1 || echo absent
    echo "triage:"; grep -F "outcome-covered" "$state/.watch-triage.log" 2>/dev/null || true
  } > "$EV/03-terminal-rehash-absorb.txt"
  reap "$pid" 2>/dev/null || true
}

# 4 static silent
{
  dir=$(make_case live-static); state="$dir/state"; fakebin="$dir/fakebin"
  out="$dir/watch.out"; capture_file="$dir/pane.txt"
  window="test:live-static"
  key=$(printf '%s' "$window" | tr ':/.' '___')
  setup_covered_terminal_task "$state" static "$window"
  prime_stale_pane "$state" "$key" "$capture_file" 'finished, awaiting teardown'
  ok=1
  covered_stale_round "$state" "$fakebin" "$out" "$capture_file" "$window" absorb "absorbed stale (outcome-covered): $window" || ok=0
  covered_stale_round "$state" "$fakebin" "$out" "$capture_file" "$window" poll || ok=0
  [ ! -s "$out" ] || ok=0
  [ ! -s "$state/.wake-queue" ] || ok=0
  prime_stale_pane "$state" "$key" "$capture_file" 'finished, awaiting teardown (repaint)'
  covered_stale_round "$state" "$fakebin" "$out" "$capture_file" "$window" absorb "absorbed stale (outcome-covered): $window" || ok=0
  covered_stale_round "$state" "$fakebin" "$out" "$capture_file" "$window" poll || ok=0
  [ ! -s "$out" ] || ok=0
  if [ "$ok" -eq 1 ]; then report static-covered-pane-stays-silent PASS
  else report static-covered-pane-stays-silent FAIL; fi
  {
    echo "ok=$ok"
    echo "watch.out:"; cat "$out" 2>/dev/null || true
    echo "queue:"; cat "$state/.wake-queue" 2>/dev/null || echo empty
    echo "triage:"; cat "$state/.watch-triage.log" 2>/dev/null | tail -20
  } > "$EV/04-static-pane-silent.txt"
}

# 5 post-steer surfaces
{
  dir=$(make_case live-steer); state="$dir/state"; fakebin="$dir/fakebin"
  out="$dir/watch.out"; drain_out="$dir/drain.out"
  window="test:live-steer"
  printf 'done: PR https://example.test/pr/9 checks green\n' > "$state/steered.status"
  printf 'window=%s\nkind=ship\nharness=pi\n' "$window" > "$state/steered.meta"
  write_covered_outcome_index "$state" steered 7
  backdate_path "$state/.steered.branch-outcome-index"
  prime_status_seen "$state" "$state/steered.status"
  record_acked_steer "$state" steered
  : > "$state/steered.turn-ended"
  export FM_FAKE_CREW_STATE='state: unknown · source: none · no current-state source available'
  PATH="$fakebin:$PATH" FM_FAKE_TMUX_WINDOW="$window" \
    FM_STATE_OVERRIDE="$state" FM_CREW_STATE_BIN="$fakebin/fm-crew-state.sh" \
    FM_POLL=3 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$WATCH" > "$out" &
  pid=$!
  if wait_for_exit "$pid" 100 \
    && grep -F "signal: $state/steered.turn-ended" "$out" >/dev/null \
    && FM_STATE_OVERRIDE="$state" "$DRAIN" > "$drain_out" 2>/dev/null \
    && grep "$(printf '\tsignal\t')" "$drain_out" | grep -F "$state/steered.turn-ended" >/dev/null; then
    report post-steer-stop-surfaces PASS
  else
    report post-steer-stop-surfaces FAIL
  fi
  {
    echo "watch.out:"; cat "$out"
    echo "drain:"; cat "$drain_out"
  } > "$EV/05-post-steer-surfaces.txt"
  unset FM_FAKE_CREW_STATE
}

# 6 busy then stop surfaces
{
  dir=$(make_case live-busy); state="$dir/state"; fakebin="$dir/fakebin"
  out="$dir/watch.out"; capture_file="$dir/pane.txt"
  window="test:live-busy"
  key=$(printf '%s' "$window" | tr ':/.' '___')
  shared="$state/.paused-resurfaced-$key"
  setup_covered_terminal_task "$state" rebusy "$window"
  prime_stale_pane "$state" "$key" "$capture_file" 'finished, awaiting teardown'
  ok=1
  covered_stale_round "$state" "$fakebin" "$out" "$capture_file" "$window" absorb "absorbed stale (outcome-covered): $window" || ok=0
  [ ! -e "$shared" ] || ok=0
  printf 'working on the follow-up\nCtrl+c:cancel' > "$capture_file"
  covered_stale_round "$state" "$fakebin" "$out" "$capture_file" "$window" poll || ok=0
  case "$(cat "$state/.outcome-busy-$key" 2>/dev/null)" in
    outcome-covered:14:*) ;;
    *) ok=0 ;;
  esac
  [ ! -e "$shared" ] || ok=0
  prime_stale_pane "$state" "$key" "$capture_file" 'Should I also bump the version?'
  covered_stale_round "$state" "$fakebin" "$out" "$capture_file" "$window" exit || ok=0
  grep -Fx "stale: $window" "$out" >/dev/null || ok=0
  if [ "$ok" -eq 1 ]; then report busy-then-stop-surfaces PASS
  else report busy-then-stop-surfaces FAIL; fi
  {
    echo "ok=$ok"
    echo "busy-marker:"; cat "$state/.outcome-busy-$key" 2>/dev/null || true
    echo "watch.out:"; cat "$out"
    echo "shared exists?"; ls "$shared" 2>&1 || echo absent
  } > "$EV/06-busy-then-stop.txt"
}

# 7 display-only mark-processed CLI
{
  home="$EV/display-home"
  mkdir -p "$home/state"
  store="$home/state/branch-outcomes.jsonl"
  marker="$home/state/.branch-outcomes-processed"
  OUTCOME="$ROOT/bin/fm-branch-outcome.sh"
  ok=1
  FM_HOME="$home" "$OUTCOME" append \
    --task task-a --verdict captain --summary 'display only result' --action none >/dev/null || ok=0
  FM_HOME="$home" "$OUTCOME" append \
    --task task-b --verdict captain --summary 'needs main' --action main >/dev/null || ok=0
  FM_HOME="$home" "$OUTCOME" mark-read --through 1 || ok=0
  FM_HOME="$home" "$OUTCOME" mark-processed --through 1 --display-only || ok=0
  [ "$(cat "$marker")" = 1 ] || ok=0
  FM_HOME="$home" "$OUTCOME" mark-read --through 2 || ok=0
  if FM_HOME="$home" "$OUTCOME" mark-processed --through 2 --display-only 2>"$EV/display-refuse.err"; then
    ok=0
  fi
  grep -q 'action:main' "$EV/display-refuse.err" || ok=0
  [ "$(cat "$marker")" = 1 ] || ok=0
  FM_HOME="$home" "$OUTCOME" mark-processed --through 2 || ok=0
  [ "$(cat "$marker")" = 2 ] || ok=0
  if [ "$ok" -eq 1 ]; then report display-only-no-main-turn PASS
  else report display-only-no-main-turn FAIL; fi
  {
    echo "ok=$ok"
    echo "store:"; cat "$store"
    echo "marker:"; cat "$marker"
    echo "refuse:"; cat "$EV/display-refuse.err" 2>/dev/null || true
  } > "$EV/07-display-only.txt"
}

echo LIVE_DRIVE_DONE
INNER

bash "$wrap" 2>&1 | tee "$EV/../manual-live/driver.log"
rc=${PIPESTATUS[0]}
rm -f "$wrap"
exit $rc
