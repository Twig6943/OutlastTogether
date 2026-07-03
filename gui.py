import json
import os
import subprocess
import sys
import time
from typing import Optional
from urllib.parse import quote

import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

from server import LOG, BridgeServer, _detect_local_host


class ServerApp(tk.Tk):
    def __init__(self, host: str = "", port: int = 7777, config_path: Optional[str] = None):
        super().__init__()
        self.title("OLTogether Relay Server")
        self.minsize(760, 560)
        self.server = BridgeServer(self)

        self.host_var = tk.StringVar(value=host or _detect_local_host())
        self.port_var = tk.StringVar(value=str(port))
        self.name_var = tk.StringVar(value="Player")
        self.rename_var = tk.StringVar(value="")
        self.game_path_var = tk.StringVar(value="")
        self.notification_var = tk.StringVar(value="")
        self.status_var = tk.StringVar(value="Stopped")
        self.stats_var = tk.StringVar(value="No clients connected.")
        self.server_running = False
        self.config_path = config_path or os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "server_config.json"
        )

        self._load_settings()
        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self._tick_stats()

    # ----------------------------------------------------------------- UI
    def _build_ui(self):
        self.style = ttk.Style(self)
        try:
            self.style.theme_use("clam")
        except Exception:
            pass

        bg = "#23262b"
        panel = "#2b2f36"
        fg = "#e6e6e6"
        accent = "#3a3f47"
        self.configure(background=bg)
        self.style.configure("Dark.TFrame", background=bg)
        self.style.configure("Panel.TLabelframe", background=panel, foreground=fg, bordercolor=accent)
        self.style.configure("Panel.TLabelframe.Label", background=panel, foreground="#9fd0ff")
        self.style.configure("Dark.TLabel", background=bg, foreground=fg)
        self.style.configure("Panel.TLabel", background=panel, foreground=fg)
        self.style.configure("Dark.TButton", background=accent, foreground=fg, borderwidth=0, padding=6)
        self.style.map("Dark.TButton",
                       background=[("active", "#4a515b"), ("disabled", "#2a2d31")],
                       foreground=[("disabled", "#777")])
        self.style.configure("Accent.TButton", background="#2f6f4f", foreground="#ffffff", padding=6)
        self.style.map("Accent.TButton", background=[("active", "#37855f"), ("disabled", "#2a2d31")])
        self.style.configure("Danger.TButton", background="#7a3b3b", foreground="#ffffff", padding=6)
        self.style.map("Danger.TButton", background=[("active", "#8f4646"), ("disabled", "#2a2d31")])

        root = ttk.Frame(self, style="Dark.TFrame", padding=12)
        root.grid(row=0, column=0, sticky="nsew")
        self.columnconfigure(0, weight=1)
        self.rowconfigure(0, weight=1)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(4, weight=1)

        header = ttk.Frame(root, style="Dark.TFrame")
        header.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        header.columnconfigure(1, weight=1)
        ttk.Label(header, text="OLTogether Server Bridge", font=("Segoe UI", 15, "bold"),
                  style="Dark.TLabel").grid(row=0, column=0, sticky="w")
        self.status_dot = tk.Canvas(header, width=14, height=14, highlightthickness=0, bg=bg)
        self.status_dot.grid(row=0, column=2, padx=(0, 6))
        self._dot = self.status_dot.create_oval(2, 2, 12, 12, fill="#c0392b", outline="")
        ttk.Label(header, textvariable=self.status_var, style="Dark.TLabel",
                  font=("Segoe UI", 10, "bold")).grid(row=0, column=3, sticky="e")

        conn = ttk.LabelFrame(root, text="Connection", style="Panel.TLabelframe", padding=10)
        conn.grid(row=1, column=0, sticky="ew", pady=(0, 8))
        for c in (1, 4):
            conn.columnconfigure(c, weight=0)
        ttk.Label(conn, text="Host:", style="Panel.TLabel").grid(row=0, column=0, sticky="e", padx=4, pady=3)
        ttk.Entry(conn, textvariable=self.host_var, width=16).grid(row=0, column=1, sticky="w")
        ttk.Button(conn, text="Localhost", command=self.set_localhost, style="Dark.TButton").grid(row=0, column=2, padx=6)
        ttk.Label(conn, text="Port:", style="Panel.TLabel").grid(row=0, column=3, sticky="e", padx=4)
        ttk.Entry(conn, textvariable=self.port_var, width=8).grid(row=0, column=4, sticky="w")
        ttk.Label(conn, text="Player Name:", style="Panel.TLabel").grid(row=1, column=0, sticky="e", padx=4, pady=3)
        ttk.Entry(conn, textvariable=self.name_var, width=20).grid(row=1, column=1, columnspan=2, sticky="w")

        self.start_btn = ttk.Button(conn, text="Start Server", command=self.start_server, style="Accent.TButton")
        self.start_btn.grid(row=1, column=3, padx=4, sticky="ew")
        self.stop_btn = ttk.Button(conn, text="Stop Server", command=self.stop_server, style="Danger.TButton", state="disabled")
        self.stop_btn.grid(row=1, column=4, padx=4, sticky="ew")

        launch = ttk.LabelFrame(root, text="Game Launcher", style="Panel.TLabelframe", padding=10)
        launch.grid(row=2, column=0, sticky="ew", pady=(0, 8))
        launch.columnconfigure(1, weight=1)
        ttk.Label(launch, text="Game EXE:", style="Panel.TLabel").grid(row=0, column=0, sticky="e", padx=4)
        ttk.Entry(launch, textvariable=self.game_path_var).grid(row=0, column=1, sticky="ew", padx=4)
        ttk.Button(launch, text="Browse...", command=self._browse_game_path, style="Dark.TButton").grid(row=0, column=2, padx=4)
        btns = ttk.Frame(launch, style="Dark.TFrame")
        btns.grid(row=1, column=0, columnspan=3, sticky="w", pady=(6, 0))
        ttk.Button(btns, text="Launch Host", command=lambda: self.launch_game(0), style="Dark.TButton").grid(row=0, column=0, padx=(0, 6))
        ttk.Button(btns, text="Launch Joiner", command=lambda: self.launch_game(1), style="Dark.TButton").grid(row=0, column=1, padx=6)
        ttk.Label(btns, text="Player name is passed to the game automatically.",
                  style="Panel.TLabel").grid(row=0, column=2, padx=10)

        admin = ttk.LabelFrame(root, text="Broadcast & Admin", style="Panel.TLabelframe", padding=10)
        admin.grid(row=3, column=0, sticky="ew", pady=(0, 8))
        admin.columnconfigure(1, weight=1)
        ttk.Label(admin, text="Notify:", style="Panel.TLabel").grid(row=0, column=0, sticky="e", padx=4)
        entry = ttk.Entry(admin, textvariable=self.notification_var)
        entry.grid(row=0, column=1, sticky="ew", padx=4)
        entry.bind("<Return>", lambda _e: self.send_notification())
        ttk.Button(admin, text="Send", command=self.send_notification, style="Dark.TButton").grid(row=0, column=2, padx=4)
        ttk.Label(admin, text="Rename:", style="Panel.TLabel").grid(row=1, column=0, sticky="e", padx=4, pady=(6, 0))
        ttk.Entry(admin, textvariable=self.rename_var, width=20).grid(row=1, column=1, sticky="w", padx=4, pady=(6, 0))
        ra = ttk.Frame(admin, style="Dark.TFrame")
        ra.grid(row=1, column=2, sticky="e", pady=(6, 0))
        ttk.Button(ra, text="Rename", command=self.rename_selected_client, style="Dark.TButton").grid(row=0, column=0, padx=2)
        ttk.Button(ra, text="Kick", command=self.kick_selected_client, style="Danger.TButton").grid(row=0, column=1, padx=2)

        body = ttk.Frame(root, style="Dark.TFrame")
        body.grid(row=4, column=0, sticky="nsew")
        body.columnconfigure(0, weight=1)
        body.columnconfigure(1, weight=0)
        body.rowconfigure(0, weight=1)

        log_frame = ttk.LabelFrame(body, text="Server Log", style="Panel.TLabelframe", padding=6)
        log_frame.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)
        self.log_text = scrolledtext.ScrolledText(log_frame, width=64, height=16, state="disabled",
                                                   wrap="word", bg="#181a1e", fg="#e6e6e6",
                                                   insertbackground="#e6e6e6", relief="flat")
        self.log_text.grid(row=0, column=0, sticky="nsew")
        ttk.Button(log_frame, text="Clear Log", command=self._clear_log, style="Dark.TButton").grid(row=1, column=0, sticky="e", pady=(6, 0))

        client_frame = ttk.LabelFrame(body, text="Clients", style="Panel.TLabelframe", padding=6)
        client_frame.grid(row=0, column=1, sticky="nsew")
        client_frame.rowconfigure(0, weight=1)
        self.client_list = tk.Listbox(client_frame, height=12, width=34, bg="#181a1e", fg="#e6e6e6",
                                       selectbackground="#3a5a7a", bd=0, relief="flat",
                                       activestyle="none", font=("Consolas", 9))
        self.client_list.grid(row=0, column=0, sticky="nsew")

        self.status_bar = ttk.Label(root, textvariable=self.stats_var, style="Dark.TLabel",
                                     anchor="w", font=("Segoe UI", 9))
        self.status_bar.grid(row=5, column=0, sticky="ew", pady=(8, 0))

    # ----------------------------------------------------------------- settings
    def _load_settings(self):
        if not os.path.exists(self.config_path):
            return
        try:
            with open(self.config_path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
            if isinstance(data, dict):
                gp = data.get("game_path", "")
                if isinstance(gp, str) and gp.strip():
                    self.game_path_var.set(gp.strip())
                name = data.get("player_name", "")
                if isinstance(name, str) and name.strip():
                    self.name_var.set(name.strip())
                host = data.get("host", "")
                if isinstance(host, str) and host.strip():
                    self.host_var.set(host.strip())
                port = data.get("port", "")
                if port:
                    self.port_var.set(str(port))
        except Exception:
            pass

    def _save_settings(self):
        data = {
            "game_path": self.game_path_var.get().strip(),
            "player_name": self.name_var.get().strip(),
            "host": self.host_var.get().strip(),
            "port": self.port_var.get().strip(),
        }
        try:
            with open(self.config_path, "w", encoding="utf-8") as handle:
                json.dump(data, handle, indent=2)
        except Exception:
            pass

    def _browse_game_path(self):
        path = filedialog.askopenfilename(title="Select Game Executable",
                                          filetypes=[("Executable", "*.exe"), ("All Files", "*")])
        if path:
            self.game_path_var.set(path)
            self._save_settings()

    # ----------------------------------------------------------------- actions
    def start_server(self):
        host = self.host_var.get().strip() or _detect_local_host()
        try:
            port = int(self.port_var.get().strip() or "7777")
        except ValueError:
            messagebox.showwarning("Invalid Port", "Port must be a number.")
            return
        if not (0 < port < 65536):
            messagebox.showwarning("Invalid Port", "Port must be between 1 and 65535.")
            return
        self._save_settings()
        self.server.start(host, port)

    def set_localhost(self):
        self.host_var.set(_detect_local_host())
        self.port_var.set("7777")

    def stop_server(self):
        self.server.stop()

    def send_notification(self):
        message = self.notification_var.get().strip()
        if not message:
            return
        if not self.server_running:
            messagebox.showinfo("Not running", "Start the server before sending notifications.")
            return
        self.server.broadcast_notification(message)
        self.log(f"Server notification: {message}")
        self.notification_var.set("")

    def _selected_client_name(self) -> Optional[str]:
        selected = self.client_list.curselection()
        if not selected:
            return None
        entry = self.client_list.get(selected[0])
        return entry.split("  ", 1)[0].strip()

    def rename_selected_client(self):
        old_name = self._selected_client_name()
        if not old_name:
            messagebox.showwarning("No selection", "Select a client to rename.")
            return
        new_name = self.rename_var.get().strip()
        if not new_name:
            messagebox.showwarning("Invalid name", "Enter a new name.")
            return
        if old_name == new_name:
            return
        self.server.rename_client(old_name, new_name)
        self.rename_var.set("")

    def kick_selected_client(self):
        name = self._selected_client_name()
        if not name:
            messagebox.showwarning("No selection", "Select a client to kick.")
            return
        if messagebox.askyesno("Kick client", f"Disconnect {name}?"):
            self.server.kick_client(name)

    def launch_game(self, role: int):
        if not sys.platform.startswith("win"):
            messagebox.showwarning("Game Launch not supported yet", "Platforms other than windows cannot launch the game automatically yet.")
            return

        game_path = self.game_path_var.get().strip()
        if not game_path or not os.path.isfile(game_path):
            messagebox.showwarning("Missing Game Path", "Please choose a valid game executable path.")
            return
        player_name = self.name_var.get().strip() or ("HostPlayer" if role == 0 else "ClientPlayer")
        host = self.host_var.get().strip() or _detect_local_host()
        port = self.port_var.get().strip() or "7777"
        self._save_settings()
        url = (f"Intro_Persistent?game=Multiplayer.OLTogetherGame?Role={role}"
               f"?ServerIP={quote(host, safe='')}?ServerPort={port}?PlayerName={quote(player_name, safe='')}?QuickPlay")
        try:
            launch_args = [game_path, url]
            launch_args.append("-log")
            subprocess.Popen(launch_args)
            self.log(f"Launched game role={role} name={player_name}")
        except Exception as exc:
            messagebox.showerror("Launch Failed", f"Failed to launch game: {exc}")

    # ----------------------------------------------------------------- callbacks (thread-safe)
    def log(self, message: str):
        LOG.info(message)
        self.after(0, self._append_log, message)

    def _append_log(self, message: str):
        stamp = time.strftime("%H:%M:%S")
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"[{stamp}] {message}\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def _clear_log(self):
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.configure(state="disabled")

    def refresh_clients(self, snapshot: list):
        self.after(0, self._refresh_clients, snapshot)

    def _refresh_clients(self, snapshot: list):
        previous = self._selected_client_name()
        self.client_list.delete(0, "end")
        for info in snapshot:
            up = int(info.get("uptime", 0))
            line = f"{info['name']}  ({info['address']})  {up}s"
            self.client_list.insert("end", line)
            if info["name"] == previous:
                self.client_list.selection_set("end")

    def set_server_state(self, running: bool):
        self.after(0, self._set_server_state, running)

    def _set_server_state(self, running: bool):
        self.server_running = running
        self.status_var.set("Running" if running else "Stopped")
        self.status_dot.itemconfigure(self._dot, fill="#2ecc71" if running else "#c0392b")
        self.start_btn.configure(state="disabled" if running else "normal")
        self.stop_btn.configure(state="normal" if running else "disabled")

    def _tick_stats(self):
        if self.server_running:
            s = self.server.stats()
            up = int(s["uptime"])
            self.stats_var.set(
                f"Clients: {s['clients']}   Total connections: {s['connections']}   "
                f"Relayed: {s['relayed']}   Uptime: {up // 60}m {up % 60}s"
            )
        else:
            self.stats_var.set("Server stopped.")
        self.after(1000, self._tick_stats)

    def _on_close(self):
        if self.server_running:
            self.server.stop()
        self._save_settings()
        self.after(200, self.destroy)
