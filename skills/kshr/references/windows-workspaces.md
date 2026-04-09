# Windows and Workspaces

Window/workspace lifecycle and ordering operations.

## Inspect

```bash
kshr list-windows
kshr current-window
kshr list-workspaces
kshr current-workspace
```

## Create/Focus/Close

```bash
kshr new-window
kshr focus-window --window window:2
kshr close-window --window window:2

kshr new-workspace
kshr select-workspace --workspace workspace:4
kshr close-workspace --workspace workspace:4
```

## Reorder and Move

```bash
kshr reorder-workspace --workspace workspace:4 --before workspace:2
kshr move-workspace-to-window --workspace workspace:4 --window window:1
```
