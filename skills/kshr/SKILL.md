---
name: kshr
description: End-user control of kshr topology and routing (windows, workspaces, panes/surfaces, focus, moves, reorder, identify, trigger flash). Use when automation needs deterministic placement and navigation in a multi-pane kshr layout.
---

# kshr Core Control

Use this skill to control non-browser kshr topology and routing.

## Core Concepts

- Window: top-level macOS kshr window.
- Workspace: tab-like group within a window.
- Pane: split container in a workspace.
- Surface: a tab within a pane (terminal or browser panel).

## Fast Start

```bash
# identify current caller context
kshr identify --json

# list topology
kshr list-windows
kshr list-workspaces
kshr list-panes
kshr list-pane-surfaces --pane pane:1

# create/focus/move
kshr new-workspace
kshr new-split right --panel pane:1
kshr move-surface --surface surface:7 --pane pane:2 --focus true
kshr reorder-surface --surface surface:7 --before surface:3

# attention cue
kshr trigger-flash --surface surface:7
```

## Handle Model

- Default output uses short refs: `window:N`, `workspace:N`, `pane:N`, `surface:N`.
- UUIDs are still accepted as inputs.
- Request UUID output only when needed: `--id-format uuids|both`.

## Deep-Dive References

| Reference | When to Use |
|-----------|-------------|
| [references/handles-and-identify.md](references/handles-and-identify.md) | Handle syntax, self-identify, caller targeting |
| [references/windows-workspaces.md](references/windows-workspaces.md) | Window/workspace lifecycle and reorder/move |
| [references/panes-surfaces.md](references/panes-surfaces.md) | Splits, surfaces, move/reorder, focus routing |
| [references/trigger-flash-and-health.md](references/trigger-flash-and-health.md) | Flash cue and surface health checks |
| [../kshr-browser/SKILL.md](../kshr-browser/SKILL.md) | Browser automation on surface-backed webviews |
| [../kshr-markdown/SKILL.md](../kshr-markdown/SKILL.md) | Markdown viewer panel with live file watching |
