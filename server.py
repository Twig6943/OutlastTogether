#!/usr/bin/env python3

import asyncio
import json
import logging
import os
import socket
import sys
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Optional

LOG = logging.getLogger("oltogether")

DEFAULT_CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "server_config.json")

MAX_LINE_BYTES = 8192
READ_CHUNK = 4096
CLIENT_QUEUE_LIMIT = 256
CLIENT_TIMEOUT = 20.0
IDLE_CHECK_INTERVAL = 5.0

CRITICAL_PREFIXES = (b"CHAT,", b"NAME,", b"NOTIF,", b"PONG,")


def _detect_local_host() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            local_ip = sock.getsockname()[0]
            if local_ip and not local_ip.startswith("127.") and not local_ip.startswith("169.254."):
                return local_ip
    except Exception:
        pass

    try:
        for entry in socket.gethostbyname_ex(socket.gethostname())[2]:
            if entry and not entry.startswith("127.") and not entry.startswith("169.254."):
                if entry.startswith("192.168.") or entry.startswith("10.") or entry.startswith("172.16.") or entry.startswith("172.17.") or entry.startswith("172.18.") or entry.startswith("172.19.") or entry.startswith("172.2") or entry.startswith("172.3"):
                    return entry
    except Exception:
        pass

    return "127.0.0.1"


def _now() -> float:
    return time.monotonic()


def _load_config(path: str) -> dict:
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


@dataclass
class Client:
    cid: int
    writer: asyncio.StreamWriter
    address: str
    name: str = ""
    connected_at: float = field(default_factory=_now)
    last_seen: float = field(default_factory=_now)
    rx_bytes: int = 0
    tx_bytes: int = 0
    rx_msgs: int = 0
    tx_msgs: int = 0
    dropped: int = 0
    outbox: deque = field(default_factory=deque)
    wake: Optional[asyncio.Event] = None
    writer_task: Optional[asyncio.Task] = None
    closing: bool = False

    @property
    def label(self) -> str:
        return self.name or f"Player{self.cid}"

    @property
    def uptime(self) -> float:
        return _now() - self.connected_at


