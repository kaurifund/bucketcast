#!/usr/bin/env python3
"""
Bucketcast - Terminal User Interface
=======================================

A clean, intuitive interface for file synchronization.
Designed with clarity, simplicity, and user experience in mind.

Usage:
    python3 bucketcast_tui.py [--base-dir ~/.bucketcast]
"""

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import List

try:
    from textual.app import App, ComposeResult
    from textual.containers import Container, Horizontal, ScrollableContainer
    from textual.widgets import (
        Button,
        DataTable,
        Footer,
        Header,
        Input,
        Static,
        Tree,
        TabbedContent,
        TabPane,
    )
    from textual.binding import Binding
    from textual.screen import ModalScreen
    from textual.message import Message
    from rich.text import Text
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install textual rich")
    sys.exit(1)


# =============================================================================
# HELP TEXT
# =============================================================================

HELP_TEXT = """
[bold cyan]═══════════════════════════════════════════════════════════════════════════════[/bold cyan]
[bold cyan]                           BUCKETCAST - HELP                                  [/bold cyan]
[bold cyan]═══════════════════════════════════════════════════════════════════════════════[/bold cyan]

[bold yellow]KEYBOARD SHORTCUTS[/bold yellow]
────────────────────────────────────────────────────────────────────────────────
  [bold]p[/bold]         Push a file to a server's inbox
  [bold]l[/bold]         Pull files from a server's outbox
  [bold]s[/bold]         Share a file (add to your outbox)
  [bold]r[/bold]         Refresh the current view
  [bold]1-5[/bold]       Switch tabs (Servers, Inbox, Outbox, Activity, Help)
  [bold]?[/bold]         Show quick help notification
  [bold]q[/bold]         Quit the application

[bold yellow]TABS OVERVIEW[/bold yellow]
────────────────────────────────────────────────────────────────────────────────
  [bold]Servers[/bold]   View and manage configured remote servers
  [bold]Inbox[/bold]     Files received FROM other servers (organized by sender)
  [bold]Outbox[/bold]    Files shared FOR other servers to pull
  [bold]Activity[/bold]  Recent sync operations and logs
  [bold]Help[/bold]      This help screen

[bold yellow]DIRECTORY STRUCTURE[/bold yellow]
────────────────────────────────────────────────────────────────────────────────
  ~/.bucketcast/
  ├── config/
  │   ├── bucketcast.conf     Main configuration
  │   └── servers.toml          Server definitions
  ├── local/
  │   ├── inbox/<server>/       Files received from each server
  │   └── outbox/
  │       ├── global/           Shared with ALL servers
  │       └── <server>/         Shared with specific server
  └── logs/
      ├── sync.log              Human-readable log
      └── sync.jsonl            Machine-readable JSON log

[bold yellow]CLI COMMANDS[/bold yellow]
────────────────────────────────────────────────────────────────────────────────
  [bold]bucketcast init[/bold]
      Initialize directory structure (run once)

  [bold]bucketcast push -s <server> -S <file>[/bold]
      Push a file to a server's inbox
      Add --dry-run to preview without executing
      Add --force to allow overwrites

  [bold]bucketcast pull -s <server>[/bold]
      Pull files from a server's outbox (global + your hostname)
      Add --dry-run to preview

  [bold]bucketcast share --global -S <file>[/bold]
      Share a file with ALL servers (goes to outbox/global/)

  [bold]bucketcast share -s <server> -S <file>[/bold]
      Share a file with a SPECIFIC server (goes to outbox/<server>/)

  [bold]bucketcast share --list[/bold]
      List all currently shared files

  [bold]bucketcast share --remove --global -S <file>[/bold]
      Remove a file from global share

  [bold]bucketcast list servers[/bold]
      List all configured servers

  [bold]bucketcast list files -s <server>[/bold]
      List files synced with a server

  [bold]bucketcast status[/bold]
      Show sync status and recent operations

  [bold]bucketcast tui[/bold]
      Launch this interactive interface

[bold yellow]WORKFLOW EXAMPLES[/bold yellow]
────────────────────────────────────────────────────────────────────────────────
  [bold]Send a file to a colleague:[/bold]
    bucketcast push -s their-server -S ~/document.pdf

  [bold]Receive files from a colleague:[/bold]
    bucketcast pull -s their-server
    ls ~/.bucketcast/local/inbox/their-server/

  [bold]Share a file for anyone to pull:[/bold]
    bucketcast share --global -S ~/shared-notes.txt

  [bold]Check what you're sharing:[/bold]
    bucketcast share --list

[bold yellow]SAFETY FEATURES[/bold yellow]
────────────────────────────────────────────────────────────────────────────────
  • All files stay in ~/.bucketcast/ (sandboxed)
  • Files are NEVER deleted by bucketcast
  • Existing files are NEVER overwritten without --force
  • Use --dry-run to preview any operation
  • All operations are logged

[bold yellow]CONFIGURATION[/bold yellow]
────────────────────────────────────────────────────────────────────────────────
  Edit servers: ~/.bucketcast/config/servers.toml

  Example server entry:
    [servers.myserver]
    name = "My Server"
    host = "192.168.1.100"
    port = 22
    user = "myuser"
    remote_base = "/home/myuser/.bucketcast"
    enabled = true

[bold cyan]═══════════════════════════════════════════════════════════════════════════════[/bold cyan]
"""


