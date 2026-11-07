#!/usr/bin/env python3
"""Control negativo: HTTP 200 con cuerpo incorrecto debe fallar la aserción JMeter."""
import argparse
import csv
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading
from experimento import ROOT,write

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body=b'{"items":[]}'
        self.send_response(200);self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def log_message(self,*args): pass


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--jmeter',type=Path,default=Path('/tmp/apache-jmeter-5.6.3/bin/jmeter'))
    p.add_argument('--output',type=Path,default=ROOT/'evidencia/generador_negativo')
    args=p.parse_args()
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=False)
    server=ThreadingHTTPServer(('127.0.0.1',58001),Handler)
    worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
    try:
        with (output/'console.log').open('w') as log:
            subprocess.run([str(args.jmeter),'-n','-t',str(ROOT/'carga/fixture.jmx'),'-l',str(output/'requests.jtl'),
                '-j',str(output/'jmeter.log'),'-Jusers=1','-Jramp=1','-Jduration=5','-Jthink=100',
                '-Jtimeout=1000','-Jport=58001','-Jexpected_sha='+'0'*64,f'-Jphasefile={output/"origin.txt"}',
                '-Jjmeter.save.saveservice.assertion_results_failure_message=true'],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=40)
        rows=[r for r in csv.DictReader((output/'requests.jtl').open()) if r['label']=='fixture']
        assert rows and all(r['responseCode']=='200' and r['success']=='false' and r['failureMessage']=='HTTP o contenido incorrecto' for r in rows)
        write(output/'validation.json',dict(ok=True,scenario='Control negativo, NO es carga contra el backend ni fallo del sistema medido',
              http_status=200,responses=len(rows),incorrect_bodies_rejected=len(rows)))
        print(f'Control negativo correcto: {len(rows)} cuerpos incorrectos rechazados con HTTP 200.')
    finally:
        server.shutdown();server.server_close();worker.join(timeout=5)

if __name__=='__main__':main()
