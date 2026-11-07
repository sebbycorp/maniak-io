#!/usr/bin/env python3
"""Anthropic-shaped mock. The assistant text is the raw request body it received."""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length)
        text = raw.decode("utf-8", errors="replace")
        print(f"LLM MOCK {self.command} {self.path}", flush=True)
        print(text, flush=True)
        response = {
            "id": "msg_lab",
            "type": "message",
            "role": "assistant",
            "model": "claude-lab",
            "content": [{"type": "text", "text": text}],
            "stop_reason": "end_turn",
            "stop_sequence": None,
            "usage": {"input_tokens": 1, "output_tokens": 1},
        }
        body = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))
        sys.stderr.flush()


def main() -> None:
    port = int(sys.argv[1] if len(sys.argv) > 1 else "4010")
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"llm mock listening on http://127.0.0.1:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
