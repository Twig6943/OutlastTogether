import asyncio
import json
import logging
import os
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(message)s", datefmt="%H:%M:%S")

class BridgeServer:
    def __init__(self, app):
        self.app = app
        self.host = "127.0.0.1"
        self.port = 7777
        self.server = None
        self.loop = asyncio.new_event_loop()
        self.thread = None
        self._shutdown_future = None
        self.clients = {}
        self.next_client_id = 1

    def start(self, host: str, port: int):
        if self.thread and self.thread.is_alive():
            self.app.log("Server is already running.")
            return

        self.host = host
        self.port = port
        self.thread = threading.Thread(target=self._run_loop, daemon=True)
        self.thread.start()
        self.app.log(f"Starting server on {host}:{port}...")

    def _run_loop(self):
        asyncio.set_event_loop(self.loop)
        try:
            self.loop.run_until_complete(self._async_main())
        except Exception as exc:
            self.app.log(f"Server stopped with error: {exc}")
        finally:
            self.loop.close()
            self.app.log("Server event loop closed.")

    async def _async_main(self):
        try:
            self.server = await asyncio.start_server(self.handle_client, self.host, self.port)
        except Exception as exc:
            self.app.log(f"Failed to start server: {exc}")
            return

        address = self.server.sockets[0].getsockname()
        self.app.log(f"Listening on {address[0]}:{address[1]}")
        self.app.set_server_state(True)

        self._shutdown_future = self.loop.create_future()
        async with self.server:
            await self._shutdown_future
            self.server.close()
            await self.server.wait_closed()

        for writer in list(self.clients.keys()):
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass
        self.clients.clear()
        self.app.set_server_state(False)
        self.app.log("Server stopped.")

    def stop(self):
        if not self.thread or not self.thread.is_alive():
            self.app.log("Server is not running.")
            return
        if self.loop.is_closed():
            return
        self.loop.call_soon_threadsafe(self._shutdown)

    def _shutdown(self):
        if self._shutdown_future and not self._shutdown_future.done():
            self._shutdown_future.set_result(None)

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        addr = writer.get_extra_info("peername")
        client_id = f"Player{self.next_client_id}"
        self.next_client_id += 1
        self.clients[writer] = client_id
        self.app.add_client(client_id)
        self.app.log(f"Connected: {addr}")
        self.broadcast_notification(f"{client_id} connected.")

        try:
            while True:
                data = await reader.read(1024)
                if not data:
                    break
                text = data.decode("utf-8", "ignore")
                for line in text.splitlines():
                    await self.process_line(line.strip(), writer)
        except asyncio.IncompleteReadError:
            pass
        except ConnectionResetError:
            self.app.log(f"Disconnected: {addr}")
        finally:
            await self.disconnect_client(writer)

    async def process_line(self, line: str, writer: asyncio.StreamWriter):
        if not line:
            return

        if line.startswith("NAME,"):
            name = line[5:].strip()
            if name == "":
                name = self.clients.get(writer, "Unknown")
            old_name = self.clients.get(writer, "Unknown")
            self.clients[writer] = name
            self.app.update_client(old_name, name)
            self.app.log(f"{old_name} is now {name}")
            self.broadcast(f"NAME,{name}", exclude=writer)
            self.broadcast_notification(f"{name} joined the server.")
            return

        if line.startswith("PING," ):
            payload = line[5:]
            try:
                writer.write(("PONG," + payload + "\n").encode("utf-8"))
                await writer.drain()
            except Exception:
                pass
            return

        if line.startswith("NOTIF," ):
            notification = line[6:].strip()
            self.broadcast(line, exclude=writer)
            self.app.log(f"NOTIF: {notification}")
            return

        if line.startswith("CHAT," ):
            self.broadcast(line, exclude=writer)
            self.app.log(f"CHAT: {line[5:].strip()}")
            return

        self.broadcast(line, exclude=writer)

    async def disconnect_client(self, writer: asyncio.StreamWriter):
        name = self.clients.pop(writer, "Unknown")
        self.app.remove_client(name)
        self.broadcast(f"NOTIF,{name} left the server.")
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass

    def rename_client(self, old_name: str, new_name: str) -> bool:
        for writer, name in self.clients.items():
            if name == old_name:
                self.clients[writer] = new_name
                self.app.update_client(old_name, new_name)
                self.broadcast_notification(f"{new_name} joined.")
                return True
        return False

    def broadcast(self, line: str, exclude: asyncio.StreamWriter = None):
        data = (line + "\n").encode("utf-8")
        for client in list(self.clients.keys()):
            if client == exclude:
                continue
            try:
                client.write(data)
                asyncio.run_coroutine_threadsafe(client.drain(), self.loop)
            except Exception:
                pass

    def broadcast_notification(self, message: str):
        self.broadcast(f"NOTIF,{message}")


