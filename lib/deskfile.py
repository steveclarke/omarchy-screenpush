#!/usr/bin/python3 -I
"""Descriptor-bound access to ~/.config/screenpush/desks.json.

Every step works through descriptors opened once and checked on the
descriptor itself, never by reopening a pathname:

  - The passwd home is the trust root. The default .config or each component
    of an absolute $XDG_CONFIG_HOME beneath that home is opened relative to
    the preceding directory with O_NOFOLLOW and checked for ownership. Only
    a missing default .config is created; no symlink in the walk is followed.
  - The screenpush directory beneath it is opened O_NOFOLLOW, must be owned by
    this user, and is kept at 0700.
  - desks.json is opened O_NOFOLLOW|O_NONBLOCK and must be a regular file owned
    by this user, with one link, no group or other write bit, and under the
    size cap. It is read from that descriptor, capped at the limit plus one.
  - A save holds an exclusive flock on the directory descriptor for the whole
    read-merge-write, writes a random O_EXCL 0600 temporary through that
    directory, fsyncs it, renames it over desks.json relative to the same
    directory descriptor, fsyncs the directory, and then confirms the
    directory still resolves to the inode it locked.

Anything that fails a check is refused, never repaired or followed.

Usage:
  deskfile.py read           print desks.json, or nothing when there is none
  deskfile.py save KEY       merge the desk JSON on stdin in as desks[KEY]
  deskfile.py lock CMD ARGS  run CMD holding the directory lock
"""

import fcntl
import json
import os
import pwd
import secrets
import stat
import subprocess
import sys

MAX_BYTES = 262144
NAME = "desks.json"
UID = os.geteuid()


class Refused(Exception):
    pass


def open_anchor(chain_out=None):
    try:
        home = pwd.getpwuid(UID).pw_dir
    except (KeyError, OSError):
        raise Refused("the passwd home is unavailable") from None
    if not os.path.isabs(home):
        raise Refused("the passwd home is not absolute")
    base = os.environ.get("XDG_CONFIG_HOME", "")
    if os.path.isabs(base):
        prefix = home.rstrip("/")
        if not base.startswith(prefix + "/"):
            raise Refused(f"{base} is outside the passwd home")
        components = base[len(prefix) + 1:].split("/")
        if any(part in ("", ".", "..") for part in components):
            raise Refused(f"{base} has an unsafe component")
        default = False
    else:
        components = [".config"]
        default = True
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        fd = os.open(home, flags)
    except OSError:
        raise Refused(f"{home} is not a plain directory") from None
    try:
        st = os.fstat(fd)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != UID:
            raise Refused(f"{home} is not a directory you own")
        if chain_out is not None:
            chain_out.append((st.st_dev, st.st_ino))
        for part in components:
            try:
                child = open_child_dir(fd, part, create=default)
            except FileNotFoundError:
                raise Refused(f"{base} does not exist") from None
            os.close(fd)
            fd = child
            if chain_out is not None:
                st = os.fstat(fd)
                chain_out.append((st.st_dev, st.st_ino))
        return fd
    except OSError:
        os.close(fd)
        raise Refused("the config path could not be checked") from None
    except BaseException:
        os.close(fd)
        raise


def open_child_dir(parent, name, create):
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        fd = os.open(name, flags, dir_fd=parent)
    except FileNotFoundError:
        if not create:
            raise
        try:
            os.mkdir(name, 0o700, dir_fd=parent)
        except FileExistsError:
            pass
        except OSError:
            raise Refused(f"{name} could not be created") from None
        try:
            fd = os.open(name, flags, dir_fd=parent)
        except OSError:
            raise Refused(f"{name} is not a plain directory") from None
    except OSError:
        # ELOOP or ENOTDIR: a symlink or something that is not a directory.
        raise Refused(f"{name} is not a plain directory") from None
    try:
        st = os.fstat(fd)
    except OSError:
        os.close(fd)
        raise Refused(f"{name} could not be checked") from None
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != UID:
        os.close(fd)
        raise Refused(f"{name} is not a directory you own")
    return fd


def open_desk_dir(create, chain_out=None):
    anchor = open_anchor(chain_out)
    try:
        try:
            fd = open_child_dir(anchor, "screenpush", create)
        except FileNotFoundError:
            return None
    finally:
        os.close(anchor)
    if os.fstat(fd).st_mode & 0o077:
        os.fchmod(fd, 0o700)
    return fd


