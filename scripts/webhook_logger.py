# Recepteur webhook minimal : ecrit les alertes recues dans le journal
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        corps = self.rfile.read(int(self.headers["Content-Length"]))
        print(self.path, corps.decode(), flush=True)
        self.send_response(200)
        self.end_headers()

HTTPServer(("127.0.0.1", 5001), H).serve_forever()
