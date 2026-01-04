#!/usr/bin/env python3
"""
Sync Shuttle - Terminal User Interface
=======================================

Interactive TUI for managing file synchronization operations.
Built with Textual for a modern, responsive terminal interface.

Usage:
    python3 sync_tui.py --base-dir ~/.sync-shuttle --config-dir ~/.sync-shuttle/config
"""

import argparse
import asyncio
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

try:
    from textual.app import App, ComposeResult
    from textual.containers import Container, Horizontal, Vertical, ScrollableContainer
    from textual.widgets import (
        Button,
        DataTable,
        Footer,
        Header,
        Input,
        Label,
        ListItem,
        ListView,
        Static,
        Switch,
        Tree,
    )
    from textual.binding import Binding
    from textual.screen import Screen
    from rich.text import Text
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install textual rich")
    sys.exit(1)


# =============================================================================
# DATA MODELS (Schema Contracts)
# =============================================================================

@dataclass
class ServerConfig:
    """Server configuration schema."""
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
    """Sync operation log entry schema."""
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

# Python 3.11+ has tomllib built-in
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None


def load_servers(config_dir: Path) -> list[ServerConfig]:
    """Load server configurations from TOML config file."""
    servers_file = config_dir / "servers.toml"
    servers = []

    if not servers_file.exists():
        return servers

    if tomllib is None:
        print("Warning: TOML support not available. Run: pip install tomli", file=sys.stderr)
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


def load_operations(logs_dir: Path, limit: int = 50) -> list[SyncOperation]:
    """Load recent sync operations from log file."""
    log_file = logs_dir / "sync.jsonl"
    operations = []
    
    if not log_file.exists():
        return operations
    
    # Read last N lines
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


# =============================================================================
# TUI COMPONENTS
# =============================================================================

class ServerList(ListView):
    """Server list widget."""
    
    def __init__(self, servers: list[ServerConfig], **kwargs):
        super().__init__(**kwargs)
        self.servers = servers
    
    def compose(self) -> ComposeResult:
        for server in self.servers:
            status = "●" if server.enabled else "○"
            color = "green" if server.enabled else "red"
            yield ListItem(
                Static(f"[{color}]{status}[/] {server.id} - {server.name}"),
                id=f"server-{server.id}"
            )


class OperationTable(DataTable):
    """Recent operations table widget."""
    
    def __init__(self, operations: list[SyncOperation], **kwargs):
        super().__init__(**kwargs)
        self.operations = operations
    
    def on_mount(self) -> None:
        self.add_columns("Status", "Op", "Server", "Time", "UUID")
        
        for op in self.operations[:20]:
            status_icon = "✓" if op.status == "SUCCESS" else "✗"
            time_str = op.timestamp_start[11:19] if op.timestamp_start else ""
            
            self.add_row(
                status_icon,
                op.operation.upper()[:4],
                op.server_id[:12],
                time_str,
                op.uuid[:8],
            )


class FileBrowser(Tree):
    """File browser widget for inbox/outbox."""
    
    def __init__(self, root_path: Path, label: str = "Files", **kwargs):
        super().__init__(label, **kwargs)
        self.root_path = root_path
    
    def on_mount(self) -> None:
        self.root.expand()
        self._populate_tree(self.root, self.root_path)
    
    def _populate_tree(self, node, path: Path, depth: int = 0) -> None:
        if depth > 3 or not path.exists():
            return
        
        try:
            for item in sorted(path.iterdir()):
                if item.name.startswith("."):
                    continue
                
                if item.is_dir():
                    child = node.add(f"📁 {item.name}", expand=False)
                    # Add placeholder for lazy loading
                    child.data = item
                else:
                    size = item.stat().st_size
                    size_str = self._human_size(size)
                    node.add_leaf(f"📄 {item.name} ({size_str})")
        except PermissionError:
            pass
    
    @staticmethod
    def _human_size(size: int) -> str:
        for unit in ["B", "KB", "MB", "GB"]:
            if size < 1024:
                return f"{size:.1f}{unit}"
            size /= 1024
        return f"{size:.1f}TB"


