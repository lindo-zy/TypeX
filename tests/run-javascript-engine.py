#!/usr/bin/env python3
"""Runs the actual Foundation/JavaScriptCore engine on macOS against localhost.
No iOS deployment, external requests or changes to the user's clipboard/apps.
"""
import http.server
import json
import pathlib
import subprocess
import tempfile
import threading
import time


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == '/slow':
            time.sleep(0.5)
        status = 503 if self.path == '/status' else 200
        body = {'/text': 'hello 中文'.encode(), '/binary': b'\xff\xfe',
                '/large': b'x' * (1024 * 1024 + 1)}.get(self.path, b'ok')
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        data = json.dumps({'method': self.command, 'header': self.headers.get('X-Test'), 'body': body}).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_PUT = do_PATCH = do_DELETE = do_POST


root = pathlib.Path(__file__).resolve().parents[1]
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='typex-js-tests-') as tmp:
        binary = str(pathlib.Path(tmp) / 'js-tests')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror',
                        '-framework', 'Foundation', '-framework', 'JavaScriptCore',
                        str(root / 'DXJavaScriptEngine.m'), str(root / 'tests/DXJavaScriptEngineTests.m'),
                        '-o', binary], check=True)
        subprocess.run([binary, f'http://127.0.0.1:{server.server_port}'], check=True, timeout=45)
finally:
    server.shutdown()
    server.server_close()