# =============================================================================
# DATA MODELS
# =============================================================================

@dataclass
class ServerConfig:
    """Server configuration."""
    id: str
    name: str
    host: str
    port: int
    user: str
    remote_base: str
    enabled: bool
    s3_backup: bool


@dataclass
class SyncOperation:
    """Sync operation log entry."""
    uuid: str
    operation: str
    server_id: str
    source_path: str
    dest_path: str
    timestamp_start: str
    timestamp_end: str
    status: str
    bytes_transferred: int
    dry_run: bool


# =============================================================================
# CONFIGURATION LOADER
# =============================================================================

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None


def load_servers(config_dir: Path) -> List[ServerConfig]:
    """Load server configurations from TOML."""
    servers_file = config_dir / "servers.toml"
    servers = []

    if not servers_file.exists() or tomllib is None:
        return servers

    with open(servers_file, "rb") as f:
        config = tomllib.load(f)

    for server_id, props in config.get("servers", {}).items():
        servers.append(ServerConfig(
            id=server_id,
            name=props.get("name", server_id),
            host=props.get("host", ""),
            port=int(props.get("port", 22)),
            user=props.get("user", ""),
            remote_base=props.get("remote_base", ""),
            enabled=props.get("enabled", False),
            s3_backup=props.get("s3_backup", False),
        ))

    return servers


def load_operations(logs_dir: Path, limit: int = 20) -> List[SyncOperation]:
    """Load recent sync operations from JSON log."""
    log_file = logs_dir / "sync.jsonl"
    operations = []

    if not log_file.exists():
        return operations

    lines = log_file.read_text().strip().split("\n")[-limit:]

    for line in reversed(lines):
        if not line:
            continue
        try:
            data = json.loads(line)
            operations.append(SyncOperation(
                uuid=data.get("uuid", ""),
                operation=data.get("operation", ""),
                server_id=data.get("server_id", ""),
                source_path=data.get("source_path", ""),
                dest_path=data.get("dest_path", ""),
                timestamp_start=data.get("timestamp_start", ""),
                timestamp_end=data.get("timestamp_end", ""),
                status=data.get("status", ""),
                bytes_transferred=data.get("bytes_transferred", 0),
                dry_run=data.get("dry_run", False),
            ))
        except json.JSONDecodeError:
            continue

    return operations


def load_log_lines(logs_dir: Path, limit: int = 50) -> List[str]:
    """Load recent lines from human-readable log."""
    log_file = logs_dir / "sync.log"

    if not log_file.exists():
        return []

    try:
        text = log_file.read_text().strip()
        if not text:
            return []
        lines = text.split("\n")
        return lines[-limit:]
    except Exception:
        return []


def human_size(size: int) -> str:
    """Convert bytes to human readable size."""
    for unit in ["B", "KB", "MB", "GB"]:
        if size < 1024:
            return f"{size:.0f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def relative_time(timestamp: str) -> str:
    """Convert timestamp to relative time."""
    if not timestamp:
        return ""
    try:
        dt = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        now = datetime.now(dt.tzinfo)
        delta = now - dt

        if delta.days > 0:
            return f"{delta.days}d ago"
        elif delta.seconds > 3600:
            return f"{delta.seconds // 3600}h ago"
        elif delta.seconds > 60:
            return f"{delta.seconds // 60}m ago"
        else:
            return "just now"
    except Exception:
        return ""


