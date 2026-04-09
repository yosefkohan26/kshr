# Panes and Surfaces

Split layout, surface creation, focus, move, and reorder.

## Inspect

```bash
kshr list-panes
kshr list-pane-surfaces --pane pane:1
```

## Create Splits/Surfaces

```bash
kshr new-split right --panel pane:1
kshr new-surface --type terminal --pane pane:1
kshr new-surface --type browser --pane pane:1 --url https://example.com
```

## Focus and Close

```bash
kshr focus-pane --pane pane:2
kshr focus-panel --panel surface:7
kshr close-surface --surface surface:7
```

## Move/Reorder Surfaces

```bash
kshr move-surface --surface surface:7 --pane pane:2 --focus true
kshr move-surface --surface surface:7 --workspace workspace:2 --window window:1 --after surface:4
kshr reorder-surface --surface surface:7 --before surface:3
```

Surface identity is stable across move/reorder operations.
