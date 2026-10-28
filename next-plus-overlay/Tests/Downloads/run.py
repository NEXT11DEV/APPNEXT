import http.server,threading,subprocess,tempfile,pathlib,re,time,json
SIZE=17*1024*1024+37
PAYLOAD=b'PK\x03\x04'+bytes([37])*(SIZE-4)
counts={}
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_HEAD(self):
  self.send_response(200);self.send_header('Content-Length',str(SIZE));self.send_header('ETag','"fixture-v1"')
  if self.path!='/ordinary':self.send_header('Accept-Ranges','bytes')
  self.end_headers()
 def do_GET(self):
  counts[self.path]=counts.get(self.path,0)+1
  if self.path=='/html':
   self.send_response(200);self.end_headers();self.wfile.write(b'<html>not an IPA</html>');return
  value=self.headers.get('Range')
  ranged=value and self.path!='/ignored'
  start,end=map(int,re.fullmatch(r'bytes=(\d+)-(\d+)',value).groups()) if ranged else (0,SIZE-1)
  data=PAYLOAD[start:end+1]
  self.send_response(206 if ranged else 200)
  self.send_header('Content-Length',str(len(data)))
  self.send_header('ETag','"fixture-v2"' if ranged and self.path=='/changed' else '"fixture-v1"')
  if ranged:self.send_header('Content-Range',f'bytes {start}-{end}/{SIZE}')
  self.end_headers()
  try:
   if ranged and self.path=='/truncated':self.wfile.write(data[:1024]);self.close_connection=True;return
   if self.path=='/slow':time.sleep(1.5)
   self.wfile.write(data)
  except (BrokenPipeError,ConnectionResetError):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with tempfile.TemporaryDirectory() as d:
  binary=str(pathlib.Path(d)/'checks')
  subprocess.run(['swiftc','-swift-version','6','App/Services/NextIPADownload.swift','App/Services/TaifFastDownload.swift','App/Services/NextProgressThrottle.swift','App/Services/NextTransferSnapshot.swift','Tests/Downloads/Checks.swift','-o',binary],check=True)
  subprocess.run([binary,f'http://127.0.0.1:{server.server_port}'],check=True,timeout=90)
  assert counts['/parallel']==4,counts # second call must not contact server
  for path in ['/ignored','/changed','/truncated']:assert counts[path]>=5,counts
  assert counts['/ordinary']==1,counts
  print('PASS: request counts confirm four-part transport, fallback, single stream and cache hit',json.dumps(counts))
finally:server.shutdown()
