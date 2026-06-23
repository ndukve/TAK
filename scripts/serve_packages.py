#!/usr/bin/env python3
"""TAK package + client plugin HTTP server.

Routes:
  /                   user data packages  (certs/files/clientpkgs/)
  /<callsign>.zip     direct package link
  /plugins/           ATAK/WinTAK plugin index
  /plugins/<file>     plugin download (APK / ZIP)
"""
import http.server
import os
import sys
import urllib.parse

PORT       = int(sys.argv[1]) if len(sys.argv) > 1 else 8888
BIND       = "0.0.0.0"
DATA_ROOT  = "/opt/tak/data"
PKG_DIR    = os.path.join(DATA_ROOT, "certs/files/clientpkgs")
PLUGIN_DIR = os.path.join(DATA_ROOT, "plugins")

MIME = {
    ".p12":  "application/x-pkcs12",
    ".zip":  "application/zip",
    ".pref": "text/xml",
    ".apk":  "application/vnd.android.package-archive",
}
FORCE_DOWNLOAD = {".zip", ".p12", ".apk"}


class TAKHandler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        path = urllib.parse.unquote(self.path.split("?")[0])

        if path in ("/plugins", "/plugins/"):
            self._list_plugins()
        elif path.startswith("/plugins/"):
            fname = os.path.basename(path)
            self._send_file(os.path.join(PLUGIN_DIR, fname))
        elif path in ("/", "/index.html"):
            self._list_packages()
        else:
            fname = os.path.basename(path)
            self._send_file(os.path.join(PKG_DIR, fname))

    def _send_file(self, fpath):
        if not os.path.isfile(fpath):
            self.send_error(404)
            return
        _, ext = os.path.splitext(fpath)
        mime   = MIME.get(ext.lower(), "application/octet-stream")
        size   = os.path.getsize(fpath)
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(size))
        if ext.lower() in FORCE_DOWNLOAD:
            self.send_header("Content-Disposition",
                             f'attachment; filename="{os.path.basename(fpath)}"')
        self.end_headers()
        with open(fpath, "rb") as f:
            self.wfile.write(f.read())

    def _list_packages(self):
        files = (sorted(f for f in os.listdir(PKG_DIR) if f.endswith(".zip"))
                 if os.path.isdir(PKG_DIR) else [])
        rows = "".join(
            f'<tr><td><a href="/{f}">{f}</a></td>'
            f'<td>{_size(os.path.join(PKG_DIR, f))}</td></tr>'
            for f in files
        ) or "<tr><td colspan=2>No packages yet — run: make add-user USERNAME=alice</td></tr>"
        self._html("TAK User Packages",
                   f'<p><a href="/plugins/">→ Plugin repository</a></p>'
                   f'<table><tr><th>Package</th><th>Size</th></tr>{rows}</table>')

    def _list_plugins(self):
        files = (sorted(f for f in os.listdir(PLUGIN_DIR)
                        if f.endswith(".apk") or f.endswith(".zip"))
                 if os.path.isdir(PLUGIN_DIR) else [])
        rows = "".join(
            f'<tr><td><a href="/plugins/{f}">{f}</a></td>'
            f'<td>{_size(os.path.join(PLUGIN_DIR, f))}</td></tr>'
            for f in files
        ) or "<tr><td colspan=2>No plugins yet — run: make add-plugin APK=/path/to/plugin.apk</td></tr>"
        self._html("ATAK Plugin Repository",
                   f'<p><a href="/">← User packages</a></p>'
                   f'<p>On device: open ATAK → Settings → Manage Plugins → Install from file<br>'
                   f'Or navigate to this page in ATAK browser and tap a file to sideload.</p>'
                   f'<table><tr><th>Plugin</th><th>Size</th></tr>{rows}</table>')

    def _html(self, title, body):
        page = (
            f'<!DOCTYPE html><html><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width">'
            f'<title>{title}</title>'
            f'<style>body{{font-family:monospace;max-width:900px;margin:2em auto;padding:0 1em}}'
            f'table{{width:100%;border-collapse:collapse}}'
            f'th,td{{padding:6px 10px;text-align:left;border-bottom:1px solid #ddd}}'
            f'a{{color:#06c}}</style></head>'
            f'<body><h2>{title}</h2>{body}</body></html>'
        )
        data = page.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print(f"  {self.address_string()} → {fmt % args}")


def _size(path: str) -> str:
    try:
        b = os.path.getsize(path)
        for unit in ("B", "KB", "MB", "GB"):
            if b < 1024:
                return f"{b:.0f} {unit}"
            b /= 1024
        return f"{b:.1f} GB"
    except OSError:
        return "?"


print(f"\nTAK package + plugin server → http://{BIND}:{PORT}/")
print(f"  User packages : http://<server>:8888/<callsign>.zip")
print(f"  Plugin repo   : http://<server>:8888/plugins/")
print("Press Ctrl+C to stop.\n")

with http.server.HTTPServer((BIND, PORT), TAKHandler) as httpd:
    httpd.serve_forever()