class StatusPanel(Static):
    """Status panel showing sync-shuttle state."""
    
    def __init__(self, base_dir: Path, **kwargs):
        super().__init__(**kwargs)
        self.base_dir = base_dir
    
    def compose(self) -> ComposeResult:
        dirs = {
            "Config": self.base_dir / "config",
            "Remote": self.base_dir / "remote",
            "Inbox": self.base_dir / "local" / "inbox",
            "Outbox": self.base_dir / "local" / "outbox",
            "Logs": self.base_dir / "logs",
        }
        
        lines = ["[bold]Directory Status[/bold]\n"]
        
        for name, path in dirs.items():
            if path.exists():
                try:
                    count = sum(1 for _ in path.rglob("*") if _.is_file())
                except:
                    count = 0
                lines.append(f"  [green]✓[/] {name}: {count} files")
            else:
                lines.append(f"  [red]✗[/] {name}: missing")
        
        yield Static("\n".join(lines))


# =============================================================================
# SCREENS
# =============================================================================

class MainScreen(Screen):
    """Main dashboard screen."""
    
    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "refresh", "Refresh"),
        Binding("p", "push", "Push"),
        Binding("l", "pull", "Pull"),
        Binding("s", "servers", "Servers"),
        Binding("o", "operations", "Operations"),
    ]
    
    def __init__(self, base_dir: Path, config_dir: Path, **kwargs):
        super().__init__(**kwargs)
        self.base_dir = base_dir
        self.config_dir = config_dir
        self.logs_dir = base_dir / "logs"
    
    def compose(self) -> ComposeResult:
        yield Header()
        
        with Container(id="main-container"):
            with Horizontal(id="top-row"):
                with Vertical(id="servers-panel", classes="panel"):
                    yield Static("[bold]Servers[/bold]", classes="panel-title")
                    servers = load_servers(self.config_dir)
                    if servers:
                        yield ServerList(servers, id="server-list")
                    else:
                        yield Static("No servers configured.\nEdit config/servers.toml")
                
                with Vertical(id="status-panel", classes="panel"):
                    yield Static("[bold]Status[/bold]", classes="panel-title")
                    yield StatusPanel(self.base_dir)
            
            with Vertical(id="operations-panel", classes="panel"):
                yield Static("[bold]Recent Operations[/bold]", classes="panel-title")
                operations = load_operations(self.logs_dir)
                if operations:
                    yield OperationTable(operations, id="operations-table")
                else:
                    yield Static("No operations logged yet.")
            
            with Horizontal(id="actions-row"):
                yield Button("Push", id="btn-push", variant="primary")
                yield Button("Pull", id="btn-pull", variant="primary")
                yield Button("Dry Run", id="btn-dryrun", variant="warning")
                yield Button("Status", id="btn-status", variant="default")
                yield Button("Refresh", id="btn-refresh", variant="default")
        
        yield Footer()
    
    def action_refresh(self) -> None:
        """Refresh the display."""
        self.refresh()
    
    def action_quit(self) -> None:
        """Quit the application."""
        self.app.exit()
    
    async def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        button_id = event.button.id
        
        if button_id == "btn-refresh":
            self.action_refresh()
        elif button_id == "btn-status":
            await self.run_command(["status"])
        elif button_id == "btn-push":
            self.app.push_screen(PushScreen(self.base_dir, self.config_dir))
        elif button_id == "btn-pull":
            self.app.push_screen(PullScreen(self.base_dir, self.config_dir))
        elif button_id == "btn-dryrun":
            self.notify("Select an operation first", severity="warning")
    
    async def run_command(self, args: list[str]) -> None:
        """Run sync-shuttle command and show output."""
        script_path = Path(__file__).parent.parent / "sync-shuttle.sh"
        
        if not script_path.exists():
            self.notify(f"Script not found: {script_path}", severity="error")
            return
        
        try:
            result = subprocess.run(
                [str(script_path)] + args,
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if result.returncode == 0:
                self.notify("Command completed successfully")
            else:
                self.notify(f"Command failed: {result.stderr[:100]}", severity="error")
        except subprocess.TimeoutExpired:
            self.notify("Command timed out", severity="error")
        except Exception as e:
            self.notify(f"Error: {str(e)}", severity="error")


class PushScreen(Screen):
    """Push operation screen."""
    
    BINDINGS = [
        Binding("escape", "pop_screen", "Back"),
    ]
    
    def __init__(self, base_dir: Path, config_dir: Path, **kwargs):
        super().__init__(**kwargs)
        self.base_dir = base_dir
        self.config_dir = config_dir
        self.selected_server = None
    
    def compose(self) -> ComposeResult:
        yield Header()
        
        with Container(id="push-container"):
            yield Static("[bold]Push Files to Server[/bold]\n", classes="screen-title")
            
            with Vertical(id="push-form"):
                yield Static("Select Server:")
                servers = load_servers(self.config_dir)
                yield ServerList([s for s in servers if s.enabled], id="server-select")
                
                yield Static("\nSource Path:")
                yield Input(
                    placeholder="Enter path to push (e.g., ~/myfile.txt)",
                    id="source-input"
                )
                
                with Horizontal(id="options-row"):
                    yield Label("Dry Run:")
                    yield Switch(value=True, id="dry-run-switch")
                    yield Label("Force:")
                    yield Switch(value=False, id="force-switch")
                
                yield Static("\nOutbox Files:", classes="section-title")
                outbox_path = self.base_dir / "local" / "outbox"
                if outbox_path.exists():
                    yield FileBrowser(outbox_path, "Outbox")
                else:
                    yield Static("Outbox is empty")
            
            with Horizontal(id="push-actions"):
                yield Button("Execute Push", id="btn-execute", variant="success")
                yield Button("Cancel", id="btn-cancel", variant="error")
        
        yield Footer()
    
    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-cancel":
            self.app.pop_screen()
        elif event.button.id == "btn-execute":
            await self.execute_push()
    
    async def execute_push(self) -> None:
        source_input = self.query_one("#source-input", Input)
        dry_run = self.query_one("#dry-run-switch", Switch).value
        force = self.query_one("#force-switch", Switch).value
        
        source = source_input.value.strip()
        
        if not source:
            self.notify("Please enter a source path", severity="error")
            return
        
        if not self.selected_server:
            self.notify("Please select a server", severity="error")
            return
        
        args = ["push", "--server", self.selected_server, "--source", source]
        
        if dry_run:
            args.append("--dry-run")
        if force:
            args.append("--force")
        
        self.notify(f"Running: sync-shuttle {' '.join(args)}")
        # In a real implementation, this would run the command
        # For now, just show the command


class PullScreen(Screen):
    """Pull operation screen."""

    BINDINGS = [
        Binding("escape", "pop_screen", "Back"),
    ]

    def __init__(self, base_dir: Path, config_dir: Path, **kwargs):
        super().__init__(**kwargs)
        self.base_dir = base_dir
        self.config_dir = config_dir
        self.selected_server = None

    def compose(self) -> ComposeResult:
        yield Header()

        with Container(id="pull-container"):
            yield Static("[bold]Pull Files from Server[/bold]\n", classes="screen-title")

            with Vertical(id="pull-form"):
                yield Static("Select Server:")
                servers = load_servers(self.config_dir)
                yield ServerList([s for s in servers if s.enabled], id="server-select")

                with Horizontal(id="options-row"):
                    yield Label("Dry Run:")
                    yield Switch(value=True, id="dry-run-switch")
                    yield Label("Force:")
                    yield Switch(value=False, id="force-switch")

                yield Static("\nInbox (files will arrive here):", classes="section-title")
                inbox_path = self.base_dir / "local" / "inbox"
                if inbox_path.exists() and any(inbox_path.iterdir()):
                    yield FileBrowser(inbox_path, "Inbox")
                else:
                    yield Static("Inbox is empty")

            with Horizontal(id="pull-actions"):
                yield Button("Execute Pull", id="btn-execute", variant="success")
                yield Button("Cancel", id="btn-cancel", variant="error")

        yield Footer()

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-cancel":
            self.app.pop_screen()
        elif event.button.id == "btn-execute":
            await self.execute_pull()

    async def execute_pull(self) -> None:
        dry_run = self.query_one("#dry-run-switch", Switch).value
        force = self.query_one("#force-switch", Switch).value

        if not self.selected_server:
            self.notify("Please select a server", severity="error")
            return

        args = ["pull", "--server", self.selected_server]

        if dry_run:
            args.append("--dry-run")
        if force:
            args.append("--force")

        self.notify(f"Running: sync-shuttle {' '.join(args)}")


# =============================================================================
# FILE DATA MODEL
# =============================================================================

@dataclass
class FileEntry:
    """File entry for the browser."""
    name: str
    path: Path
    size: int
    modified: float
    location: str  # "inbox", "outbox", or server_id
    source: str    # For inbox files, the sender

    @property
    def size_str(self) -> str:
        size = self.size
        for unit in ["B", "KB", "MB", "GB"]:
            if size < 1024:
                return f"{size:.1f} {unit}"
            size /= 1024
        return f"{size:.1f} TB"

    @property
    def age_str(self) -> str:
        diff = datetime.now().timestamp() - self.modified
        if diff < 60:
            return "just now"
        elif diff < 3600:
            return f"{int(diff / 60)} min ago"
        elif diff < 86400:
            return f"{int(diff / 3600)} hours ago"
        elif diff < 604800:
            return f"{int(diff / 86400)} days ago"
        else:
            return datetime.fromtimestamp(self.modified).strftime("%Y-%m-%d")


# =============================================================================
# BROWSE SCREEN - File Discovery TUI
# =============================================================================

class LocationTree(Tree):
    """Tree widget for browsing locations (inbox/outbox/remote)."""

    def __init__(self, base_dir: Path, config_dir: Path, **kwargs):
        super().__init__("Locations", **kwargs)
        self.base_dir = base_dir
        self.config_dir = config_dir

    def on_mount(self) -> None:
        self.root.expand()
        self._build_tree()

    def _build_tree(self) -> None:
        # Inbox
        inbox_dir = self.base_dir / "local" / "inbox"
        inbox_count = self._count_files(inbox_dir)
        inbox_node = self.root.add(f"[cyan]Inbox[/cyan] ({inbox_count})", data={"type": "inbox", "path": inbox_dir})

        if inbox_dir.exists():
            for sender_dir in sorted(inbox_dir.iterdir()):
                if sender_dir.is_dir():
                    count = self._count_files(sender_dir)
                    inbox_node.add(f"{sender_dir.name} ({count})", data={"type": "inbox_sender", "path": sender_dir, "sender": sender_dir.name})

        # Outbox
        outbox_dir = self.base_dir / "local" / "outbox"
        outbox_count = self._count_files(outbox_dir)
        self.root.add(f"[green]Outbox[/green] ({outbox_count})", data={"type": "outbox", "path": outbox_dir})

        # Remote servers
        servers = load_servers(self.config_dir)
        if servers:
            remote_node = self.root.add("[magenta]Remote[/magenta]", data={"type": "remote_root"})
            for server in servers:
                status = "[green]●[/green]" if server.enabled else "[red]○[/red]"
                remote_node.add(f"{status} {server.id}", data={"type": "remote", "server": server})

    def _count_files(self, path: Path) -> int:
        if not path.exists():
            return 0
        try:
            return sum(1 for f in path.rglob("*") if f.is_file())
        except:
            return 0


class FileListTable(DataTable):
    """Table widget showing files in selected location."""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.files: list[FileEntry] = []

    def on_mount(self) -> None:
        self.cursor_type = "row"
        self.add_columns("Name", "Size", "Modified", "Source")

    def load_files(self, files: list[FileEntry]) -> None:
        self.files = files
        self.clear()
        for f in files:
            self.add_row(
                f.name,
                f.size_str,
                f.age_str,
                f.source or "-",
                key=str(f.path)
            )

    def get_selected_file(self) -> Optional[FileEntry]:
        if self.cursor_row is not None and 0 <= self.cursor_row < len(self.files):
            return self.files[self.cursor_row]
        return None


class PreviewPanel(Static):
    """Preview panel showing selected file details."""

    def __init__(self, **kwargs):
        super().__init__("", **kwargs)
        self.current_file: Optional[FileEntry] = None

    def show_file(self, file: Optional[FileEntry]) -> None:
        self.current_file = file
        if file is None:
            self.update("[dim]No file selected[/dim]")
            return

        lines = [
            f"[bold]{file.name}[/bold] ({file.size_str})",
            f"Location: {file.location}",
        ]
        if file.source:
            lines.append(f"From: {file.source}")
        lines.append(f"Modified: {file.age_str}")
        lines.append(f"Path: {file.path}")

        # Try to show preview for text files
        if file.size < 10000:
            try:
                content = file.path.read_text()[:500]
                if content:
                    lines.append("")
                    lines.append("[dim]Preview:[/dim]")
                    lines.append(content[:300] + ("..." if len(content) > 300 else ""))
            except:
                pass

        self.update("\n".join(lines))


class BrowseScreen(Screen):
    """File browser screen as per design spec."""

    BINDINGS = [
        Binding("q", "quit", "Quit", show=True),
        Binding("escape", "quit", "Quit", show=False),
        Binding("slash", "search", "Search", show=True),
        Binding("p", "pull", "Pull", show=True),
        Binding("d", "delete", "Delete", show=True),
        Binding("o", "open_file", "Open", show=True),
        Binding("r", "refresh", "Refresh", show=True),
        Binding("l", "focus_files", "Files", show=False),
        Binding("h", "focus_tree", "Tree", show=False),
    ]

    def __init__(self, base_dir: Path, config_dir: Path, **kwargs):
        super().__init__(**kwargs)
        self.base_dir = base_dir
        self.config_dir = config_dir
        self.search_query = ""

    def compose(self) -> ComposeResult:
        yield Header()

        with Container(id="browse-container"):
            with Horizontal(id="browse-top"):
                with ScrollableContainer(id="locations-panel"):
                    yield Static("[bold]Locations[/bold]", classes="panel-header")
                    yield LocationTree(self.base_dir, self.config_dir, id="location-tree")

                with ScrollableContainer(id="files-panel"):
                    yield Static("[bold]Files[/bold]", classes="panel-header", id="files-header")
                    yield FileListTable(id="file-table")

            with ScrollableContainer(id="preview-panel"):
                yield Static("[bold]Preview[/bold]", classes="panel-header")
                yield PreviewPanel(id="preview")

        yield Footer()

    def on_mount(self) -> None:
        # Load outbox by default
        self._load_location_files("outbox", self.base_dir / "local" / "outbox")
        # Focus the tree first
        self.query_one("#location-tree").focus()

    def action_focus_files(self) -> None:
        """Focus the file table."""
        self.query_one("#file-table").focus()

    def action_focus_tree(self) -> None:
        """Focus the location tree."""
        self.query_one("#location-tree").focus()

    def _load_location_files(self, location: str, path: Path, source: str = "") -> None:
        """Load files from a location into the file table."""
        files = []

        if not path.exists():
            self.query_one("#file-table", FileListTable).load_files([])
            return

        try:
            for f in sorted(path.rglob("*")):
                if f.is_file():
                    # Apply search filter if set
                    if self.search_query:
                        import fnmatch
                        if not fnmatch.fnmatch(f.name.lower(), f"*{self.search_query.lower()}*"):
                            continue

                    stat = f.stat()
                    files.append(FileEntry(
                        name=f.name,
                        path=f,
                        size=stat.st_size,
                        modified=stat.st_mtime,
                        location=location,
                        source=source,
                    ))
        except Exception as e:
            self.notify(f"Error loading files: {e}", severity="error")

        self.query_one("#file-table", FileListTable).load_files(files)
        self.query_one("#files-header", Static).update(f"[bold]Files[/bold] ({len(files)})")

    def on_tree_node_selected(self, event: Tree.NodeSelected) -> None:
        """Handle location tree selection."""
        data = event.node.data
        if not data:
            return

        node_type = data.get("type", "")

        if node_type == "inbox":
            self._load_location_files("inbox", data["path"])
        elif node_type == "inbox_sender":
            self._load_location_files("inbox", data["path"], source=data.get("sender", ""))
        elif node_type == "outbox":
            self._load_location_files("outbox", data["path"])
        elif node_type == "remote":
            server = data.get("server")
            if server:
                self._load_remote_files(server)

    def _load_remote_files(self, server: ServerConfig) -> None:
        """Load files from remote server (uses cache from CLI)."""
        cache_file = self.base_dir / "cache" / f"remote-{server.id}.cache"
        files = []

        if cache_file.exists():
            try:
                content = cache_file.read_text()
                lines = content.strip().split("\n")
                if lines and lines[0].startswith("OK|"):
                    for line in lines[1:]:
                        if line == "CACHED":
                            continue
                        parts = line.split("|")
                        if len(parts) >= 2:
                            size = int(parts[0]) if parts[0].isdigit() else 0
                            name = parts[1]
                            mod_time = float(parts[2]) if len(parts) > 2 else 0
                            files.append(FileEntry(
                                name=name,
                                path=Path(f"remote://{server.id}/{name}"),
                                size=size,
                                modified=mod_time,
                                location=f"remote:{server.id}",
                                source=server.host,
                            ))
            except Exception as e:
                self.notify(f"Error reading cache: {e}", severity="warning")

        if not files:
            self.notify(f"No cached data for {server.id}. Run 'sync-shuttle files --remote' first.", severity="warning")

        self.query_one("#file-table", FileListTable).load_files(files)
        self.query_one("#files-header", Static).update(f"[bold]Remote: {server.id}[/bold] ({len(files)})")

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle file selection in the table."""
        table = self.query_one("#file-table", FileListTable)
        file = table.get_selected_file()
        self.query_one("#preview", PreviewPanel).show_file(file)

    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        """Update preview when row is highlighted."""
        table = self.query_one("#file-table", FileListTable)
        file = table.get_selected_file()
        self.query_one("#preview", PreviewPanel).show_file(file)

    def action_quit(self) -> None:
        self.app.exit()

    def action_refresh(self) -> None:
        """Refresh the current view and reload files."""
        # Rebuild the location tree
        tree = self.query_one("#location-tree", LocationTree)
        tree.clear()
        tree._build_tree()
        tree.root.expand()

        # Reload the current location's files
        # Default to outbox if nothing selected
        self._load_location_files("outbox", self.base_dir / "local" / "outbox")

        self.notify("Refreshed")

    def action_search(self) -> None:
        """Open search dialog."""
        self.app.push_screen(SearchDialog(self._apply_search))

    def _apply_search(self, query: str) -> None:
        """Apply search filter."""
        self.search_query = query
        self.notify(f"Searching: {query}" if query else "Search cleared")
        # Re-trigger current location load
        tree = self.query_one("#location-tree", LocationTree)
        if tree.cursor_node and tree.cursor_node.data:
            self.on_tree_node_selected(Tree.NodeSelected(tree, tree.cursor_node))

    def action_open_file(self) -> None:
        """Open the selected file."""
        table = self.query_one("#file-table", FileListTable)
        file = table.get_selected_file()
        if file and file.path.exists():
            import subprocess
            try:
                subprocess.run(["xdg-open", str(file.path)], check=False)
                self.notify(f"Opening: {file.name}")
            except:
                self.notify("Cannot open file", severity="error")
        else:
            self.notify("File not available locally", severity="warning")

    def action_delete(self) -> None:
        """Delete the selected file (local only)."""
        table = self.query_one("#file-table", FileListTable)
        file = table.get_selected_file()
        if file and file.path.exists() and not str(file.path).startswith("remote://"):
            self.app.push_screen(ConfirmDialog(
                f"Delete {file.name}?",
                lambda: self._do_delete(file)
            ))
        else:
            self.notify("Cannot delete remote files", severity="warning")

    def _do_delete(self, file: FileEntry) -> None:
        """Actually delete the file."""
        try:
            file.path.unlink()
            self.notify(f"Deleted: {file.name}")
            self.action_refresh()
        except Exception as e:
            self.notify(f"Error: {e}", severity="error")

    def action_pull(self) -> None:
        """Pull from the selected remote server."""
        table = self.query_one("#file-table", FileListTable)
        file = table.get_selected_file()
        if file and file.location.startswith("remote:"):
            server_id = file.location.split(":")[1]
            self.notify(f"Run: sync-shuttle pull -s {server_id}")
        else:
            self.notify("Select a remote file first", severity="warning")


class SearchDialog(Screen):
    """Search input dialog."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
    ]

    def __init__(self, callback, **kwargs):
        super().__init__(**kwargs)
        self.callback = callback

    def compose(self) -> ComposeResult:
        with Container(id="search-dialog"):
            yield Static("[bold]Search Files[/bold]")
            yield Input(placeholder="Enter search pattern (e.g., *.pdf)", id="search-input")
            with Horizontal():
                yield Button("Search", id="btn-search", variant="primary")
                yield Button("Clear", id="btn-clear", variant="default")
                yield Button("Cancel", id="btn-cancel", variant="error")

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-cancel":
            self.app.pop_screen()
        elif event.button.id == "btn-clear":
            self.callback("")
            self.app.pop_screen()
        elif event.button.id == "btn-search":
            query = self.query_one("#search-input", Input).value
            self.callback(query)
            self.app.pop_screen()

    def action_cancel(self) -> None:
        self.app.pop_screen()


