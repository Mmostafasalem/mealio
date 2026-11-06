"""Exercise the auth verification script against local synthetic services only."""
import http.server
import os
from pathlib import Path
import subprocess
import threading
import unittest


class AuthVerificationTests(unittest.TestCase):
    def run_check(self, leak=False):
        key='synthetic-private-key-'+'x'*48
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/api/backend/health':
                    status,body=200,(key if leak else '{"status":"ok"}')
                else:
                    status=200 if self.headers.get('X-API-Key') == key else 401
                    body='{"status":"ok"}' if status==200 else '{}'
                self.send_response(status);self.end_headers();self.wfile.write(body.encode())
            def log_message(self,*args): pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url='http://127.0.0.1:'+str(server.server_port)
        try:
            result=subprocess.run(['bash',str(Path(__file__).with_name('verify-auth.sh'))],
                env={**os.environ,'MEALIO_API_KEY':key,'BACKEND_URL':url,'WEB_URL':url},
                capture_output=True,text=True,timeout=15)
        finally: server.shutdown();server.server_close();thread.join()
        self.assertNotIn(key,result.stdout+result.stderr)
        return result

    def test_configured_services_pass_without_printing_key(self):
        self.assertEqual(self.run_check().returncode,0)

    def test_leaking_proxy_fails_without_printing_leaked_key(self):
        self.assertNotEqual(self.run_check(leak=True).returncode,0)


if __name__ == '__main__': unittest.main()