class ServerApp(tk.Tk):
    def __init__(self, host: str = "127.0.0.1", port: int = 7777):
        super().__init__()
        self.title("OLTogether Relay Server")
        self.resizable(False, False)
        self.server = BridgeServer(self)

        self.host_var = tk.StringVar(value=host)
        self.port_var = tk.StringVar(value=str(port))
        self.name_var = tk.StringVar(value="Player")
        self.rename_var = tk.StringVar(value="")
        self.game_path_var = tk.StringVar(value="")
        self.notification_var = tk.StringVar(value="")
        self.server_running = False
        self.config_path = os.path.join(os.path.dirname(__file__), "server_config.json")

        self._load_settings()
        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self):
        self.style = ttk.Style(self)
        try:
            self.style.theme_use('clam')
        except Exception:
            pass
        self.style.configure('Dark.TFrame', background='#2b2b2b')
        self.style.configure('Dark.TLabel', background='#2b2b2b', foreground='#f0f0f0')
        self.style.configure('Dark.TButton', background='#3a3a3a', foreground='#f0f0f0')
        self.style.configure('Dark.TEntry', fieldbackground='#3a3a3a', foreground='#ffffff')

        self.configure(background='#2b2b2b')
        main_frame = ttk.Frame(self, style='Dark.TFrame', padding=12)
        main_frame.grid(row=0, column=0, sticky="nsew")

        header = ttk.Label(main_frame, text="OLTogether Server Bridge", font=("Segoe UI", 14, "bold"), style='Dark.TLabel')
        header.grid(row=0, column=0, columnspan=5, pady=(0, 12), sticky="w")

        ttk.Label(main_frame, text="Host:", style='Dark.TLabel').grid(row=1, column=0, sticky="e")
        ttk.Entry(main_frame, textvariable=self.host_var, width=16).grid(row=1, column=1, sticky="w")
        ttk.Button(main_frame, text="Localhost", command=self.set_localhost, style='Dark.TButton').grid(row=1, column=2, padx=(8, 0), pady=0, sticky="w")
        ttk.Label(main_frame, text="Port:", style='Dark.TLabel').grid(row=1, column=3, sticky="e")
        ttk.Entry(main_frame, textvariable=self.port_var, width=8).grid(row=1, column=4, sticky="w")

        ttk.Label(main_frame, text="Player Name:", style='Dark.TLabel').grid(row=2, column=0, sticky="e")
        ttk.Entry(main_frame, textvariable=self.name_var, width=20).grid(row=2, column=1, columnspan=2, sticky="w")

        ttk.Label(main_frame, text="Game EXE Path:", style='Dark.TLabel').grid(row=3, column=0, sticky="e")
        ttk.Entry(main_frame, textvariable=self.game_path_var, width=44).grid(row=3, column=1, columnspan=3, sticky="w")
        ttk.Button(main_frame, text="Browse...", command=self._browse_game_path, style='Dark.TButton').grid(row=3, column=4, sticky="w")

        button_frame = ttk.Frame(main_frame, style='Dark.TFrame')
        button_frame.grid(row=4, column=0, columnspan=5, pady=(10, 8), sticky="ew")
        ttk.Button(button_frame, text="Start Server", command=self.start_server, style='Dark.TButton').grid(row=0, column=0, padx=4)
        ttk.Button(button_frame, text="Stop Server", command=self.stop_server, style='Dark.TButton').grid(row=0, column=1, padx=4)
        ttk.Button(button_frame, text="Send Notification", command=self.send_notification, style='Dark.TButton').grid(row=0, column=2, padx=4)

        launch_frame = ttk.LabelFrame(main_frame, text="Game Launcher", padding=8, style='Dark.TFrame')
        launch_frame.grid(row=5, column=0, columnspan=5, pady=(0, 10), sticky="ew")
        ttk.Button(launch_frame, text="Launch Host", command=lambda: self.launch_game(0), style='Dark.TButton').grid(row=0, column=0, padx=4, pady=2)
        ttk.Button(launch_frame, text="Launch Joiner", command=lambda: self.launch_game(1), style='Dark.TButton').grid(row=0, column=1, padx=4, pady=2)
        ttk.Label(launch_frame, text="The game launcher automatically passes the in-game player name.", style='Dark.TLabel').grid(row=1, column=0, columnspan=2, sticky="w", pady=(4,0))

        status_frame = ttk.LabelFrame(main_frame, text="Server Log", padding=8, style='Dark.TFrame')
        status_frame.grid(row=6, column=0, columnspan=5, sticky="nsew")

        self.log_text = scrolledtext.ScrolledText(status_frame, width=76, height=14, state="disabled", wrap="word", bg="#1f1f1f", fg="#ffffff", insertbackground="#ffffff")
        self.log_text.grid(row=0, column=0, sticky="nsew")

        self.client_list = tk.Listbox(status_frame, height=6, width=32, bg="#1f1f1f", fg="#ffffff", selectbackground="#4b4b4b", bd=0)
        self.client_list.grid(row=0, column=1, padx=(8, 0), sticky="ns")
        status_frame.columnconfigure(0, weight=1)
        status_frame.rowconfigure(0, weight=1)

        self.notification_entry = ttk.Entry(main_frame, textvariable=self.notification_var, width=60)
        self.notification_entry.grid(row=7, column=0, columnspan=3, pady=(0, 8), sticky="w")

        ttk.Button(main_frame, text="Send Notification", command=self.send_notification, style='Dark.TButton').grid(row=7, column=3, sticky="e")
        ttk.Label(main_frame, text="Rename selected user:", style='Dark.TLabel').grid(row=8, column=0, sticky="e")
        ttk.Entry(main_frame, textvariable=self.rename_var, width=20).grid(row=8, column=1, columnspan=2, sticky="w")
        ttk.Button(main_frame, text="Rename", command=self.rename_selected_client, style='Dark.TButton').grid(row=8, column=3, sticky="w")

    def _load_settings(self):
        if not os.path.exists(self.config_path):
            return
        try:
            with open(self.config_path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
            if isinstance(data, dict):
                game_path = data.get("game_path", "")
                if isinstance(game_path, str) and game_path.strip():
                    self.game_path_var.set(game_path.strip())
        except Exception:
            pass

    def _save_settings(self):
        data = {
            "game_path": self.game_path_var.get().strip()
        }
        try:
            with open(self.config_path, "w", encoding="utf-8") as handle:
                json.dump(data, handle, indent=2)
        except Exception:
            pass

    def _browse_game_path(self):
        path = filedialog.askopenfilename(title="Select Game Executable", filetypes=[("Executable", "*.exe"), ("All Files", "*")])
        if path:
            self.game_path_var.set(path)
            self._save_settings()

    def start_server(self):
        try:
            host = self.host_var.get().strip() or "127.0.0.1"
            port = int(self.port_var.get().strip() or 7777)
        except ValueError:
            messagebox.showwarning("Invalid Port", "Port must be a number.")
            return

        self.server.start(host, port)

    def set_localhost(self):
        self.host_var.set("127.0.0.1")
        self.port_var.set("7777")

    def stop_server(self):
        self.server.stop()

    def send_notification(self):
        notification = self.notification_var.get().strip()
        if notification == "":
            return
        self.server.broadcast_notification(notification)
        self.log(f"Server notification: {notification}")
        self.notification_var.set("")

    def rename_selected_client(self):
        selected = self.client_list.curselection()
        if not selected:
            messagebox.showwarning("No selection", "Select a client to rename.")
            return
        old_name = self.client_list.get(selected[0])
        new_name = self.rename_var.get().strip()
        if new_name == "":
            messagebox.showwarning("Invalid name", "Enter a new name.")
            return
        if old_name == new_name:
            return
        if self.server.rename_client(old_name, new_name):
            self.log(f"Renamed {old_name} to {new_name}")
            self.rename_var.set("")
        else:
            messagebox.showwarning("Rename failed", "Could not find the selected client.")

    def launch_game(self, role: int):
        game_path = self.game_path_var.get().strip()
        if not game_path or not os.path.isfile(game_path):
            messagebox.showwarning("Missing Game Path", "Please choose a valid game executable path.")
            return

        player_name = self.name_var.get().strip() or ("HostPlayer" if role == 0 else "ClientPlayer")
        self._save_settings()
        url = f"Intro_Persistent?game=Multiplayer.OLTogetherGame?Role={role}?ServerIP={self.host_var.get().strip() or '127.0.0.1'}?ServerPort={self.port_var.get().strip() or '7777'}?PlayerName={player_name}?QuickPlay"
        try:
            subprocess.Popen([game_path, url])
            self.log(f"Launched game role={role} name={player_name}")
        except Exception as exc:
            messagebox.showerror("Launch Failed", f"Failed to launch game: {exc}")

    def log(self, message: str):
        self.after(0, self._append_log, message)

    def _append_log(self, message: str):
        self.log_text.configure(state="normal")
        self.log_text.insert("end", message + "\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def add_client(self, client_id: str):
        self.after(0, lambda: self.client_list.insert("end", client_id))

    def update_client(self, old_name: str, new_name: str):
        def update():
            for index in range(self.client_list.size()):
                if self.client_list.get(index) == old_name:
                    self.client_list.delete(index)
                    self.client_list.insert(index, new_name)
                    return
            self.client_list.insert("end", new_name)
        self.after(0, update)

    def remove_client(self, client_id: str):
        def remove():
            values = list(self.client_list.get(0, "end"))
            if client_id in values:
                self.client_list.delete(values.index(client_id))
        self.after(0, remove)

    def set_server_state(self, running: bool):
        self.server_running = running

    def _on_close(self):
        if self.server_running:
            self.server.stop()
        self.destroy()


def main():
    host = "127.0.0.1"
    port = 7777
    if len(sys.argv) >= 2:
        host = sys.argv[1]
    if len(sys.argv) >= 3:
        try:
            port = int(sys.argv[2])
        except ValueError:
            pass

    app = ServerApp(host, port)
    app.mainloop()


if __name__ == "__main__":
    main()
