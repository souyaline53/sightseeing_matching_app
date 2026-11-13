"""Local browser-test fixture only. No Firebase or Dify calls."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

FIXTURE = Path(__file__).resolve().parents[1] / 'docs/transport_optimizer_meroad_coal_optimized.json'

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/network.json':
            self.send_error(404)
            return
        data = FIXTURE.read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass

if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 8766), Handler).serve_forever()
