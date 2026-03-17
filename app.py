"""
WinCleanup Desktop - Disk & cache cleanup with GUI.
"""

import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

import psutil
import webview

# ─── Config ──────────────────────────────────────────────────────────────

PROTECTED_PATHS = [
    os.path.expandvars(r"%APPDATA%\Claude\claude-code"),
    os.path.expandvars(r"%APPDATA%\Claude\vm_bundles"),
    os.path.expandvars(r"%APPDATA%\Claude\claude-code-vm"),
]

SCAN_CATEGORIES = {
    "Windows Temp": [
        os.path.expandvars(r"%TEMP%"),
        r"C:\Windows\Temp",
    ],
    "Crash Dumps": [
        os.path.expandvars(r"%LOCALAPPDATA%\CrashDumps"),
    ],
    "Windows Update Cache": [
        r"C:\Windows\SoftwareDistribution\Download",
    ],
    "Thumbnail Cache": [
        os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Windows\Explorer"),
    ],
    "Chrome Cache": [
        os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache"),
        os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\User Data\Default\Code Cache"),
        os.path.expandvars(r"%LOCALAPPDATA%\Google\Chrome\User Data\Default\Service Worker\CacheStorage"),
    ],
    "Edge Cache": [
        os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache"),
        os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Code Cache"),
    ],
    "Claude Cache": [
        os.path.expandvars(r"%APPDATA%\Claude\Cache"),
        os.path.expandvars(r"%APPDATA%\Claude\Code Cache"),
        os.path.expandvars(r"%APPDATA%\Claude\GPUCache"),
        os.path.expandvars(r"%APPDATA%\Claude\logs"),
    ],
    "NVIDIA Cache": [
        os.path.expandvars(r"%LOCALAPPDATA%\NVIDIA Corporation\NV_Cache"),
        os.path.expandvars(r"%APPDATA%\NVIDIA"),
    ],
    "VS Code / Cursor Cache": [
        os.path.expandvars(r"%APPDATA%\Code\Cache"),
        os.path.expandvars(r"%APPDATA%\Code\CachedData"),
        os.path.expandvars(r"%APPDATA%\Cursor\Cache"),
        os.path.expandvars(r"%APPDATA%\Cursor\CachedData"),
    ],
    "Docker Temp": [
        os.path.expandvars(r"%TEMP%\DockerDesktop"),
    ],
}

PKG_MANAGER_CACHES = {
    "conda": {
        "check": "conda --version",
        "clean": "conda clean --all --yes",
        "paths": [r"C:\ProgramData\miniconda3\pkgs"],
    },
    "pip": {
        "check": "pip --version",
        "clean": "pip cache purge",
        "paths": [os.path.expandvars(r"%LOCALAPPDATA%\pip\cache")],
    },
    "npm": {
        "check": "npm --version",
        "clean": "npm cache clean --force",
        "paths": [os.path.expandvars(r"%LOCALAPPDATA%\npm-cache")],
    },
    "pnpm": {
        "check": "pnpm --version",
        "clean": "pnpm store prune",
        "paths": [os.path.expandvars(r"%LOCALAPPDATA%\pnpm-store")],
    },
    "yarn": {
        "check": "yarn --version",
        "clean": "yarn cache clean",
        "paths": [os.path.expandvars(r"%LOCALAPPDATA%\Yarn\Cache")],
    },
    "scoop": {
        "check": "scoop --version",
        "clean": "scoop cache rm *",
        "paths": [os.path.expandvars(r"%USERPROFILE%\scoop\cache")],
    },
    "cargo": {
        "check": "cargo --version",
        "clean": None,
        "paths": [os.path.expandvars(r"%USERPROFILE%\.cargo\registry\cache")],
    },
    "go": {
        "check": "go version",
        "clean": "go clean -modcache",
        "paths": [os.path.expandvars(r"%USERPROFILE%\go\pkg\mod\cache")],
    },
    "docker": {
        "check": "docker --version",
        "clean": "docker system prune -f",
        "paths": [],
    },
    "uv": {
        "check": "uv --version",
        "clean": "uv cache clean",
        "paths": [os.path.expandvars(r"%LOCALAPPDATA%\uv\cache")],
    },
}

PKG_UPDATE_COMMANDS = {
    "conda": ["conda update conda -y", "conda update --all -y"],
    "pip": ["pip install --upgrade pip"],
    "npm": ["npm update -g"],
    "scoop": ["scoop update *"],
}

