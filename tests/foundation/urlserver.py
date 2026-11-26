#!/usr/bin/env python3
"""A local HTTP and WebSocket server for tests/foundation/urlsession.m.
Prints the port it listens on, then serves until stdin closes."""
import base64, gzip, hashlib, http.server, socketserver, struct, sys, threading


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send(self, status, body=b"", headers=()):
        self.send_response(status)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        p = self.path
        if p == "/hello":
            self.send(200, b"hello world", [("Content-Type", "text/plain; charset=utf-8"), ("X-Test", "yes")])
        elif p.startswith("/redirect"):
            self.send(302, b"moving", [("Location", "/hello")])
        elif p == "/relative/redirect":
            self.send(301, b"", [("Location", "../hello")])
        elif p == "/loop":
            self.send(302, b"", [("Location", "/loop")])
        elif p == "/setcookie":
            self.send(200, b"set", [("Set-Cookie", "flavor=oat; Path=/"), ("Set-Cookie", "other=1; Path=/")])
        elif p == "/cookies":
            self.send(200, (self.headers.get("Cookie") or "").encode())
        elif p == "/gzip":
            self.send(200, gzip.compress(b"z" * 1000), [("Content-Encoding", "gzip")])
        elif p == "/agent":
            self.send(200, (self.headers.get("User-Agent") or "").encode())
        elif p == "/big":
            self.send(200, bytes(range(256)) * 4096, [("Content-Type", "application/octet-stream")])
        elif p == "/missing":
            self.send(404, b"nope")
        elif p == "/slow":
            threading.Event().wait(5)
            self.send(200, b"late")
        elif p.startswith("/ws"):
            self.websocket()
        else:
            self.send(404, b"")

    def do_POST(self):
        b = self.body()
        if self.path == "/echo":
            self.send(200, b, [("Content-Type", self.headers.get("Content-Type") or "")])
        elif self.path == "/seeother":
            self.send(303, b"", [("Location", "/method")])
        else:
            self.send(404, b"")

    def do_PUT(self):
        b = self.body()
        self.send(200, b"put:" + b)

    do_DELETE = do_GET

    def websocket(self):
        key = self.headers.get("Sec-WebSocket-Key")
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        proto = self.headers.get("Sec-WebSocket-Protocol")
        if proto:
            self.send_header("Sec-WebSocket-Protocol", proto.split(",")[0].strip())
        self.end_headers()
        self.wfile.flush()
        r, w = self.rfile, self.wfile

        def frame(op, data):
            n = len(data)
            head = bytes([0x80 | op])
            head += bytes([n]) if n < 126 else (bytes([126]) + struct.pack(">H", n) if n < 65536 else bytes([127]) + struct.pack(">Q", n))
            w.write(head + data)
            w.flush()

        frame(1, b"welcome")
        while True:
            h = r.read(2)
            if len(h) < 2:
                return
            op, n = h[0] & 15, h[1] & 127
            if n == 126:
                n = struct.unpack(">H", r.read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", r.read(8))[0]
            mask = r.read(4) if h[1] & 128 else b"\0\0\0\0"
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(r.read(n)))
            if op == 8:
                frame(8, data[:2])
                return
            if op == 9:
                frame(10, data)
            elif data == b"close please":
                frame(8, struct.pack(">H", 4000) + b"bye")
                return
            elif op in (1, 2):
                # echo, in two fragments for text
                if op == 1 and len(data) > 1:
                    w.write(bytes([0x01, len(data[:1])]) + data[:1])
                    w.write(bytes([0x80, len(data[1:])]) + data[1:])
                    w.flush()
                else:
                    frame(op, data)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


s = Server(("127.0.0.1", 0), Handler)
print(s.server_address[1], flush=True)
threading.Thread(target=s.serve_forever, daemon=True).start()
sys.stdin.read()
