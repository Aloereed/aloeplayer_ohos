"""Unencrypted, peer-restricted LAN file transfer using only Python's stdlib.

Start `serve` on the receiver's LAN address, then use `put` or `get`.
Only explicitly named files under the serving directory are accessible.
Uploads are atomic and SHA-256 verified. Stop the server when finished.
"""
import argparse
import hashlib
import http.client
import http.server
import ipaddress
import json
import os
from pathlib import Path
import socket
import time
from urllib.parse import quote, unquote, urlsplit


def digest(path):
    sha = hashlib.sha256()
    with open(path, "rb") as stream:
        while chunk := stream.read(4 * 1024 * 1024):
            sha.update(chunk)
    return sha.hexdigest()


class Handler(http.server.BaseHTTPRequestHandler):
    def target(self):
        if self.client_address[0] != self.server.peer:
            self.send_error(403)
            return None
        name = unquote(urlsplit(self.path).path).lstrip("/")
        if not name or Path(name).name != name or "\\" in name or name in (".", ".."):
            self.send_error(400)
            return None
        path = self.server.root / name
        if path.is_symlink():
            self.send_error(403)
            return None
        return path

    def do_PUT(self):
        target = self.target()
        if target is None:
            return
        size = int(self.headers.get("Content-Length", "-1"))
        expected = self.headers.get("X-SHA256", "")
        if size < 0 or len(expected) != 64 or target.exists():
            self.send_error(409, "Invalid upload or destination exists")
            return
        partial = target.with_name(target.name + ".part")
        sha = hashlib.sha256()
        remaining = size
        created = False
        try:
            with partial.open("xb") as stream:
                created = True
                os.chmod(partial, 0o600)
                while remaining:
                    chunk = self.rfile.read(min(4 * 1024 * 1024, remaining))
                    if not chunk:
                        raise ConnectionError("Incomplete upload")
                    stream.write(chunk)
                    sha.update(chunk)
                    remaining -= len(chunk)
            if sha.hexdigest() != expected:
                raise ValueError("SHA-256 mismatch")
            partial.rename(target)
            body = json.dumps({"bytes": size, "sha256": sha.hexdigest()}).encode()
            self.send_response(201)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception:
            if created and partial.exists():
                partial.unlink()
            raise

    def do_GET(self):
        target = self.target()
        if target is None:
            return
        if not target.is_file():
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(target.stat().st_size))
        self.send_header("X-SHA256", digest(target))
        self.end_headers()
        self.wfile.flush()
        with target.open("rb") as stream:
            self.connection.sendfile(stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="action", required=True)
    serve = subs.add_parser("serve")
    serve.add_argument("--bind", required=True)
    serve.add_argument("--peer", required=True)
    serve.add_argument("--port", type=int, default=18765)
    serve.add_argument("--root", type=Path, required=True)
    for action in ("put", "get"):
        command = subs.add_parser(action)
        command.add_argument("file", type=Path)
        command.add_argument("url")
    args = parser.parse_args()
    if args.action == "serve":
        for address in (args.bind, args.peer):
            if not ipaddress.ip_address(address).is_private:
                parser.error("Use private LAN addresses only")
        args.root.mkdir(parents=True, exist_ok=True)
        server = http.server.ThreadingHTTPServer((args.bind, args.port), Handler)
        server.root, server.peer = args.root.resolve(), args.peer
        print(f"READY http://{args.bind}:{args.port} peer={args.peer}", flush=True)
        server.serve_forever()
        return
    url = urlsplit(args.url)
    if url.scheme != "http" or not ipaddress.ip_address(url.hostname).is_private:
        parser.error("Use http:// with a private LAN IP address")
    connection = http.client.HTTPConnection(url.hostname, url.port or 80, timeout=600)
    start = time.monotonic()
    if args.action == "put":
        size = args.file.stat().st_size
        checksum = digest(args.file)
        start = time.monotonic()
        connection.putrequest("PUT", quote(unquote(url.path)))
        connection.putheader("Content-Length", str(size))
        connection.putheader("X-SHA256", checksum)
        connection.endheaders()
        connection.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        with args.file.open("rb") as stream:
            sent = 0
            while sent < size:
                sent += connection.sock.sendfile(stream, offset=sent, count=min(64 * 1024 * 1024, size-sent))
                print(f"{sent / size:.0%} {sent / 1e6:.0f} MB", flush=True)
        response = connection.getresponse()
        body = response.read()
        if response.status != 201:
            raise RuntimeError(f"Upload failed: {response.status} {body!r}")
        assert json.loads(body)["sha256"] == checksum
    else:
        if args.file.exists():
            raise FileExistsError(args.file)
        connection.request("GET", quote(unquote(url.path)))
        response = connection.getresponse()
        if response.status != 200:
            raise RuntimeError(f"Download failed: {response.status}")
        checksum = response.getheader("X-SHA256")
        sha = hashlib.sha256()
        partial = args.file.with_name(args.file.name + ".part")
        size = 0
        with partial.open("xb") as stream:
            while chunk := response.read(4 * 1024 * 1024):
                stream.write(chunk)
                sha.update(chunk)
                size += len(chunk)
        if sha.hexdigest() != checksum:
            partial.unlink()
            raise ValueError("SHA-256 mismatch")
        partial.rename(args.file)
    connection.close()
    elapsed = max(time.monotonic() - start, 0.001)
    print(f"SHA256 OK {checksum}; {size/1e6:.1f} MB in {elapsed:.1f}s ({size/1e6/elapsed:.1f} MB/s)")


if __name__ == "__main__":
    main()
