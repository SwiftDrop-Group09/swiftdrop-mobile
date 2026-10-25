"""Serve the dedicated Flutter test build with a same-origin local API proxy.

This helper is test infrastructure. It never serves the normal release build,
loads secrets, or connects to a configurable external host.
"""

import argparse
import functools
import http.client
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class FixtureHandler(SimpleHTTPRequestHandler):
    api_port = 5088

    def _is_fixture_request(self):
        path = urlsplit(self.path).path
        return path.startswith("/api/") or path == "/__test/booking-context"

    def do_GET(self):
        if self._is_fixture_request():
            self._proxy()
        else:
            super().do_GET()

    def do_POST(self):
        if self._is_fixture_request():
            self._proxy()
        else:
            self.send_error(405)

    def _proxy(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        if length < 0 or length > 1_048_576:
            self.send_error(413)
            return
        body = self.rfile.read(length) if length else None
        excluded = {"host", "connection", "transfer-encoding", "accept-encoding"}
        headers = {
            key: value for key, value in self.headers.items()
            if key.lower() not in excluded
        }
        connection = http.client.HTTPConnection("127.0.0.1", self.api_port, timeout=15)
        try:
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            payload = response.read()
            self.send_response(response.status)
            excluded_response = {
                "content-length", "transfer-encoding", "connection",
                "server", "date", "cache-control",
            }
            for key, value in response.getheaders():
                if key.lower() not in excluded_response:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
        except (OSError, http.client.HTTPException):
            payload = json.dumps({"code": "fixture_unavailable"}).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        finally:
            connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=5181)
    parser.add_argument("--api-port", type=int, default=5088)
    args = parser.parse_args()
    if any(port < 1 or port > 65535 for port in (args.port, args.api_port)):
        parser.error("Ports must be between 1 and 65535.")
    build = Path(__file__).resolve().parents[1] / "build" / "booking-harness"
    if not (build / "index.html").is_file():
        parser.error("Build the dedicated profile web harness first; see README.md.")
    FixtureHandler.api_port = args.api_port
    handler = functools.partial(FixtureHandler, directory=str(build))
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    server.daemon_threads = True
    print(f"Flutter test fixture: http://127.0.0.1:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