def read_desks(dirfd):
    try:
        fd = os.open(NAME, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dirfd)
    except FileNotFoundError:
        return None
    except OSError:
        raise Refused(f"{NAME} is not a plain file") from None
    try:
        st = os.fstat(fd)
        if (not stat.S_ISREG(st.st_mode) or st.st_uid != UID or st.st_nlink != 1
                or st.st_mode & 0o022 or st.st_size > MAX_BYTES):
            raise Refused(f"{NAME} is not a plain file only you can write")
        os.set_blocking(fd, True)
        data = b""
        while len(data) <= MAX_BYTES:
            chunk = os.read(fd, MAX_BYTES + 1 - len(data))
            if not chunk:
                break
            data += chunk
        if len(data) > MAX_BYTES:
            raise Refused(f"{NAME} is larger than {MAX_BYTES} bytes")
        return data
    finally:
        os.close(fd)


def write_desks(dirfd, data):
    tmp = f".{NAME}.{secrets.token_hex(8)}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=dirfd)
    try:
        os.fchmod(fd, 0o600)
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view):]
        os.fsync(fd)
        os.rename(tmp, NAME, src_dir_fd=dirfd, dst_dir_fd=dirfd)
        os.fsync(dirfd)
    except BaseException:
        try:
            os.unlink(tmp, dir_fd=dirfd)
        except OSError:
            pass
        raise
    finally:
        os.close(fd)


def revalidate(dirfd, chain):
    """The home, config path, and desk directory still name the held inodes."""
    held = os.fstat(dirfd)
    current_chain = []
    again = open_desk_dir(create=False, chain_out=current_chain)
    if again is None:
        raise Refused("the screenpush directory moved during the save")
    try:
        now = os.fstat(again)
        if current_chain != chain or (now.st_dev, now.st_ino) != (held.st_dev, held.st_ino):
            raise Refused("the desk file path was replaced during the save")
    finally:
        os.close(again)


def cmd_read():
    dirfd = open_desk_dir(create=False)
    if dirfd is None:
        return 0
    # No lock: a save publishes by rename, so a read sees the old file or the
    # new one, never half of one. Taking the lock here would also deadlock
    # inside `lock`, which holds it for the whole switch.
    try:
        data = read_desks(dirfd)
    finally:
        os.close(dirfd)
    if data:
        sys.stdout.write(data.decode("utf-8", "strict"))
    return 0


def cmd_save(key):
    if not key or len(key) > 4096 or any(c in key for c in "\0\n\r"):
        raise Refused("bad desk key")
    payload = sys.stdin.buffer.read(MAX_BYTES + 1)
    if len(payload) > MAX_BYTES:
        raise Refused("desk data is too large")
    try:
        desk = json.loads(payload)
    except ValueError:
        raise Refused("the desk data was unreadable") from None
    if not isinstance(desk, dict):
        raise Refused("the desk data was unreadable")

    chain = []
    dirfd = open_desk_dir(create=True, chain_out=chain)
    try:
        fcntl.flock(dirfd, fcntl.LOCK_EX)
        current = read_desks(dirfd)
        doc = {"version": 1, "desks": {}}
        if current:
            try:
                doc = json.loads(current)
            except ValueError:
                raise Refused(f"{NAME} is damaged; move it aside and save again") from None
            if not isinstance(doc, dict) or not isinstance(doc.get("desks", {}), dict):
                raise Refused(f"{NAME} is damaged; move it aside and save again")
        doc["version"] = 1
        doc.setdefault("desks", {})[key] = desk
        out = json.dumps(doc, indent=2).encode() + b"\n"
        if len(out) > MAX_BYTES:
            raise Refused("desk file would be too large")
        write_desks(dirfd, out)
        revalidate(dirfd, chain)
    finally:
        os.close(dirfd)
    return 0


def cmd_lock(argv):
    if not argv:
        raise Refused("nothing to run")
    dirfd = open_desk_dir(create=True)
    try:
        fcntl.flock(dirfd, fcntl.LOCK_EX)
        return subprocess.run(argv, close_fds=True).returncode
    finally:
        os.close(dirfd)


def main(argv):
    try:
        if len(argv) == 1 and argv[0] == "read":
            return cmd_read()
        if len(argv) == 2 and argv[0] == "save":
            return cmd_save(argv[1])
        if len(argv) >= 2 and argv[0] == "lock":
            return cmd_lock(argv[1:])
        print("usage: deskfile.py read | save KEY | lock CMD...", file=sys.stderr)
        return 2
    except Refused as e:
        print(f"Screen Push won't use its desk file: {e}.", file=sys.stderr)
        return 1
    except UnicodeDecodeError:
        print(f"Screen Push won't use its desk file: {NAME} is not UTF-8.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
