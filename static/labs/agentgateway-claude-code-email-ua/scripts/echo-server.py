#!/usr/bin/env python3
"""HTTPS header echo for the egress hop. Prints the User-Agent it actually received."""

import json
import ssl
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self._respond()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length:
            self.rfile.read(length)
        self._respond()

    def _respond(self):
        payload = {
            "path": self.path,
            "headers": {key: value for key, value in self.headers.items()},
        }
        body = json.dumps(payload, indent=2).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))
        sys.stderr.flush()


def main() -> None:
    if len(sys.argv) != 4:
        print("usage: echo-server.py CERT KEY PORT", file=sys.stderr)
        sys.exit(2)
    cert, key, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    print(f"echo listening on https://127.0.0.1:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
