#!/usr/bin/env python3
"""Offline check for refresh.sh: stub the workers refresh endpoint, run the
script, and assert it does a single GET carrying the X-Refresh-Token header.
Run: python3 refresher/test_refresh.py"""
import http.server
import os
import pathlib
import subprocess
import threading

REFRESH_BODY = '{"total":1,"data":[{"workerId":"1","company":{"name":"X"}}]}'
TOKEN = "refresh-token-123"
captured = {}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):  # silence
        pass

    def do_GET(self):
        captured["path"] = self.path
        captured["token"] = self.headers.get("X-Refresh-Token")
        body = REFRESH_BODY.encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]

    script = pathlib.Path(__file__).with_name("refresh.sh")
    env = {
        **os.environ,
        "APIM_GATEWAY_URL": f"http://127.0.0.1:{port}",
        "REFRESH_TOKEN": TOKEN,
    }
    subprocess.run(["sh", str(script)], env=env, check=True)
    server.shutdown()

    assert captured["path"] == "/workers", captured
    assert captured["token"] == TOKEN, captured
    print("OK: refresh.sh did a single GET /workers with the refresh token")


if __name__ == "__main__":
    main()
