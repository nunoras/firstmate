#!/usr/bin/env bash
# Live driver: real Pi TUI in tmux, faux reasoning model, Calm on with Pi hide-thinking EXPANDED.
# usage: drive-calm-thinking.sh <source-tree> <label> [full]
set -u
SRC=$1
LABEL=$2
MODE=${3:-full}
EVID=/home/nunoras/.no-mistakes/evidence/01M2EKZZA2DXP0HN5TNS997TVM
OUT="$EVID/$LABEL"
WORK=$(mktemp -d /tmp/calm-live-$LABEL-XXXX)
SOCK="calm-live-$LABEL-$$"
SESS=calmlive
PASS=0
FAIL=0
mkdir -p "$OUT"
LOG="$OUT/transcript.log"
: >"$LOG"
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
check() {
  local desc=$1; shift
  if "$@"; then say "PASS: $desc"; PASS=$((PASS + 1)); else say "FAIL: $desc"; FAIL=$((FAIL + 1)); fi
}
has() { grep -Fq "$2" "$1"; }
lacks() { ! grep -Fq "$2" "$1"; }

project="$WORK/project"; home="$WORK/home"; config="$WORK/config"; sessions="$WORK/sessions"
mkdir -p "$project/.pi/extensions" "$home/config" "$config" "$sessions"
git -C "$project" init -q && git -C "$project" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cp "$SRC/.pi/extensions/fm-calm.ts" "$project/.pi/extensions/"
cp -r "$SRC/.pi/extensions/lib" "$project/.pi/extensions/lib"
printf 'on\n' >"$home/config/calm"
printf '%s\n' '{"hideThinkingBlock":false,"terminal":{"clearOnShrink":false}}' >"$config/settings.json"
printf 'probe contents\n' >"$project/probe.txt"
STREAM_THINKING=$(for i in $(seq 1 30); do printf 'LIVE_STREAM_REASONING step %s weighing options. ' "$i"; done)
CONTROL_THINKING=$(for i in $(seq 1 30); do printf 'LIVE_CONTROL_REASONING step %s weighing options. ' "$i"; done)
cat >"$project/live-provider.ts" <<TS
import { createFauxCore, fauxAssistantMessage, fauxThinking, fauxText, fauxToolCall } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
export default function (pi: ExtensionAPI): void {
  const faux = createFauxCore({
    api: "calm-live-api",
    provider: "calm-live",
    models: [{ id: "reasoner", name: "Calm live reasoner", reasoning: true, input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 8192, maxTokens: 512 }],
    tokensPerSecond: 40,
    tokenSize: { min: 1, max: 1 },
  });
  faux.setResponses([
    fauxAssistantMessage([
      fauxThinking("LIVE_REASONING_ALPHA the captain asked me to look at the probe file first."),
      fauxToolCall("read", { path: "probe.txt" }, { id: "live_read_one" }),
    ], { stopReason: "toolUse" }),
    fauxAssistantMessage([
      fauxThinking("LIVE_REASONING_BETA the probe says what I expected, so I can answer."),
      fauxText("LIVE_FINAL_ANSWER the probe file is fine."),
    ]),
    fauxAssistantMessage([
      fauxThinking("$STREAM_THINKING"),
      fauxText("LIVE_STREAM_DONE second answer."),
    ]),
    fauxAssistantMessage([
      fauxThinking("$CONTROL_THINKING"),
      fauxText("LIVE_CONTROL_DONE third answer."),
    ]),
  ]);
  pi.registerProvider("calm-live", { baseUrl: "http://127.0.0.1/unused", apiKey: "test-only",
    api: faux.api, models: faux.models, streamSimple: faux.streamSimple });
  pi.registerCommand("calm-live", {
    description: "Select the Calm live reasoner.",
    handler: async (_args, ctx) => {
      const model = ctx.modelRegistry.find("calm-live", "reasoner");
      if (!model || !(await pi.setModel(model))) throw new Error("model unavailable");
    },
  });
}
TS

