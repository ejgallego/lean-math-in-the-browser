"""Static server for the repository root with the MIME types a module Worker needs
(Python's http.server may serve .mjs as text/plain, which browsers refuse to run as a module).

Run: python bench/servir.py [port]   (default 8125)
"""
import http.server
import mimetypes
import os
import sys

mimetypes.add_type("text/javascript", ".mjs")
mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("application/wasm", ".wasm")
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8125), http.server.SimpleHTTPRequestHandler).serve_forever()