# =============================================================================
# COMPONENTS - Reusable UI Elements
# =============================================================================

class ServerCard(Static):
    """A card displaying server info with status."""

    class Selected(Message):
        """Emitted when server is selected."""
        def __init__(self, server_id: str) -> None:
            self.server_id = server_id
            super().__init__()

    def __init__(self, server: ServerConfig, **kwargs):
        super().__init__(**kwargs)
        self.server = server
        self.add_class("server-card")
        if server.enabled:
            self.add_class("enabled")

    def compose(self) -> ComposeResult:
        s = self.server
        status = "●" if s.enabled else "○"
        status_class = "status-on" if s.enabled else "status-off"

        yield Static(f"[{status_class}]{status}[/] [bold]{s.name}[/bold]", classes="server-name")
        yield Static(f"  {s.user}@{s.host}", classes="server-detail")

    def on_click(self) -> None:
        self.post_message(self.Selected(self.server.id))


class FileTree(Tree):
    """File browser for viewing inbox/outbox contents."""

    def __init__(self, root_path: Path, label: str = "Files", **kwargs):
        super().__init__(label, **kwargs)
        self.root_path = root_path
        self.show_root = True

    def on_mount(self) -> None:
        self.root.expand()
        self._populate_tree(self.root, self.root_path)

    def _populate_tree(self, node, path: Path, depth: int = 0) -> None:
        if depth > 3 or not path.exists():
            return

        try:
            items = sorted(path.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower()))
            for item in items:
                if item.name.startswith("."):
                    continue

                if item.is_dir():
                    child = node.add(f"📁 {item.name}", expand=False)
                    child.data = item
                    self._populate_tree(child, item, depth + 1)
                else:
                    size = human_size(item.stat().st_size)
                    leaf = node.add_leaf(f"📄 {item.name}  [dim]{size}[/dim]")
                    leaf.data = item
        except PermissionError:
            pass


def _has_children(path: Path) -> bool:
    """Check if directory has any children, safely."""
    try:
        return any(True for _ in path.iterdir())
    except (PermissionError, OSError):
        return False


def count_files(path: Path) -> int:
    """Count files in a directory (non-recursive for speed)."""
    if not path.exists():
        return 0
    try:
        return sum(1 for p in path.iterdir() if p.is_file() or p.is_dir())
    except Exception:
        return 0


class QuickStats(Static):
    """Quick statistics overview."""

    def __init__(self, base_dir: Path, **kwargs):
        super().__init__(**kwargs)
        self.base_dir = base_dir

    def compose(self) -> ComposeResult:
        inbox = self.base_dir / "local" / "inbox"
        outbox = self.base_dir / "local" / "outbox"

        inbox_count = count_files(inbox)
        outbox_count = count_files(outbox)

        yield Static(
            f"📥 Inbox: {inbox_count}   📤 Outbox: {outbox_count}",
            classes="quick-stats"
        )


class EmptyState(Static):
    """Helpful empty state message."""

    def __init__(self, icon: str, title: str, subtitle: str, action: str = "", **kwargs):
        super().__init__(**kwargs)
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.add_class("empty-state")

    def compose(self) -> ComposeResult:
        yield Static(f"\n\n{self.icon}", classes="empty-icon")
        yield Static(f"[bold]{self.title}[/bold]", classes="empty-title")
        yield Static(f"[dim]{self.subtitle}[/dim]", classes="empty-subtitle")
        if self.action:
            yield Static(f"\n{self.action}", classes="empty-action")


# =============================================================================
# MODAL DIALOGS
# =============================================================================

