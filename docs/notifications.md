# Notifications

kshr provides a notification panel for AI agents like Claude Code, Codex, and OpenCode. Notifications appear in a dedicated panel and trigger macOS system notifications.

## Quick Start

```bash
# Send a notification (if kshr is available)
command -v kshr &>/dev/null && kshr notify --title "Done" --body "Task complete"

# With fallback to macOS notifications
command -v kshr &>/dev/null && kshr notify --title "Done" --body "Task complete" || osascript -e 'display notification "Task complete" with title "Done"'
```

## Detection

Check if `kshr` CLI is available before using it:

```bash
# Shell
if command -v kshr &>/dev/null; then
    kshr notify --title "Hello"
fi

# One-liner with fallback
command -v kshr &>/dev/null && kshr notify --title "Hello" || osascript -e 'display notification "" with title "Hello"'
```

```python
# Python
import shutil
import subprocess

def notify(title: str, body: str = ""):
    if shutil.which("kshr"):
        subprocess.run(["kshr", "notify", "--title", title, "--body", body])
    else:
        # Fallback to macOS
        subprocess.run(["osascript", "-e", f'display notification "{body}" with title "{title}"'])
```

## CLI Usage

```bash
# Simple notification
kshr notify --title "Build Complete"

# With subtitle and body
kshr notify --title "Claude Code" --subtitle "Permission" --body "Approval needed"

# Notify specific tab/panel
kshr notify --title "Done" --tab 0 --panel 1
```

## Integration Examples

### Claude Code

See the [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) for hook configuration.

### GitHub Copilot CLI

Copilot CLI supports [hooks](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/use-hooks) that run shell commands at key lifecycle events. Add to `~/.copilot/config.json`:

```json
{
  "hooks": {
    "userPromptSubmitted": [
      {
        "type": "command",
        "bash": "if command -v kshr &>/dev/null; then kshr set-status copilot_cli Running; fi",
        "timeoutSec": 3
      }
    ],
    "agentStop": [
      {
        "type": "command",
        "bash": "if command -v kshr &>/dev/null; then kshr notify --title 'Copilot CLI' --body 'Done'; kshr set-status copilot_cli Idle; else osascript -e 'display notification \"Done\" with title \"Copilot CLI\"'; fi",
        "timeoutSec": 5
      }
    ],
    "errorOccurred": [
      {
        "type": "command",
        "bash": "if command -v kshr &>/dev/null; then kshr notify --title 'Copilot CLI' --subtitle 'Error' --body \"$(cat | jq -r '.errorMessage // \"An error occurred\"' 2>/dev/null | head -c 100)\"; kshr set-status copilot_cli Error; else osascript -e 'display notification \"An error occurred\" with title \"Copilot CLI\"'; fi",
        "timeoutSec": 5
      }
    ],
    "sessionEnd": [
      {
        "type": "command",
        "bash": "if command -v kshr &>/dev/null; then kshr clear-status copilot_cli; fi",
        "timeoutSec": 3
      }
    ]
  }
}
```

Or for repo-level hooks, create `.github/hooks/notify.json`:

```json
{
  "version": 1,
  "hooks": {
    "userPromptSubmitted": [ ... ],
    "agentStop": [ ... ]
  }
}
```

### OpenAI Codex

Add to `~/.codex/config.toml`:

```toml
notify = ["bash", "-c", "command -v kshr &>/dev/null && kshr notify --title Codex --body \"$(echo $1 | jq -r '.\"last-assistant-message\" // \"Turn complete\"' 2>/dev/null | head -c 100)\" || osascript -e 'display notification \"Turn complete\" with title \"Codex\"'", "--"]
```

Or create a simple script `~/.local/bin/codex-notify.sh`:

```bash
#!/bin/bash
MSG=$(echo "$1" | jq -r '."last-assistant-message" // "Turn complete"' 2>/dev/null | head -c 100)
command -v kshr &>/dev/null && kshr notify --title "Codex" --body "$MSG" || osascript -e "display notification \"$MSG\" with title \"Codex\""
```

Then use:
```toml
notify = ["bash", "~/.local/bin/codex-notify.sh"]
```

### OpenCode Plugin

Create `.opencode/plugins/kshr-notify.js`:

```javascript
export const KshrNotificationPlugin = async ({ $, }) => {
  const notify = async (title, body) => {
    try {
      await $`command -v kshr && kshr notify --title ${title} --body ${body}`;
    } catch {
      await $`osascript -e ${"display notification \"" + body + "\" with title \"" + title + "\""}`;
    }
  };

  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") {
        await notify("OpenCode", "Session idle");
      }
    },
  };
};
```

## Environment Variables

kshr sets these in child shells:

| Variable | Description |
|----------|-------------|
| `KSHR_SOCKET_PATH` | Path to control socket |
| `KSHR_TAB_ID` | UUID of the current tab |
| `KSHR_PANEL_ID` | UUID of the current panel |

## CLI Commands

```
kshr notify --title <text> [--subtitle <text>] [--body <text>] [--tab <id|index>] [--panel <id|index>]
kshr list-notifications
kshr clear-notifications
kshr set-status <key> <value>
kshr clear-status <key>
kshr ping
```

## Best Practices

1. **Always check availability first** - Use `command -v kshr` before calling
2. **Provide fallbacks** - Use `|| osascript` for macOS fallback
3. **Keep notifications concise** - Title should be brief, use body for details