class ConfirmDialog(Screen):
    """Confirmation dialog."""

    BINDINGS = [
        Binding("escape", "cancel", "Cancel"),
        Binding("y", "confirm", "Yes"),
        Binding("n", "cancel", "No"),
    ]

    def __init__(self, message: str, callback, **kwargs):
        super().__init__(**kwargs)
        self.message = message
        self.callback = callback

    def compose(self) -> ComposeResult:
        with Container(id="confirm-dialog"):
            yield Static(f"[bold]{self.message}[/bold]")
            with Horizontal():
                yield Button("Yes", id="btn-yes", variant="error")
                yield Button("No", id="btn-no", variant="default")

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-yes":
            self.callback()
        self.app.pop_screen()

    def action_confirm(self) -> None:
        self.callback()
        self.app.pop_screen()

    def action_cancel(self) -> None:
        self.app.pop_screen()


# =============================================================================
# MAIN APPLICATION
# =============================================================================

class SyncShuttleTUI(App):
    """Main Sync Shuttle TUI application."""

    # Disable mouse support to avoid escape code artifacts
    ENABLE_COMMAND_PALETTE = False

    CSS = """
    Screen {
        background: $surface;
    }

    #main-container {
        width: 100%;
        height: 100%;
        padding: 1;
    }

    #top-row {
        height: 40%;
        width: 100%;
    }

    .panel {
        border: solid $primary;
        padding: 1;
        margin: 0 1;
    }

    .panel-title {
        color: $secondary;
        text-style: bold;
    }

    #servers-panel {
        width: 40%;
    }

    #status-panel {
        width: 60%;
    }

    #operations-panel {
        height: 40%;
        width: 100%;
    }

    #actions-row {
        height: 5;
        width: 100%;
        align: center middle;
        padding: 1;
    }

    #actions-row Button {
        margin: 0 1;
    }

    .screen-title {
        text-align: center;
        color: $secondary;
        padding: 1;
    }

    #push-container, #pull-container {
        padding: 2;
    }

    #options-row {
        height: 3;
        padding: 1 0;
    }

    #options-row Label {
        margin-right: 1;
    }

    #push-actions, #pull-actions {
        height: 5;
        align: center middle;
        padding: 1;
    }

    DataTable {
        height: 100%;
    }

    ListView {
        height: auto;
        max-height: 100%;
    }

    /* Browse Screen Styles */
    #browse-container {
        width: 100%;
        height: 100%;
        padding: 0;
    }

    #browse-top {
        height: 2fr;
        width: 100%;
    }

    #locations-panel {
        width: 30;
        min-width: 25;
        max-width: 40;
        border: solid $primary;
        padding: 0 1;
    }

    #locations-panel:focus-within {
        border: solid $secondary;
    }

    #files-panel {
        width: 1fr;
        border: solid $primary;
        padding: 0 1;
    }

    #files-panel:focus-within {
        border: solid $secondary;
    }

    #preview-panel {
        height: 1fr;
        min-height: 5;
        max-height: 15;
        width: 100%;
        border: solid $primary;
        padding: 1;
    }

    .panel-header {
        color: $secondary;
        text-style: bold;
        height: 1;
        padding: 0;
        margin-bottom: 1;
    }

    #location-tree {
        width: 100%;
        height: auto;
    }

    #location-tree:focus {
        background: $primary-background;
    }

    #file-table {
        width: 100%;
        height: auto;
    }

    #file-table:focus {
        background: $primary-background;
    }

    #preview {
        width: 100%;
        height: auto;
    }

    /* Dialog Styles */
    #search-dialog, #confirm-dialog {
        align: center middle;
        width: 60;
        height: auto;
        border: thick $primary;
        background: $surface;
        padding: 2;
    }

    #search-dialog Input {
        margin: 1 0;
    }

    #search-dialog Horizontal, #confirm-dialog Horizontal {
        align: center middle;
        height: 3;
        margin-top: 1;
    }

    #search-dialog Button, #confirm-dialog Button {
        margin: 0 1;
    }
    """
    
    TITLE = "Sync Shuttle"
    SUB_TITLE = "Safe File Synchronization"

    def __init__(self, base_dir: Path, config_dir: Path, mode: str = "dashboard"):
        super().__init__()
        self.base_dir = base_dir
        self.config_dir = config_dir
        self.mode = mode

    def on_mount(self) -> None:
        if self.mode == "browse":
            self.push_screen(BrowseScreen(self.base_dir, self.config_dir))
        else:
            self.push_screen(MainScreen(self.base_dir, self.config_dir))