class BridgeServer:
    def __init__(self, app):
        self.app = app
        self.host = _detect_local_host()
        self.port = 7777
        self.server: Optional[asyncio.AbstractServer] = None
        self.loop = asyncio.new_event_loop()
        self.thread: Optional[threading.Thread] = None
        self._shutdown_future: Optional[asyncio.Future] = None
        self.clients: dict[int, Client] = {}
        self.next_client_id = 1
        self.total_connections = 0
        self.total_relayed = 0
        self.started_at = 0.0

    # ----------------------------------------------------------------- lifecycle
    def is_running(self) -> bool:
        return bool(self.thread and self.thread.is_alive())

    def start(self, host: str, port: int):
        if self.is_running():
            self.app.log("Server is already running.")
            return
        self.host = host
        self.port = port
        self.thread = threading.Thread(target=self._run_loop, daemon=True, name="oltogether-loop")
        self.thread.start()
        self.app.log(f"Starting server on {host}:{port} ...")

    def _run_loop(self):
        asyncio.set_event_loop(self.loop)
        try:
            self.loop.run_until_complete(self._async_main())
        except Exception as exc:
            self.app.log(f"Server stopped with error: {exc}")
        finally:
            try:
                pending = asyncio.all_tasks(self.loop)
                for task in pending:
                    task.cancel()
                if pending:
                    self.loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            except Exception:
                pass
            self.loop.close()
            self.app.log("Server event loop closed.")

    async def _async_main(self):
        try:
            self.server = await asyncio.start_server(
                self.handle_client, self.host, self.port, limit=MAX_LINE_BYTES
            )
        except Exception as exc:
            self.app.log(f"Failed to start server: {exc}")
            self.app.set_server_state(False)
            return

        sock = self.server.sockets[0].getsockname()
        self.started_at = _now()
        self.app.log(f"Listening on {sock[0]}:{sock[1]}")
        self.app.set_server_state(True)
        self.app.refresh_clients([])

        self._shutdown_future = self.loop.create_future()
        idle_task = self.loop.create_task(self._idle_monitor())

        try:
            async with self.server:
                await self._shutdown_future
        finally:
            idle_task.cancel()
            self.server.close()
            await self.server.wait_closed()
            await self._close_all_clients()
            self.app.set_server_state(False)
            self.app.refresh_clients([])
            self.app.log("Server stopped.")

    def stop(self):
        if not self.is_running():
            self.app.log("Server is not running.")
            return
        self._call_soon(self._shutdown)

    def _shutdown(self):
        if self._shutdown_future and not self._shutdown_future.done():
            self._shutdown_future.set_result(None)

    def _call_soon(self, fn, *args):
        if self.loop and not self.loop.is_closed():
            try:
                self.loop.call_soon_threadsafe(fn, *args)
            except RuntimeError:
                pass

    async def _idle_monitor(self):
        try:
            while True:
                await asyncio.sleep(IDLE_CHECK_INTERVAL)
                now = _now()
                stale = [c for c in self.clients.values()
                         if not c.closing and now - c.last_seen > CLIENT_TIMEOUT]
                for client in stale:
                    self.app.log(f"Timing out idle client {client.label} ({client.address}).")
                    client.closing = True
                    self._wake(client)
                    try:
                        client.writer.close()
                    except Exception:
                        pass
        except asyncio.CancelledError:
            pass

    async def _close_all_clients(self):
        for client in list(self.clients.values()):
            client.closing = True
            self._wake(client)
            try:
                client.writer.close()
            except Exception:
                pass
        for client in list(self.clients.values()):
            try:
                await client.writer.wait_closed()
            except Exception:
                pass
        self.clients.clear()

    # ----------------------------------------------------------------- connection
    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        peer = writer.get_extra_info("peername")
        address = f"{peer[0]}:{peer[1]}" if peer else "unknown"
        client = Client(cid=self.next_client_id, writer=writer, address=address)
        client.wake = asyncio.Event()
        self.next_client_id += 1
        self.total_connections += 1
        self.clients[client.cid] = client
        client.writer_task = self.loop.create_task(self._client_writer(client))

        self.app.log(f"Connected: {address} (assigned {client.label})")
        self._push_roster()

        for other in self.clients.values():
            if other.cid != client.cid and other.name:
                self.send_to(client, f"NAME,{other.name}")

        buffer = b""
        try:
            while True:
                chunk = await reader.read(READ_CHUNK)
                if not chunk:
                    break
                client.rx_bytes += len(chunk)
                client.last_seen = _now()
                buffer += chunk
                if len(buffer) > MAX_LINE_BYTES * 4:
                    buffer = buffer[-MAX_LINE_BYTES:]
                while b"\n" in buffer:
                    raw, buffer = buffer.split(b"\n", 1)
                    line = raw.decode("utf-8", "ignore").strip("\r").strip()
                    if line:
                        client.rx_msgs += 1
                        await self.process_line(line, client)
        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        except Exception as exc:
            self.app.log(f"Client {client.label} error: {exc}")
        finally:
            await self.disconnect_client(client)

    async def _client_writer(self, client: Client):
        assert client.wake is not None
        try:
            while True:
                if not client.outbox:
                    if client.closing:
                        break
                    await client.wake.wait()
                    client.wake.clear()
                    continue
                data = client.outbox.popleft()
                client.writer.write(data)
                client.tx_bytes += len(data)
                client.tx_msgs += 1
                if not client.outbox:
                    await client.writer.drain()
        except (ConnectionResetError, BrokenPipeError, asyncio.CancelledError):
            pass
        except Exception:
            pass

    async def disconnect_client(self, client: Client):
        if client.cid not in self.clients:
            return
        self.clients.pop(client.cid, None)
        client.closing = True
        self._wake(client)
        if client.writer_task:
            client.writer_task.cancel()
        try:
            client.writer.close()
            await client.writer.wait_closed()
        except Exception:
            pass
        self.app.log(f"Disconnected: {client.address} ({client.label})")
        self.broadcast(f"NOTIF,{client.label} left the server.")
        self._push_roster()

    # ----------------------------------------------------------------- protocol
    async def process_line(self, line: str, client: Client):
        if line.startswith("NAME,"):
            new_name = line[5:].strip() or client.label
            old = client.label
            client.name = new_name
            if old != new_name:
                self.app.log(f"{old} is now {new_name}")
            self.broadcast(f"NAME,{new_name}", exclude=client)
            if old != new_name and new_name != client.label:
                self.broadcast(f"NOTIF,{new_name} joined the server.", exclude=client)
            self._push_roster()
            return

        if line.startswith("PING,"):
            self.send_to(client, "PONG," + line[5:])
            return

        if line.startswith("PONG,"):
            return

        if line.startswith("NOTIF,"):
            self.broadcast(line, exclude=client)
            self.app.log(f"NOTIF: {line[6:].strip()}")
            return

        if line.startswith("CHAT,"):
            self.broadcast(line, exclude=client)
            self.app.log(f"CHAT: {line[5:].strip()}")
            return

        # Default: position / state relay (LOC and anything else).
        self.broadcast(line, exclude=client)

    # ----------------------------------------------------------------- delivery
    def send_to(self, client: Client, line: str):
        data = (line.rstrip("\n") + "\n").encode("utf-8")
        self._call_soon(self._enqueue, client, data)

    def broadcast(self, line: str, exclude: Optional[Client] = None):
        data = (line.rstrip("\n") + "\n").encode("utf-8")
        exclude_cid = exclude.cid if exclude else None
        self._call_soon(self._broadcast_now, data, exclude_cid)

    def broadcast_notification(self, message: str):
        message = message.strip()
        if message:
            self.broadcast(f"NOTIF,{message}")

    def _broadcast_now(self, data: bytes, exclude_cid: Optional[int]):
        self.total_relayed += 1
        for client in self.clients.values():
            if client.cid == exclude_cid or client.closing:
                continue
            self._enqueue(client, data)

    def _enqueue(self, client: Client, data: bytes):
        if client.closing:
            return
        outbox = client.outbox
        if len(outbox) >= CLIENT_QUEUE_LIMIT:
            self._make_room(outbox)
            client.dropped += 1
        outbox.append(data)
        self._wake(client)

    @staticmethod
    def _make_room(outbox: deque):
        for i, item in enumerate(outbox):
            if not item.startswith(CRITICAL_PREFIXES):
                del outbox[i]
                return
        outbox.popleft()

    @staticmethod
    def _wake(client: Client):
        if client.wake is not None and not client.wake.is_set():
            client.wake.set()

    # ----------------------------------------------------------------- roster / admin
    def rename_client(self, old_name: str, new_name: str):
        self._call_soon(self._do_rename, old_name, new_name)

    def _do_rename(self, old_name: str, new_name: str):
        target = next((c for c in self.clients.values() if c.label == old_name), None)
        if target is None:
            self.app.log(f"Rename failed: no client named '{old_name}'.")
            return
        target.name = new_name
        self.broadcast(f"NAME,{new_name}", exclude=target)
        self.broadcast(f"NOTIF,{new_name} joined the server.", exclude=target)
        self.app.log(f"Renamed {old_name} to {new_name}")
        self._push_roster()

    def kick_client(self, name: str):
        self._call_soon(self._do_kick, name)

    def _do_kick(self, name: str):
        target = next((c for c in self.clients.values() if c.label == name), None)
        if target is None:
            return
        self.app.log(f"Kicking {target.label} ({target.address}).")
        target.closing = True
        self._wake(target)
        try:
            target.writer.close()
        except Exception:
            pass

    def _push_roster(self):
        snapshot = [
            {
                "name": c.label,
                "address": c.address,
                "uptime": c.uptime,
                "rx": c.rx_msgs,
                "dropped": c.dropped,
            }
            for c in sorted(self.clients.values(), key=lambda x: x.cid)
        ]
        self.app.refresh_clients(snapshot)

    def stats(self) -> dict:
        uptime = _now() - self.started_at if self.started_at else 0.0
        return {
            "clients": len(self.clients),
            "connections": self.total_connections,
            "relayed": self.total_relayed,
            "uptime": uptime,
        }