tmux -L "$SOCK" new-session -d -s "$SESS" -x 110 -y 48 \
  "cd '$project' && env FM_HOME='$home' PI_CODING_AGENT_DIR='$config' PI_OFFLINE=1 pi --approve --no-context-files --no-prompt-templates --no-extensions -e ./.pi/extensions/fm-calm.ts -e ./live-provider.ts --session-dir '$sessions'; printf '\nPI_EXIT=%s\n' \$?; sleep 30"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$WORK"' EXIT

cap() { tmux -L "$SOCK" capture-pane -p -t "$SESS" -S -300 >"$1"; }
capansi() { tmux -L "$SOCK" capture-pane -p -e -t "$SESS" >"$1"; }
waitfor() {
  local file=$1 text=$2 n=0
  while [ "$n" -lt 300 ]; do cap "$file"; grep -Fq "$text" "$file" && return 0; sleep 0.05; n=$((n + 1)); done
  return 1
}
waitgone() {
  local file=$1 text=$2 n=0
  while [ "$n" -lt 300 ]; do cap "$file"; grep -Fq "$text" "$file" || return 0; sleep 0.05; n=$((n + 1)); done
  return 1
}
idle() {
  local file=$1 n=0
  while [ "$n" -lt 200 ]; do cap "$file"; tail -12 "$file" | grep -Eq "Working(\\.\\.\\.)?([[:space:]]|─|$)" || return 0; sleep 0.05; n=$((n + 1)); done
}
send() { tmux -L "$SOCK" send-keys -t "$SESS" -l "$1"; tmux -L "$SOCK" send-keys -t "$SESS" Enter; }
snap() {
  local name=$1 title=$2
  cap "$OUT/$name.txt"
  capansi "$OUT/$name.ansi"
  node "$EVID/ansi2html.mjs" "$OUT/$name.ansi" "$OUT/$name.html" "$title"
  google-chrome --headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage --hide-scrollbars \
    --user-data-dir="$WORK/chrome-$name" --window-size=900,760 --screenshot="$OUT/$name.png" "file://$OUT/$name.html" >/dev/null 2>&1
  rm -f "$OUT/$name.ansi"
}

say "== $LABEL: source $SRC; pi $(pi --version)"
say "settings.json at start: $(cat "$config/settings.json")"
waitfor "$WORK/s.txt" "live-provider.ts" || { say "FAIL: Pi did not start"; exit 1; }
send "/calm-live"; sleep 0.3
send "Please check the probe file"
waitfor "$WORK/s.txt" "LIVE_FINAL_ANSWER" || say "FAIL: first turn never finished"
idle "$WORK/s.txt"; sleep 0.3
snap 01-calm-on-expanded "$LABEL: Calm ON, Pi hide-thinking EXPANDED (hideThinkingBlock=false), after first turn"
check "Calm on + expanded: first-turn reasoning ALPHA not shown" lacks "$OUT/01-calm-on-expanded.txt" "LIVE_REASONING_ALPHA"
check "Calm on + expanded: final reasoning BETA not shown" lacks "$OUT/01-calm-on-expanded.txt" "LIVE_REASONING_BETA"
check "Calm on + expanded: final answer visible" has "$OUT/01-calm-on-expanded.txt" "LIVE_FINAL_ANSWER"
check "Calm on + expanded: no 'Thinking...' label" lacks "$OUT/01-calm-on-expanded.txt" "Thinking..."
[ "$MODE" = full ] || { say "== $LABEL summary: $PASS passed, $FAIL failed"; exit 0; }

