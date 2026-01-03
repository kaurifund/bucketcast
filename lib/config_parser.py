#!/usr/bin/env python3
"""
Sync Shuttle - TOML Configuration Parser

Parses and modifies servers.toml.

Usage:
    python3 config_parser.py <config_file> list
    python3 config_parser.py <config_file> list-detail
    python3 config_parser.py <config_file> get <server_id>
    python3 config_parser.py <config_file> get-field <server_id> <field>
    python3 config_parser.py <config_file> set <server_id> <field> <value>
    python3 config_parser.py <config_file> add <server_id>
    python3 config_parser.py <config_file> remove <server_id>
    python3 config_parser.py <config_file> json [server_id]
"""

import sys
import json
import re
from pathlib import Path

# Python 3.11+ has tomllib built-in
try:
    import tomllib
except ImportError:
    # Fallback for Python 3.10 and earlier
    try:
        import tomli as tomllib
    except ImportError:
        print("ERROR: TOML support not available.", file=sys.stderr)
        print("Fix: ~/.local/share/sync-shuttle/.venv/bin/pip install tomli", file=sys.stderr)
        sys.exit(1)


def load_config(config_path: Path) -> dict:
    """Load and parse TOML config file."""
    if not config_path.exists():
        print(f"ERROR: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path, "rb") as f:
        return tomllib.load(f)


def list_servers(config: dict) -> None:
    """Output list of server IDs, one per line."""
    servers = config.get("servers", {})
    for server_id in servers:
        print(server_id)


def get_server_bash(config: dict, server_id: str) -> None:
    """Output server config as bash variables."""
    servers = config.get("servers", {})

    if server_id not in servers:
        print(f"ERROR: Server not found: {server_id}", file=sys.stderr)
        sys.exit(1)

    server = servers[server_id]

    # Check if enabled
    if not server.get("enabled", False):
        print(f"ERROR: Server is disabled: {server_id}", file=sys.stderr)
        sys.exit(1)

    # Output bash variables
    # Escape single quotes in values
    def escape(val):
        if val is None:
            return ""
        return str(val).replace("'", "'\\''")

    user = server.get('user', '')
    # Default remote_base to user's home .sync-shuttle directory
    default_remote_base = f"/home/{user}/.sync-shuttle" if user else ""
    remote_base = server.get('remote_base') or default_remote_base

    print(f"server_name='{escape(server.get('name', server_id))}'")
    print(f"server_host='{escape(server.get('host', ''))}'")
    print(f"server_port='{escape(server.get('port', 22))}'")
    print(f"server_user='{escape(user)}'")
    print(f"server_identity_file='{escape(server.get('identity_file', ''))}'")
    print(f"server_remote_base='{escape(remote_base)}'")
    print(f"server_s3_backup='{escape(str(server.get('s3_backup', False)).lower())}'")


def get_server_json(config: dict, server_id: str = None) -> None:
    """Output server config(s) as JSON."""
    servers = config.get("servers", {})

    if server_id:
        if server_id not in servers:
            print(f"ERROR: Server not found: {server_id}", file=sys.stderr)
            sys.exit(1)
        output = {server_id: servers[server_id]}
    else:
        output = servers

    print(json.dumps(output, indent=2))


def list_servers_detail(config: dict) -> None:
    """Output formatted server list for display."""
    servers = config.get("servers", {})

    if not servers:
        print("NO_SERVERS")
        return

    for server_id, server in servers.items():
        enabled = server.get("enabled", False)
        status = "enabled" if enabled else "disabled"
        name = server.get("name", server_id)
        user = server.get("user", "?")
        host = server.get("host", "?")
        port = server.get("port", 22)

        # Output in a parseable format: status|id|user|host|port|name
        print(f"{status}|{server_id}|{user}|{host}|{port}|{name}")


def get_field(config: dict, server_id: str, field: str) -> None:
    """Get a single field value from a server config."""
    servers = config.get("servers", {})

    if server_id not in servers:
        print(f"ERROR: Server not found: {server_id}", file=sys.stderr)
        sys.exit(1)

    server = servers[server_id]
    value = server.get(field)

    if value is None:
        print(f"ERROR: Field not found: {field}", file=sys.stderr)
        sys.exit(1)

    print(value)


def write_toml(config: dict, config_path: Path) -> None:
    """Write config back to TOML file."""
    lines = ["# Sync Shuttle - Server Configuration", ""]

    servers = config.get("servers", {})
    for server_id, server in servers.items():
        lines.append(f"[servers.{server_id}]")
        for key, value in server.items():
            if isinstance(value, bool):
                lines.append(f"{key} = {str(value).lower()}")
            elif isinstance(value, int):
                lines.append(f"{key} = {value}")
            elif isinstance(value, str):
                lines.append(f'{key} = "{value}"')
        lines.append("")

    config_path.write_text("\n".join(lines))


def set_field(config: dict, config_path: Path, server_id: str, field: str, value: str) -> None:
    """Set a field value in a server config."""
    if "servers" not in config:
        config["servers"] = {}

    servers = config["servers"]

    if server_id not in servers:
        print(f"ERROR: Server not found: {server_id}", file=sys.stderr)
        print(f"Use 'add {server_id}' to create it first", file=sys.stderr)
        sys.exit(1)

    # Type conversion
    if value.lower() == "true":
        value = True
    elif value.lower() == "false":
        value = False
    elif value.isdigit():
        value = int(value)

    servers[server_id][field] = value
    write_toml(config, config_path)
    print(f"Set {server_id}.{field} = {value}")


def add_server(config: dict, config_path: Path, server_id: str) -> None:
    """Add a new server with default values."""
    if "servers" not in config:
        config["servers"] = {}

    servers = config["servers"]

    if server_id in servers:
        print(f"ERROR: Server already exists: {server_id}", file=sys.stderr)
        sys.exit(1)

    # Validate server ID format
    if not re.match(r'^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$', server_id):
        print(f"ERROR: Invalid server ID: {server_id}", file=sys.stderr)
        print("Must be 3-32 chars, lowercase alphanumeric with dashes", file=sys.stderr)
        sys.exit(1)

    servers[server_id] = {
        "name": server_id,
        "host": "",
        "port": 22,
        "user": "",
        "remote_base": "",
        "enabled": False,
        "s3_backup": False,
    }

    write_toml(config, config_path)
    print(f"Added server: {server_id}")
    print(f"Configure with: sync-shuttle config set {server_id} host <ip>")


def remove_server(config: dict, config_path: Path, server_id: str) -> None:
    """Remove a server from config."""
    servers = config.get("servers", {})

    if server_id not in servers:
        print(f"ERROR: Server not found: {server_id}", file=sys.stderr)
        sys.exit(1)

    del servers[server_id]
    write_toml(config, config_path)
    print(f"Removed server: {server_id}")


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    config_path = Path(sys.argv[1])
    command = sys.argv[2]

    config = load_config(config_path)

    if command == "list":
        list_servers(config)
    elif command == "list-detail":
        list_servers_detail(config)
    elif command == "get":
        if len(sys.argv) < 4:
            print("ERROR: 'get' requires a server_id", file=sys.stderr)
            sys.exit(2)
        get_server_bash(config, sys.argv[3])
    elif command == "get-field":
        if len(sys.argv) < 5:
            print("ERROR: 'get-field' requires server_id and field", file=sys.stderr)
            sys.exit(2)
        get_field(config, sys.argv[3], sys.argv[4])
    elif command == "set":
        if len(sys.argv) < 6:
            print("ERROR: 'set' requires server_id, field, and value", file=sys.stderr)
            sys.exit(2)
        set_field(config, config_path, sys.argv[3], sys.argv[4], sys.argv[5])
    elif command == "add":
        if len(sys.argv) < 4:
            print("ERROR: 'add' requires a server_id", file=sys.stderr)
            sys.exit(2)
        add_server(config, config_path, sys.argv[3])
    elif command == "remove":
        if len(sys.argv) < 4:
            print("ERROR: 'remove' requires a server_id", file=sys.stderr)
            sys.exit(2)
        remove_server(config, config_path, sys.argv[3])
    elif command == "json":
        server_id = sys.argv[3] if len(sys.argv) > 3 else None
        get_server_json(config, server_id)
    else:
        print(f"ERROR: Unknown command: {command}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
