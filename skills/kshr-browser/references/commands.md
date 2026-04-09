# Command Reference (kshr Browser)

This maps common `agent-browser` usage to `kshr browser` usage.

## Direct Equivalents

- `agent-browser open <url>` -> `kshr browser open <url>`
- `agent-browser goto|navigate <url>` -> `kshr browser <surface> goto|navigate <url>`
- `agent-browser snapshot -i` -> `kshr browser <surface> snapshot --interactive`
- `agent-browser click <ref>` -> `kshr browser <surface> click <ref>`
- `agent-browser fill <ref> <text>` -> `kshr browser <surface> fill <ref> <text>`
- `agent-browser type <ref> <text>` -> `kshr browser <surface> type <ref> <text>`
- `agent-browser select <ref> <value>` -> `kshr browser <surface> select <ref> <value>`
- `agent-browser get text <ref>` -> `kshr browser <surface> get text <ref-or-selector>`
- `agent-browser get url` -> `kshr browser <surface> get url`
- `agent-browser get title` -> `kshr browser <surface> get title`

## Core Command Groups

### Navigation

```bash
kshr browser open <url>                        # opens in caller's workspace (uses KSHR_WORKSPACE_ID)
kshr browser open <url> --workspace <id|ref>   # opens in a specific workspace
kshr browser <surface> goto <url>
kshr browser <surface> back|forward|reload
kshr browser <surface> get url|title
```

> **Workspace context:** `browser open` targets the workspace of the terminal where the command is run (via `KSHR_WORKSPACE_ID`), even if a different workspace is currently focused. Use `--workspace` to override.

### Snapshot and Inspection

```bash
kshr browser <surface> snapshot --interactive
kshr browser <surface> snapshot --interactive --compact --max-depth 3
kshr browser <surface> get text body
kshr browser <surface> get html body
kshr browser <surface> get value "#email"
kshr browser <surface> get attr "#email" --attr placeholder
kshr browser <surface> get count ".row"
kshr browser <surface> get box "#submit"
kshr browser <surface> get styles "#submit" --property color
kshr browser <surface> eval '<js>'
```

### Interaction

```bash
kshr browser <surface> click|dblclick|hover|focus <selector-or-ref>
kshr browser <surface> fill <selector-or-ref> [text]   # empty text clears
kshr browser <surface> type <selector-or-ref> <text>
kshr browser <surface> press|keydown|keyup <key>
kshr browser <surface> select <selector-or-ref> <value>
kshr browser <surface> check|uncheck <selector-or-ref>
kshr browser <surface> scroll [--selector <css>] [--dx <n>] [--dy <n>]
```

### Wait

```bash
kshr browser <surface> wait --selector "#ready" --timeout-ms 10000
kshr browser <surface> wait --text "Done" --timeout-ms 10000
kshr browser <surface> wait --url-contains "/dashboard" --timeout-ms 10000
kshr browser <surface> wait --load-state complete --timeout-ms 15000
kshr browser <surface> wait --function "document.readyState === 'complete'" --timeout-ms 10000
```

### Session/State

```bash
kshr browser <surface> cookies get|set|clear ...
kshr browser <surface> storage local|session get|set|clear ...
kshr browser <surface> tab list|new|switch|close ...
kshr browser <surface> state save|load <path>
```

### Diagnostics

```bash
kshr browser <surface> console list|clear
kshr browser <surface> errors list|clear
kshr browser <surface> highlight <selector>
kshr browser <surface> screenshot
kshr browser <surface> download wait --timeout-ms 10000
```

## Agent Reliability Tips

- Use `--snapshot-after` on mutating actions to return a fresh post-action snapshot.
- Re-snapshot after navigation, modal open/close, or major DOM changes.
- Prefer short handles in outputs by default (`surface:N`, `pane:N`, `workspace:N`, `window:N`).
- Use `--id-format both` only when a UUID must be logged/exported.

## Known WKWebView Gaps (`not_supported`)

- `browser.viewport.set`
- `browser.geolocation.set`
- `browser.offline.set`
- `browser.trace.start|stop`
- `browser.network.route|unroute|requests`
- `browser.screencast.start|stop`
- `browser.input_mouse|input_keyboard|input_touch`

See also:
- [snapshot-refs.md](snapshot-refs.md)
- [authentication.md](authentication.md)
- [session-management.md](session-management.md)
