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
# MAIN APPLICATION
# =============================================================================

class SyncShuttleTUI(App):
    """Main Sync Shuttle TUI application."""
    
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
    """
    
    TITLE = "Sync Shuttle"
    SUB_TITLE = "Safe File Synchronization"
    
    def __init__(self, base_dir: Path, config_dir: Path):
        super().__init__()
        self.base_dir = base_dir
        self.config_dir = config_dir
    
    def on_mount(self) -> None:
        self.push_screen(MainScreen(self.base_dir, self.config_dir))


# =============================================================================
# ENTRY POINT
# =============================================================================

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
    
    args = parser.parse_args()
    
    base_dir = args.base_dir.expanduser().resolve()
    config_dir = args.config_dir or (base_dir / "config")
    config_dir = config_dir.expanduser().resolve()
    
    if not base_dir.exists():
        print(f"Error: Base directory does not exist: {base_dir}")
        print("Run 'sync-shuttle.sh init' first.")
        sys.exit(1)
    
    app = SyncShuttleTUI(base_dir, config_dir)
    app.run()


if __name__ == "__main__":
    main()
