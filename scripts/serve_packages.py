#!/usr/bin/env python3
"""
Serve TAK data packages over HTTP with the correct MIME types.
iOS will refuse to open .p12 files if the Content-Type is wrong.

Usage: python3 serve_packages.py [port]
       Called by: make serve-packages
"""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8888
BIND = "0.0.0.0"

MIME_OVERRIDES = {
    ".p12": "application/x-pkcs12",
    ".zip": "application/zip",
    ".pref": "text/xml",
}


class TAKPackageHandler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        _, ext = os.path.splitext(path)
        if ext.lower() in MIME_OVERRIDES:
            return MIME_OVERRIDES[ext.lower()]
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} → {fmt % args}")


print(f"\nServing TAK packages at http://{BIND}:{PORT}/")
print("Device URL: http://<Tailscale-IP>:8888/<username>.zip")
print("Press Ctrl+C to stop.\n")

with http.server.HTTPServer((BIND, PORT), TAKPackageHandler) as httpd:
    httpd.serve_forever()
