"""Real core routing smoke on loopback only. Never creates TUN or modifies OS routes."""
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time


def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(b"FOXWAY_LOCAL_DIRECT_FIXTURE")))
        self.end_headers()
        self.wfile.write(b'FOXWAY_LOCAL_DIRECT_FIXTURE')
    def log_message(self, *_):
        pass


server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
config = json.loads(Path(sys.argv[2]).read_text())
proxy_port, api_port, closed_port = port(), port(), port()
config['inbounds'] = [{'type':'http','tag':'route-fixture','listen':'127.0.0.1','listen_port':proxy_port}]
config['outbounds'][0]['server'] = '127.0.0.1'
config['outbounds'][0]['server_port'] = closed_port
config['dns'] = {'servers':[{'type':'hosts','tag':'bootstrap','predefined':{
    'local.fixture.ru':['127.0.0.1'], 'local.fixture.com':['127.0.0.1']}}], 'final':'bootstrap'}
config['experimental']['clash_api']['external_controller'] = f'127.0.0.1:{api_port}'
core = subprocess.Popen([sys.argv[1], 'run', '-c', 'stdin'], stdin=subprocess.PIPE,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    core.stdin.write(json.dumps(config).encode());core.stdin.close()
    for _ in range(50):
        if core.poll() is not None:
            raise RuntimeError('Fixture core exited')
        try:
            with socket.create_connection(('127.0.0.1', proxy_port), timeout=.1):
                break
        except OSError:
            time.sleep(.1)
    def fetch(domain):
        connection = http.client.HTTPConnection('127.0.0.1', proxy_port, timeout=5)
        try:
            connection.request('GET', f'http://{domain}:{server.server_port}/')
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()
    status, body = fetch('local.fixture.ru')
    assert status == 200 and body == b'FOXWAY_LOCAL_DIRECT_FIXTURE', (status, body)
    try:
        status, body = fetch('local.fixture.com')
        assert status != 200 and body != b'FOXWAY_LOCAL_DIRECT_FIXTURE'
    except (http.client.RemoteDisconnected, ConnectionError):
        pass
    print('Native routing PASS: .ru direct; other domain cannot leak to direct when proxy fails')
finally:
    core.terminate()
    try:core.wait(timeout=5)
    except subprocess.TimeoutExpired:core.kill();core.wait()
    server.shutdown();server.server_close();thread.join()
