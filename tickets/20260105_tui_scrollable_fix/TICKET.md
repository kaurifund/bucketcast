# Ticket: TUI ScrollableContainer CSS Bug

**Type:** Bug Fix
**Priority:** High
**Status:** In Progress
**Created:** 2026-01-05

---

## Problem

TUI renders blank content when `ScrollableContainer` is used inside `TabPane`.

### Root Cause

CSS rule in `tui/sync_tui.py`:
```css
ScrollableContainer {
    height: 100%;
}
```

This causes the ScrollableContainer to collapse to zero height inside TabbedContent/TabPane.

### Evidence

| Test | CSS | Result |
|------|-----|--------|
| test_scroll1 | No ScrollableContainer CSS | Works |
| test_scroll2 | `height: 1fr` | Blank |
| test_scroll3 | `min-height: 5` | Works |
| test_scroll4 | `height: 100%` | Blank |

---

## Solution

Remove the `height: 100%` rule from ScrollableContainer CSS. The container will size naturally based on content and parent constraints.

### Files Changed

- `tui/sync_tui.py` - Remove CSS rule (line ~632)

---

## Testing

1. Run `sync-shuttle tui`
2. Verify all tabs show content:
   - Servers tab: server list or empty state
   - Inbox tab: file tree or empty state
   - Outbox tab: file tree or empty state
   - Activity tab: activity table or empty state
