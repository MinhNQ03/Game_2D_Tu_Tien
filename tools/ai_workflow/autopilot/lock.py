"""Repository-level writer lock.

The lock is an OS advisory lock held on an open file descriptor for the supervisor's lifetime:
the kernel drops it when the process dies, so a crash can never leave a lock nobody can take.
`lock.json` beside it only DESCRIBES the holder (pid, host, run id) for `status` and for the
edit-guard hook; it is never what grants the lock.
"""

from __future__ import annotations

import json
import os
import socket
import sys
from pathlib import Path

from .util import atomic_write_json, now_iso

if sys.platform == "win32":  # pragma: no cover - exercised only on Windows
    import msvcrt

    def _try_lock(fd: int) -> bool:
        try:
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
            return True
        except OSError:
            return False

    def _unlock(fd: int) -> None:
        try:
            os.lseek(fd, 0, 0)
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
else:
    import fcntl

    def _try_lock(fd: int) -> bool:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except (BlockingIOError, PermissionError, OSError):
            return False

    def _unlock(fd: int) -> None:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        except OSError:
            pass


class LockHeld(Exception):
    def __init__(self, holder: dict | None):
        self.holder = holder or {}
        super().__init__(f"another autopilot holds the repository lock: {self.holder}")


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform == "win32":  # pragma: no cover
        return True
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


class RepoLock:
    def __init__(self, state_dir: Path):
        self.dir = Path(state_dir)
        self.lock_path = self.dir / "lock"
        self.info_path = self.dir / "lock.json"
        self.fd: int | None = None
        self.recovered_stale: dict | None = None

    def read_info(self) -> dict | None:
        try:
            return json.loads(self.info_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            return None

    def is_held_by_other(self) -> bool:
        """True when some live process holds the OS lock (used by status and the edit guard)."""
        self.dir.mkdir(parents=True, exist_ok=True)
        fd = os.open(str(self.lock_path), os.O_RDWR | os.O_CREAT, 0o600)
        try:
            if _try_lock(fd):
                _unlock(fd)
                return False
            return True
        finally:
            os.close(fd)

    def acquire(self, run_id: str) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        fd = os.open(str(self.lock_path), os.O_RDWR | os.O_CREAT, 0o600)
        if not _try_lock(fd):
            os.close(fd)
            raise LockHeld(self.read_info())
        self.fd = fd
        previous = self.read_info()
        if previous and not previous.get("released_at"):
            # The OS lock was free but the description says a run never released it: that run
            # crashed or was killed. Record it so resume can reconcile; do not trust its claims.
            self.recovered_stale = previous
        atomic_write_json(self.info_path, {
            "run_id": run_id, "pid": os.getpid(), "host": socket.gethostname(),
            "acquired_at": now_iso(), "released_at": None,
        })

    def release(self) -> None:
        if self.fd is None:
            return
        info = self.read_info() or {}
        if info.get("pid") == os.getpid():
            info["released_at"] = now_iso()
            atomic_write_json(self.info_path, info)
        _unlock(self.fd)
        os.close(self.fd)
        self.fd = None

    def __enter__(self) -> "RepoLock":
        return self

    def __exit__(self, *exc) -> None:
        self.release()