class QuickShareDialog(ModalScreen):
    """Quick share dialog - simple and focused."""

    def __init__(self, base_dir: Path, config_dir: Path, source_path: str = ""):
        super().__init__()
        self.base_dir = base_dir
        self.config_dir = config_dir
        self.source_path = source_path

    def compose(self) -> ComposeResult:
        servers = load_servers(self.config_dir)
        enabled_servers = [s for s in servers if s.enabled]

        with Container(id="share-dialog"):
            yield Static("[bold]Share a File[/bold]", classes="dialog-title")
            yield Static("Make a file available for others to pull.", classes="dialog-subtitle")

            yield Static("\nFile to share:", classes="field-label")
            yield Input(
                value=self.source_path,
                placeholder="~/document.pdf or drag file here",
                id="share-path"
            )

            yield Static("\nShare with:", classes="field-label")
            with Horizontal(classes="share-options"):
                yield Button("🌐 Everyone", id="share-global", variant="primary")
                for server in enabled_servers[:3]:  # Show up to 3 servers
                    yield Button(f"📡 {server.name[:10]}", id=f"share-{server.id}")

            with Horizontal(classes="dialog-buttons"):
                yield Button("Cancel", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)
        elif event.button.id.startswith("share-"):
            path_input = self.query_one("#share-path", Input)
            source = path_input.value.strip()

            if not source:
                self.notify("Please enter a file path", severity="warning")
                return

            if event.button.id == "share-global":
                self.dismiss(("global", source))
            else:
                server_id = event.button.id[6:]  # Remove "share-" prefix
                self.dismiss((server_id, source))


class QuickPushDialog(ModalScreen):
    """Quick push dialog - streamlined for common use case."""

    def __init__(self, base_dir: Path, config_dir: Path, source_path: str = ""):
        super().__init__()
        self.base_dir = base_dir
        self.config_dir = config_dir
        self.source_path = source_path

    def compose(self) -> ComposeResult:
        servers = load_servers(self.config_dir)
        enabled_servers = [s for s in servers if s.enabled]

        with Container(id="push-dialog"):
            yield Static("[bold]Push File[/bold]", classes="dialog-title")
            yield Static("Send a file directly to a server's inbox.", classes="dialog-subtitle")

            yield Static("\nFile to push:", classes="field-label")
            yield Input(
                value=self.source_path,
                placeholder="~/document.pdf",
                id="push-path"
            )

            yield Static("\nDestination:", classes="field-label")
            if enabled_servers:
                for server in enabled_servers:
                    yield Button(
                        f"📡 {server.name} ({server.host})",
                        id=f"push-{server.id}",
                        classes="server-button"
                    )
            else:
                yield Static("[dim]No servers configured[/dim]")

            with Horizontal(classes="dialog-buttons"):
                yield Button("Cancel", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)
        elif event.button.id.startswith("push-"):
            path_input = self.query_one("#push-path", Input)
            source = path_input.value.strip()

            if not source:
                self.notify("Please enter a file path", severity="warning")
                return

            server_id = event.button.id[5:]  # Remove "push-" prefix
            self.dismiss((server_id, source))


class QuickPullDialog(ModalScreen):
    """Quick pull dialog - select server to pull from."""

    def __init__(self, config_dir: Path):
        super().__init__()
        self.config_dir = config_dir

    def compose(self) -> ComposeResult:
        servers = load_servers(self.config_dir)
        enabled_servers = [s for s in servers if s.enabled]

        with Container(id="pull-dialog"):
            yield Static("[bold]Pull Files[/bold]", classes="dialog-title")
            yield Static("Download files from a server's outbox.", classes="dialog-subtitle")

            yield Static("\nSelect server:", classes="field-label")
            if enabled_servers:
                for server in enabled_servers:
                    yield Button(
                        f"📡 {server.name} ({server.host})",
                        id=f"pull-{server.id}",
                        classes="server-button"
                    )
            else:
                yield Static("[dim]No servers configured[/dim]")

            with Horizontal(classes="dialog-buttons"):
                yield Button("Cancel", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)
        elif event.button.id.startswith("pull-"):
            server_id = event.button.id[5:]  # Remove "pull-" prefix
            self.dismiss(server_id)


# =============================================================================
# MAIN APPLICATION
# =============================================================================

