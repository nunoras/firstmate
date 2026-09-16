# fm-pi-footer-stale-churn local test evidence (this run)

## Live drive (authoritative for the captain-required scenarios)
Private tmux socket, private state under `/tmp/fm-pi-footer-live.*`, fleet watcher untouched.
Real pi 0.85.1 with `--provider zai --model glm-5.3-flash` so the statusline quota countdown ticks; pi-signed is the same TUI under a `pi-signed` harness label (no separate binary on this host). Real `bin/fm-watch.sh`.

Results (`live-footer-drive.out`):
- ok - [pi] finished live worker surfaces terminal stale exactly once on first sight
- ok - [pi] footer-only quota countdown repaint does not re-alarm a finished live worker (live tick at 49s; whole capture moved, strip stable: `1d 19h 20m` → `1d 19h 19m`)
- ok - [pi] transcript/content change above the composer produces exactly one new wake
- ok - [pi-signed] finished live worker surfaces terminal stale exactly once on first sight
- ok - [pi-signed] footer-only quota countdown repaint does not re-alarm a finished live worker (live tick at 32s: `1d 19h 19m` → `1d 19h 18m`)
- ok - [pi-signed] transcript/content change above the composer produces exactly one new wake
- ok - strip refuses live screen with no separator; watcher falls back to whole capture
- ok - strip refuses live screen with nothing above the separator
- ALL_LIVE_OK

Captures:
- `live-pi-idle-capture.txt` / `live-pi-signed-idle-capture.txt`
- `live-footer-tick-before-pi.txt` / `live-footer-tick-after-pi.txt`
- `live-footer-tick-before-pi-signed.txt` / `live-footer-tick-after-pi-signed.txt`
- `live-pi-content-change.txt` / `live-pi-signed-content-change.txt`
- `live-nosep-capture.txt` / `live-seponly-capture.txt`

## Hermetic regression
- `tests/fm-composer-lib.test.sh`: pass (includes `fm_composer_pi_strip_footer` bounds)
- focused `test_pi_footer_repaint_does_not_restale_a_finished_worker` (pi + pi-signed via real `bin/fm-watch.sh`): `ok - pi footer churn: surfaced once, silent through a footer repaint, still alarming on real content`