# =============================================================================
# ENTRY POINT
# =============================================================================

def reset_terminal():
    """Reset terminal to clean state after TUI exit."""
    # Disable mouse tracking modes
    sys.stdout.write("\033[?1000l")  # Disable mouse click tracking
    sys.stdout.write("\033[?1002l")  # Disable mouse drag tracking
    sys.stdout.write("\033[?1003l")  # Disable all mouse tracking
    sys.stdout.write("\033[?1006l")  # Disable SGR mouse mode
    sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser(description="Sync Shuttle TUI")
    parser.add_argument(
        "--base-dir",
        type=Path,
        default=Path.home() / ".sync-shuttle",
        help="Base directory for sync-shuttle"
    )
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=None,
        help="Configuration directory"
    )
    parser.add_argument(
        "--mode",
        choices=["dashboard", "browse"],
        default="dashboard",
        help="TUI mode: dashboard (default) or browse (file browser)"
    )

    args = parser.parse_args()

    base_dir = args.base_dir.expanduser().resolve()
    config_dir = args.config_dir or (base_dir / "config")
    config_dir = config_dir.expanduser().resolve()

    if not base_dir.exists():
        print(f"Error: Base directory does not exist: {base_dir}")
        print("Run 'sync-shuttle.sh init' first.")
        sys.exit(1)

    try:
        app = SyncShuttleTUI(base_dir, config_dir, mode=args.mode)
        app.run()
    finally:
        reset_terminal()


if __name__ == "__main__":
    main()