class BucketcastTUI(App):
    """Bucketcast - Clean, intuitive file synchronization."""

    CSS = """
    /* Global */
    Screen {
        background: $surface;
    }

    /* Stats bar */
    #stats-bar {
        height: 3;
        width: 100%;
        background: $primary-background;
        padding: 0 2;
    }

    #stats-bar Horizontal {
        align: right middle;
        width: auto;
    }

    .quick-stats {
        width: 1fr;
        padding: 1 0;
    }

    #quick-actions {
        width: auto;
        height: 3;
    }

    #quick-actions Button {
        margin: 0 1;
        min-width: 10;
    }

    /* Tabs */
    #main-tabs {
        height: 1fr;
    }

    TabPane {
        padding: 1 2;
    }

    /* Section titles */
    .section-title {
        color: $text;
        margin-bottom: 1;
    }

    .structure-hint {
        color: $text-muted;
        margin-bottom: 1;
    }

    /* Server cards */
    .server-card {
        width: 100%;
        height: auto;
        padding: 1;
        margin-bottom: 1;
        background: $surface;
        border: solid $primary-darken-2;
    }

    .server-card:hover {
        background: $primary-background;
        border: solid $primary;
    }

    .server-card.enabled {
        border: solid $success-darken-2;
    }

    .server-name {
        text-style: bold;
    }

    .server-detail {
        color: $text-muted;
    }

    .status-on {
        color: $success;
    }

    .status-off {
        color: $text-muted;
    }

    /* Empty states */
    .empty-state {
        width: 100%;
        height: auto;
        text-align: center;
        padding: 4;
    }

    .empty-icon {
        text-align: center;
        text-style: bold;
    }

    .empty-title {
        text-align: center;
        margin-top: 1;
    }

    .empty-subtitle {
        text-align: center;
    }

    .empty-action {
        text-align: center;
        color: $primary;
    }

    /* Dialogs */
    ModalScreen {
        align: center middle;
    }

    #dialog, #share-dialog, #push-dialog, #pull-dialog {
        width: 60;
        height: auto;
        padding: 2;
        background: $surface;
        border: solid $primary;
    }

    .dialog-title {
        text-align: center;
        margin-bottom: 1;
    }

    .dialog-subtitle {
        text-align: center;
        color: $text-muted;
        margin-bottom: 1;
    }

    .dialog-message {
        margin: 1 0;
    }

    .dialog-buttons {
        margin-top: 2;
        align: center middle;
        height: auto;
    }

    .dialog-buttons Button {
        margin: 0 1;
    }

    .field-label {
        margin-top: 1;
        color: $text-muted;
    }

    .share-options {
        margin-top: 1;
        height: auto;
    }

    .share-options Button {
        margin-right: 1;
    }

    .server-button {
        width: 100%;
        margin: 1 0;
    }

    /* Activity table */
    #activity-table {
        height: 100%;
    }

    /* File tree */
    Tree {
        height: auto;
        max-height: 100%;
    }

    /* Scrollable areas - no height constraint, let content size naturally */
    """

    TITLE = "Bucketcast"
    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "refresh", "Refresh"),
        Binding("p", "push", "Push"),
        Binding("l", "pull", "Pull"),
        Binding("s", "share", "Share"),
        Binding("1", "tab_servers", "Servers"),
        Binding("2", "tab_inbox", "Inbox"),
        Binding("3", "tab_outbox", "Outbox"),
        Binding("4", "tab_activity", "Activity"),
        Binding("5", "tab_help", "Help"),
        Binding("?", "show_help", "Help"),
    ]

    def __init__(self, base_dir: Path, config_dir: Path):
        super().__init__()
        self.base_dir = base_dir
        self.config_dir = config_dir
        self.logs_dir = base_dir / "logs"

    def compose(self) -> ComposeResult:
        yield Header()

        with Container(id="stats-bar"):
            yield QuickStats(self.base_dir)
            with Horizontal(id="quick-actions"):
                yield Button("↑ Push", id="btn-push", variant="primary")
                yield Button("↓ Pull", id="btn-pull", variant="primary")
                yield Button("⇄ Share", id="btn-share", variant="success")

        with TabbedContent(id="main-tabs"):
            with TabPane("Servers", id="tab-servers"):
                servers = load_servers(self.config_dir)
                if not servers:
                    yield EmptyState(
                        icon="📡",
                        title="No Servers Configured",
                        subtitle="Add servers to start syncing files",
                        action="Edit ~/.bucketcast/config/servers.toml"
                    )
                else:
                    yield Static("[bold]Your Servers[/bold]\n", classes="section-title")
                    with ScrollableContainer(id="server-list"):
                        for server in servers:
                            yield ServerCard(server)

            with TabPane("Inbox", id="tab-inbox"):
                inbox_path = self.base_dir / "local" / "inbox"
                yield Static(
                    "[bold]📥 Inbox[/bold] — Files received from other servers\n",
                    classes="section-title"
                )
                if inbox_path.exists() and _has_children(inbox_path):
                    with ScrollableContainer():
                        yield FileTree(inbox_path, "Received Files")
                else:
                    yield EmptyState(
                        icon="📥",
                        title="Inbox Empty",
                        subtitle="Files you pull from servers appear here",
                        action="Press [bold]l[/bold] to pull from a server"
                    )

            with TabPane("Outbox", id="tab-outbox"):
                outbox_path = self.base_dir / "local" / "outbox"
                yield Static(
                    "[bold]📤 Outbox[/bold] — Files shared for others to pull\n",
                    classes="section-title"
                )
                yield Static(
                    "[dim]├─ global/     → Available to all servers\n"
                    "└─ <server>/   → Available to specific server[/dim]\n",
                    classes="structure-hint"
                )
                if outbox_path.exists() and _has_children(outbox_path):
                    with ScrollableContainer():
                        yield FileTree(outbox_path, "Shared Files")
                else:
                    yield EmptyState(
                        icon="📤",
                        title="Nothing Shared",
                        subtitle="Share files so others can pull them",
                        action="Press [bold]s[/bold] to share a file"
                    )

            with TabPane("Activity", id="tab-activity"):
                yield Static("[bold]📊 Recent Activity[/bold]\n", classes="section-title")
                log_lines = load_log_lines(self.logs_dir, limit=30)
                if not log_lines:
                    yield EmptyState(
                        icon="📊",
                        title="No Activity Yet",
                        subtitle="Your sync operations will appear here",
                        action=""
                    )
                else:
                    # Show recent log entries
                    for line in log_lines:
                        if "[ERROR]" in line:
                            yield Static(f"[red]{line}[/red]")
                        elif "[SUCCESS]" in line:
                            yield Static(f"[green]{line}[/green]")
                        elif "[WARN]" in line:
                            yield Static(f"[yellow]{line}[/yellow]")
                        elif "[INFO]" in line:
                            yield Static(f"[blue]{line}[/blue]")
                        else:
                            yield Static(f"[dim]{line}[/dim]")

            with TabPane("Help", id="tab-help"):
                yield Static(HELP_TEXT)

        yield Footer()

    def action_quit(self) -> None:
        self.exit()

    def action_refresh(self) -> None:
        self.refresh(recompose=True)
        self.notify("Refreshed", timeout=1)

    def action_push(self) -> None:
        self.push_screen(
            QuickPushDialog(self.base_dir, self.config_dir),
            self._handle_push_result
        )

    def action_pull(self) -> None:
        self.push_screen(
            QuickPullDialog(self.config_dir),
            self._handle_pull_result
        )

    def action_share(self) -> None:
        self.push_screen(
            QuickShareDialog(self.base_dir, self.config_dir),
            self._handle_share_result
        )

    def action_tab_servers(self) -> None:
        tabs = self.query_one("#main-tabs", TabbedContent)
        tabs.active = "tab-servers"

    def action_tab_inbox(self) -> None:
        tabs = self.query_one("#main-tabs", TabbedContent)
        tabs.active = "tab-inbox"

    def action_tab_outbox(self) -> None:
        tabs = self.query_one("#main-tabs", TabbedContent)
        tabs.active = "tab-outbox"

    def action_tab_activity(self) -> None:
        tabs = self.query_one("#main-tabs", TabbedContent)
        tabs.active = "tab-activity"

    def action_tab_help(self) -> None:
        tabs = self.query_one("#main-tabs", TabbedContent)
        tabs.active = "tab-help"

    def action_show_help(self) -> None:
        self.notify(
            "p=Push  l=Pull  s=Share  1-5=Tabs  r=Refresh  q=Quit",
            timeout=5
        )

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        btn = event.button.id
        if btn == "btn-push":
            self.action_push()
        elif btn == "btn-pull":
            self.action_pull()
        elif btn == "btn-share":
            self.action_share()

    def _handle_push_result(self, result) -> None:
        if result is None:
            return
        server_id, source = result
        self._execute_push(server_id, source)

    def _handle_pull_result(self, result) -> None:
        if result is None:
            return
        self._execute_pull(result)

    def _handle_share_result(self, result) -> None:
        if result is None:
            return
        target, source = result
        self._execute_share(target, source)

    def _execute_push(self, server_id: str, source: str) -> None:
        script = Path(__file__).parent.parent / "bucketcast.sh"
        args = ["push", "--server", server_id, "--source", source]
        self.notify(f"Pushing to {server_id}...", timeout=2)

        def _run() -> subprocess.CompletedProcess:
            try:
                return subprocess.run(
                    [str(script)] + args,
                    capture_output=True, text=True, timeout=60,
                )
            except subprocess.TimeoutExpired as e:
                return subprocess.CompletedProcess(
                    args=e.cmd, returncode=124, 
                    stdout="", stderr=f"Timeout after {e.timeout}s: {e}"
                )
            except Exception as e:
                return subprocess.CompletedProcess(
                    args=[str(script)] + args, returncode=125,
                    stdout="", stderr=f"Error: {e}"
                )

        self.run_worker(_run, name="push", exit_on_error=False)

    def _execute_pull(self, server_id: str) -> None:
        script = Path(__file__).parent.parent / "bucketcast.sh"
        args = ["pull", "--server", server_id]
        self.notify(f"Pulling from {server_id}...", timeout=2)

        def _run() -> subprocess.CompletedProcess:
            try:
                return subprocess.run(
                    [str(script)] + args,
                    capture_output=True, text=True, timeout=60,
                )
            except subprocess.TimeoutExpired as e:
                return subprocess.CompletedProcess(
                    args=e.cmd, returncode=124, 
                    stdout="", stderr=f"Timeout after {e.timeout}s: {e}"
                )
            except Exception as e:
                return subprocess.CompletedProcess(
                    args=[str(script)] + args, returncode=125,
                    stdout="", stderr=f"Error: {e}"
                )

        self.run_worker(_run, name="pull", exit_on_error=False)

    def _execute_share(self, target: str, source: str) -> None:
        script = Path(__file__).parent.parent / "bucketcast.sh"
        if target == "global":
            args = ["share", "--global", "--source", source]
        else:
            args = ["share", "--server", target, "--source", source]
        self.notify(f"Sharing...", timeout=2)

        def _run() -> subprocess.CompletedProcess:
            try:
                return subprocess.run(
                    [str(script)] + args,
                    capture_output=True, text=True, timeout=30,
                )
            except subprocess.TimeoutExpired as e:
                return subprocess.CompletedProcess(
                    args=e.cmd, returncode=124, 
                    stdout="", stderr=f"Timeout after {e.timeout}s: {e}"
                )
            except Exception as e:
                return subprocess.CompletedProcess(
                    args=[str(script)] + args, returncode=125,
                    stdout="", stderr=f"Error: {e}"
                )

        self.run_worker(_run, name="share", exit_on_error=False)

    def on_worker_state_changed(self, event) -> None:
        """Handle worker completion for push/pull/share operations."""
        worker = event.worker
        if worker.is_finished and not worker.is_cancelled:
            result = worker.result
            if result is None:
                return
            if isinstance(result, subprocess.CompletedProcess):
                if result.returncode == 0:
                    self.notify(f"✓ {worker.name.title()} complete!", severity="information")
                    if worker.name in ("pull", "share"):
                        self.action_refresh()
                else:
                    self.notify(f"{worker.name.title()} failed: {result.stderr[:80]}", severity="error")
            elif isinstance(result, Exception):
                self.notify(f"Error: {result}", severity="error")


# =============================================================================
# ENTRY POINT
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Bucketcast TUI")
    parser.add_argument(
        "--base-dir",
        type=Path,
        default=Path.home() / ".bucketcast",
        help="Base directory for bucketcast"
    )
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=None,
        help="Configuration directory"
    )

    args = parser.parse_args()

    base_dir = args.base_dir.expanduser().resolve()
    config_dir = args.config_dir or (base_dir / "config")
    config_dir = config_dir.expanduser().resolve()

    if not base_dir.exists():
        print(f"Error: Base directory does not exist: {base_dir}")
        print("Run 'bucketcast init' first.")
        sys.exit(1)

    app = BucketcastTUI(base_dir, config_dir)
    app.run()


if __name__ == "__main__":
    main()