# winget: only update dev tools, not entertainment/game apps
WINGET_DEV_PACKAGES = [
    "Git.Git",
    "Microsoft.VisualStudioCode",
    "Microsoft.WindowsTerminal",
    "Docker.DockerDesktop",
    "Python.Python.3",
    "OpenJS.NodeJS",
    "Google.Chrome",
    "Mozilla.Firefox",
    "Notepad++.Notepad++",
    "JetBrains.Toolbox",
    "Microsoft.PowerShell",
    "Microsoft.DotNet.SDK.8",
    "GoLang.Go",
    "Rustlang.Rust.MSVC",
    "Postman.Postman",
]


# ─── Backend API ─────────────────────────────────────────────────────────

class Api:
    def __init__(self):
        self._window = None
        self._cleaning = False

    def set_window(self, window):
        self._window = window

    def _emit(self, event, data):
        """Send event to frontend."""
        if self._window:
            self._window.evaluate_js(
                f"window.dispatchEvent(new CustomEvent('{event}', {{detail: {json.dumps(data)}}}));"
            )

    def get_disk_info(self):
        """Get disk usage for all partitions."""
        disks = []
        for part in psutil.disk_partitions(all=False):
            try:
                usage = psutil.disk_usage(part.mountpoint)
                disks.append({
                    "device": part.device,
                    "mountpoint": part.mountpoint,
                    "total": usage.total,
                    "used": usage.used,
                    "free": usage.free,
                    "percent": usage.percent,
                })
            except (PermissionError, OSError):
                pass
        return disks

    def _get_dir_size(self, path):
        """Get directory size in bytes."""
        total = 0
        if not os.path.isdir(path):
            return 0
        for dirpath, _, filenames in os.walk(path):
            # Skip protected paths
            for pp in PROTECTED_PATHS:
                if dirpath.startswith(pp):
                    return 0
            for f in filenames:
                try:
                    total += os.path.getsize(os.path.join(dirpath, f))
                except (OSError, PermissionError):
                    pass
        return total

    def _cmd_exists(self, cmd):
        """Check if a command exists."""
        try:
            subprocess.run(
                cmd, shell=True, capture_output=True, timeout=10,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            return True
        except Exception:
            return False

    def scan(self):
        """Scan all cleanable caches and return sizes."""
        results = []

        # System & app caches
        for category, paths in SCAN_CATEGORIES.items():
            size = 0
            for p in paths:
                if os.path.exists(p):
                    size += self._get_dir_size(p)
            if size > 0:
                results.append({
                    "category": category,
                    "size": size,
                    "type": "system",
                })

        # Package manager caches
        for name, info in PKG_MANAGER_CACHES.items():
            if not self._cmd_exists(info["check"]):
                continue
            size = 0
            for p in info.get("paths", []):
                if os.path.exists(p):
                    size += self._get_dir_size(p)
            results.append({
                "category": f"{name} cache",
                "size": size,
                "type": "package",
                "has_clean": info.get("clean") is not None,
            })

        # Recycle bin estimate
        try:
            rb_path = os.path.expandvars(r"C:\$Recycle.Bin")
            if os.path.exists(rb_path):
                size = self._get_dir_size(rb_path)
                if size > 0:
                    results.append({
                        "category": "Recycle Bin",
                        "size": size,
                        "type": "system",
                    })
        except Exception:
            pass

        results.sort(key=lambda x: x["size"], reverse=True)
        return results

    def clean(self, categories):
        """Clean selected categories. Runs in background thread."""
        if self._cleaning:
            return {"error": "Cleanup already in progress"}
        self._cleaning = True

        def _do_clean():
            try:
                total_freed = 0
                total_items = len(categories)
                flags = subprocess.CREATE_NO_WINDOW

                for i, cat in enumerate(categories):
                    self._emit("clean_progress", {
                        "current": i + 1,
                        "total": total_items,
                        "category": cat,
                        "status": "cleaning",
                    })

                    freed = 0

                    # System/app cache - delete directories
                    if cat in SCAN_CATEGORIES:
                        for p in SCAN_CATEGORIES[cat]:
                            if not os.path.exists(p):
                                continue
                            before = self._get_dir_size(p)
                            # For temp dirs, delete contents not the dir itself
                            if "Temp" in cat or p.endswith("Temp"):
                                self._delete_contents(p)
                            else:
                                self._delete_contents(p)
                            after = self._get_dir_size(p)
                            freed += before - after

                    # Package manager cache - use native clean command
                    for name, info in PKG_MANAGER_CACHES.items():
                        if cat == f"{name} cache" and info.get("clean"):
                            before_sizes = sum(
                                self._get_dir_size(p)
                                for p in info.get("paths", [])
                                if os.path.exists(p)
                            )
                            try:
                                subprocess.run(
                                    info["clean"], shell=True,
                                    capture_output=True, timeout=120,
                                    creationflags=flags
                                )
                            except Exception:
                                pass
                            after_sizes = sum(
                                self._get_dir_size(p)
                                for p in info.get("paths", [])
                                if os.path.exists(p)
                            )
                            freed += max(0, before_sizes - after_sizes)
                            # Also delete path contents for non-command caches
                            for p in info.get("paths", []):
                                if os.path.exists(p):
                                    self._delete_contents(p)

                    # Recycle Bin
                    if cat == "Recycle Bin":
                        try:
                            subprocess.run(
                                'powershell -Command "Clear-RecycleBin -Force"',
                                shell=True, capture_output=True, timeout=60,
                                creationflags=flags
                            )
                            freed = 0  # Can't easily measure
                        except Exception:
                            pass

                    total_freed += freed
                    self._emit("clean_progress", {
                        "current": i + 1,
                        "total": total_items,
                        "category": cat,
                        "status": "done",
                        "freed": freed,
                    })

                self._emit("clean_complete", {
                    "total_freed": total_freed,
                    "disk_info": self.get_disk_info(),
                })
            finally:
                self._cleaning = False

        threading.Thread(target=_do_clean, daemon=True).start()
        return {"status": "started"}

    def _delete_contents(self, path):
        """Delete contents of a directory, skipping protected paths."""
        import shutil
        if not os.path.isdir(path):
            return
        for pp in PROTECTED_PATHS:
            if path.startswith(pp):
                return
        for item in os.listdir(path):
            fullpath = os.path.join(path, item)
            # Skip protected
            skip = False
            for pp in PROTECTED_PATHS:
                if fullpath.startswith(pp):
                    skip = True
                    break
            if skip:
                continue
            try:
                if os.path.isdir(fullpath):
                    shutil.rmtree(fullpath, ignore_errors=True)
                else:
                    os.remove(fullpath)
            except (OSError, PermissionError):
                pass

    def update_packages(self, managers):
        """Update selected package managers."""
        def _do_update():
            flags = subprocess.CREATE_NO_WINDOW
            results = []
            for mgr in managers:
                self._emit("update_progress", {"manager": mgr, "status": "updating"})
                success = True

                if mgr == "winget":
                    # Only update whitelisted dev tool packages
                    for pkg_id in WINGET_DEV_PACKAGES:
                        try:
                            r = subprocess.run(
                                f"winget upgrade --id {pkg_id} --accept-package-agreements --accept-source-agreements",
                                shell=True, capture_output=True,
                                timeout=300, text=True, creationflags=flags
                            )
                        except Exception:
                            pass
                else:
                    cmds = PKG_UPDATE_COMMANDS.get(mgr, [])
                    for cmd in cmds:
                        try:
                            r = subprocess.run(
                                cmd, shell=True, capture_output=True,
                                timeout=300, text=True, creationflags=flags
                            )
                            if r.returncode != 0:
                                success = False
                        except Exception:
                            success = False

                results.append({"manager": mgr, "success": success})
                self._emit("update_progress", {
                    "manager": mgr,
                    "status": "done" if success else "failed",
                })
            self._emit("update_complete", {"results": results})

        threading.Thread(target=_do_update, daemon=True).start()
        return {"status": "started"}

    def get_history(self):
        """Load cleanup history from local file."""
        history_file = os.path.join(os.path.dirname(__file__), "history.json")
        if os.path.exists(history_file):
            with open(history_file, "r") as f:
                return json.load(f)
        return []

    def save_history(self, entry):
        """Append a cleanup record to history."""
        history_file = os.path.join(os.path.dirname(__file__), "history.json")
        history = self.get_history()
        history.append(entry)
        # Keep last 100 entries
        history = history[-100:]
        with open(history_file, "w") as f:
            json.dump(history, f, indent=2)
        return True


# ─── Main ────────────────────────────────────────────────────────────────

def main():
    api = Api()
    ui_path = os.path.join(os.path.dirname(__file__), "ui", "index.html")

    window = webview.create_window(
        "WinCleanup",
        url=ui_path,
        js_api=api,
        width=1100,
        height=750,
        min_size=(900, 600),
        background_color="#0f172a",
    )
    api.set_window(window)
    webview.start(debug=("--debug" in sys.argv))


if __name__ == "__main__":
    main()
