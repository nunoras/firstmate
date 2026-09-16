# fm-calm-builtin-conflict live validation

Product under test: Firstmate Calm Pi extension (`.pi/extensions/fm-calm.ts` +
`lib/fm-calm-tool-row-layout.ts`) against installed Pi 0.85.1.

Driver: `tests/fm-calm-pi-extension.test.sh` (focused product suite; uses real Pi
packages, ExtensionRunner/loadExtensionsCached, ToolExecutionComponent, and a
live `pi` interactive session under tmux).

## Scenarios

1. **Calm-on-at-load registers zero tools**
   - `test_builtin_gate_load_time`
   - Calm with `config/calm=on` and `off` both leave `pi.registerTool` empty.
   - Built-in row presentation is supplied via `InteractiveMode.getRegisteredToolDefinition`.
   - Result: PASS

2. **Later extension keeps its bash override (the reproduced conflict)**
   - `test_calm_leaves_foreign_builtin_override_intact`
   - Pi loads Calm first, then a second extension that `registerTool({ name: "bash", ... })`.
   - Foreign bash survives, executes `FOREIGN_BUILTIN_EXECUTED`, Calm claims no tools.
   - Calm still hides/restores rows through the row-definition seam on /calm toggle.
   - Result: PASS

3. **Calm presentation still works without owning built-ins**
   - `test_rendering_and_session_lifecycle`
   - Hides seven built-in rows while on, restores stock when off, preserves execute/export.
   - Result: PASS

4. **Live interactive Pi TUI: restored built-in rows hide with Calm**
   - `test_interactive_terminal_e2e`
   - Real `pi` in tmux; `/calm` hides restored bash/grep/find output (`CALM_E2E_OUTPUT`,
     `CALM_EXPORT_GREP`, `CALM_EXPORT_FIND`) rather than leaving the old non-retroactive bound.
   - Result: PASS

Full suite: 13/13 ok lines (see `fm-calm-pi-extension.test.log`).