stream_probe() {
  local prompt=$1 reasoning=$2 done_text=$3 shot=$4 title=$5
  STREAM_FRAMES=0; STREAM_LEAKS=0
  send "$prompt"
  local n shot_taken=0
  for n in $(seq 1 600); do
    cap "$WORK/f.txt"
    grep -Fq "$done_text" "$WORK/f.txt" && break
    grep -Fq "$prompt" "$WORK/f.txt" || { sleep 0.05; continue; }
    STREAM_FRAMES=$((STREAM_FRAMES + 1))
    grep -Fq "$reasoning" "$WORK/f.txt" && STREAM_LEAKS=$((STREAM_LEAKS + 1))
    if [ "$shot_taken" -eq 0 ] && [ "$STREAM_FRAMES" -eq 40 ]; then snap "$shot" "$title"; shot_taken=1; fi
    sleep 0.05
  done
  say "stream probe '$prompt': frames before reply landed=$STREAM_FRAMES, frames showing streamed reasoning=$STREAM_LEAKS"
}
stream_probe "Think hard about something else" "LIVE_STREAM_REASONING" "LIVE_STREAM_DONE" 02-calm-on-mid-stream \
  "$LABEL: Calm ON, hide-thinking EXPANDED, captured WHILE reasoning streams (reply not landed yet)"
check "Calm on + expanded: a streaming window of >=40 frames was observed" test "$STREAM_FRAMES" -ge 40
check "Calm on + expanded: streamed reasoning never appeared mid-stream" test "$STREAM_LEAKS" -eq 0
check "Calm on + expanded: mid-stream snapshot exists and has no reasoning and no reply yet" \
  bash -c '[ -s "$1" ] && ! grep -Fq LIVE_STREAM_REASONING "$1" && ! grep -Fq LIVE_STREAM_DONE "$1"' _ "$OUT/02-calm-on-mid-stream.txt"
waitfor "$WORK/s.txt" "LIVE_STREAM_DONE"; idle "$WORK/s.txt"; sleep 0.3
cap "$WORK/s.txt"
check "Calm on + expanded: streamed reasoning absent after it settled" lacks "$WORK/s.txt" "LIVE_STREAM_REASONING"

send "/calm"
waitfor "$WORK/s.txt" "LIVE_REASONING_ALPHA"; sleep 0.3
snap 03-calm-off-expanded "$LABEL: Calm OFF, Pi hide-thinking EXPANDED - reasoning restored"
check "Calm off + expanded: first-turn reasoning ALPHA visible again" has "$OUT/03-calm-off-expanded.txt" "LIVE_REASONING_ALPHA"
check "Calm off + expanded: final reasoning BETA visible again" has "$OUT/03-calm-off-expanded.txt" "LIVE_REASONING_BETA"
check "Calm off + expanded: streamed reasoning visible again" has "$OUT/03-calm-off-expanded.txt" "LIVE_STREAM_REASONING"
check "Calm off: tool row for probe.txt restored" has "$OUT/03-calm-off-expanded.txt" "probe.txt"

tmux -L "$SOCK" send-keys -t "$SESS" C-t
waitfor "$WORK/s.txt" "Thinking blocks: hidden"; waitgone "$WORK/s.txt" "LIVE_REASONING_ALPHA"; sleep 0.2
snap 04-calm-off-collapsed "$LABEL: Calm OFF, Ctrl+T collapsed - Pi's Thinking... label is back"
check "Calm off + Ctrl+T collapse: Pi status confirms hidden" has "$OUT/04-calm-off-collapsed.txt" "Thinking blocks: hidden"
check "Calm off + Ctrl+T collapse: 'Thinking...' label shown" has "$OUT/04-calm-off-collapsed.txt" "Thinking..."
check "Calm off + Ctrl+T collapse: reasoning text hidden by Pi" lacks "$OUT/04-calm-off-collapsed.txt" "LIVE_REASONING_ALPHA"
tmux -L "$SOCK" send-keys -t "$SESS" C-t
waitfor "$WORK/s.txt" "Thinking blocks: visible"; waitfor "$WORK/s.txt" "LIVE_REASONING_ALPHA"
check "Calm off + Ctrl+T expand: reasoning visible again" has "$WORK/s.txt" "LIVE_REASONING_ALPHA"