class HeadlessApp:
    """Non-GUI stand-in for ServerApp. Implements the callback surface
    BridgeServer expects (log / set_server_state / refresh_clients) so the
    relay can run without Tkinter."""

    def __init__(self, server_name: str = ""):
        self.server = BridgeServer(self)
        self.server_running = False
        self.server_name = server_name.strip()

    def log(self, message: str):
        stamp = time.strftime("%H:%M:%S")
        print(f"[{stamp}] {message}")

    def set_server_state(self, running: bool):
        self.server_running = running
        if running and self.server_name:
            self.log(f"Server name: {self.server_name}")

    def refresh_clients(self, snapshot: list):
        if not snapshot:
            return
        roster = ", ".join(f"{c['name']}@{c['address']}" for c in snapshot)
        print(f"Clients ({len(snapshot)}): {roster}")

    def run(self, host: str, port: int):
        self.server.start(host, port)
        try:
            while self.server.thread and self.server.thread.is_alive():
                self.server.thread.join(timeout=1)
        except KeyboardInterrupt:
            print("\nShutting down...")
            self.server.stop()
            if self.server.thread:
                self.server.thread.join(timeout=5)


def _parse_args(argv: list) -> tuple:
    headless = False
    config_path = None
    positional = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--headless":
            headless = True
        elif arg == "--config":
            i += 1
            if i < len(argv):
                config_path = argv[i]
        elif arg.startswith("--config="):
            config_path = arg.split("=", 1)[1]
        else:
            positional.append(arg)
        i += 1
    return headless, config_path, positional


def main():
    logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(message)s", datefmt="%H:%M:%S")

    headless, config_path, args = _parse_args(sys.argv[1:])

    if headless:
        resolved_config_path = config_path or DEFAULT_CONFIG_PATH
        settings = _load_config(resolved_config_path)
        if settings:
            LOG.info(f"Loaded config from {resolved_config_path}")
        else:
            LOG.info(f"No config found at {resolved_config_path}, using defaults.")

        host = settings.get("host") or _detect_local_host()
        port = settings.get("port") or 7777
        server_name = str(settings.get("server_name", "")).strip()

        if len(args) >= 1:
            host = args[0]
        if len(args) >= 2:
            args_port = args[1]
        else:
            args_port = None

        try:
            port = int(args_port if args_port is not None else port)
        except (TypeError, ValueError):
            port = 7777

        HeadlessApp(server_name=server_name).run(host, port)
    else:
        host = _detect_local_host()
        port = 7777
        if len(args) >= 1:
            host = args[0]
        if len(args) >= 2:
            try:
                port = int(args[1])
            except ValueError:
                pass

        from gui import ServerApp
        app = ServerApp(host, port, config_path=config_path)
        app.mainloop()


if __name__ == "__main__":
    main()