stream_probe "Control run with Calm off" "LIVE_CONTROL_REASONING" "LIVE_CONTROL_DONE" 04b-calm-off-mid-stream-control \
  "$LABEL: CONTROL - Calm OFF, hide-thinking EXPANDED, captured WHILE reasoning streams"
check "control (Calm off): streamed reasoning IS visible mid-stream, so the probe can detect leaks" test "$STREAM_LEAKS" -gt 0
waitfor "$WORK/s.txt" "LIVE_CONTROL_DONE"; idle "$WORK/s.txt"; sleep 0.3

send "/calm"
waitgone "$WORK/s.txt" "LIVE_REASONING_ALPHA"; sleep 0.3
snap 05-calm-on-again-expanded "$LABEL: Calm back ON, Pi hide-thinking still EXPANDED"
check "Calm re-enabled + expanded: ALPHA hidden" lacks "$OUT/05-calm-on-again-expanded.txt" "LIVE_REASONING_ALPHA"
check "Calm re-enabled + expanded: BETA hidden" lacks "$OUT/05-calm-on-again-expanded.txt" "LIVE_REASONING_BETA"
check "Calm re-enabled + expanded: streamed reasoning hidden" lacks "$OUT/05-calm-on-again-expanded.txt" "LIVE_STREAM_REASONING"
check "Calm re-enabled + expanded: Calm-off control reasoning hidden" lacks "$OUT/05-calm-on-again-expanded.txt" "LIVE_CONTROL_REASONING"
check "Calm re-enabled + expanded: answers still visible" has "$OUT/05-calm-on-again-expanded.txt" "LIVE_STREAM_DONE"
check "Calm re-enabled + expanded: no 'Thinking...' label" lacks "$OUT/05-calm-on-again-expanded.txt" "Thinking..."
say "Pi settings.json after Calm toggles: $(cat "$config/settings.json")"
check "Pi's own hideThinkingBlock preference left at false by Calm" \
  node -e 'process.exit(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).hideThinkingBlock===false?0:1)' "$config/settings.json"

send "/export $WORK/export.html"
waitfor "$WORK/s.txt" "Session exported to" || say "FAIL: export status never shown"
cp "$WORK/export.html" "$OUT/export.html"
google-chrome --headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage --user-data-dir="$WORK/chrome-dom" \
  --virtual-time-budget=3000 --dump-dom "file://$OUT/export.html" >"$WORK/export-dom.html" 2>/dev/null
node -e '
const dom = require("fs").readFileSync(process.argv[1], "utf8");
const blocks = [...dom.matchAll(/<div class="thinking-text">([\s\S]*?)<\/div>/g)].map((m) => m[1]).filter((b) => !b.includes("${"));
console.log(JSON.stringify({ thinkingBlocks: blocks.length, texts: blocks.map((b) => b.slice(0, 70)) }, null, 2));
' "$WORK/export-dom.html" | tee "$OUT/export-thinking-blocks.json" | tee -a "$LOG"
check "export (Calm on) DOM has ALPHA reasoning" grep -Fq "LIVE_REASONING_ALPHA" "$OUT/export-thinking-blocks.json"
check "export (Calm on) DOM has BETA reasoning" grep -Fq "LIVE_REASONING_BETA" "$OUT/export-thinking-blocks.json"
check "export (Calm on) DOM has streamed reasoning" grep -Fq "LIVE_STREAM_REASONING" "$OUT/export-thinking-blocks.json"
check "export (Calm on) DOM has Calm-off control reasoning" grep -Fq "LIVE_CONTROL_REASONING" "$OUT/export-thinking-blocks.json"
google-chrome --headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage --hide-scrollbars --user-data-dir="$WORK/chrome-shot" \
  --virtual-time-budget=3000 --window-size=1100,1400 --screenshot="$OUT/06-export-with-calm-on.png" "file://$OUT/export.html" >/dev/null 2>&1

send "/quit"
say "== $LABEL summary: $PASS passed, $FAIL failed"
