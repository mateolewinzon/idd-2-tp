#!/usr/bin/env python3
"""Verifica expiración, invalidación y reconstrucción usando API y motores reales."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from experimento import ROOT, CONFIG, CACHE, connect, prepare, lab_env, http, integrity, write


def first_score():
    return next(p for p in json.loads(http())['items'] if p['codigo']=='P-001')['resultado']['goles_local']


def verify(backend, ttl, output):
    mongo,db,redis=connect(backend); api=None
    try:
        prepare(backend,db,redis)
        with output.with_suffix('.log').open('w') as log:
            api=subprocess.Popen([str(backend/'.venv/bin/python'),'-m','uvicorn','app.main:app','--host','127.0.0.1','--port',str(CONFIG['api_port']),'--no-access-log'],
                  cwd=backend,env=lab_env(ttl),stdout=log,stderr=subprocess.STDOUT)
            for _ in range(100):
                if api.poll() is not None: raise RuntimeError('La API no inició')
                try: http();break
                except Exception: time.sleep(.1)
            else: raise RuntimeError('Timeout de inicio')
            assert first_score()==2
            # Sin invalidación: observar la antigüedad que permite el TTL.
            remaining=redis.pttl(CACHE)
            db.partidos.update_one({'_id':'P-001'},{'$set':{'resultado.goles_local':3}})
            start=time.monotonic();observations=[]
            while True:
                value=first_score();elapsed=time.monotonic()-start
                observations.append(dict(elapsed_seconds=elapsed,goles_local=value))
                if value==3: break
                assert value==2
                if elapsed>ttl+5: raise AssertionError('La caché no expiró dentro del límite')
                time.sleep(.2)
            expiry_delay=elapsed
            # Con invalidación: no esperar el TTL.
            db.partidos.update_one({'_id':'P-001'},{'$set':{'resultado.goles_local':4}})
            start=time.monotonic();redis.delete(CACHE)
            assert first_score()==4
            invalidation_delay=time.monotonic()-start
            # Una caché corrupta tampoco debe publicar contenido incorrecto.
            redis.set(CACHE,'{"items":[{}]}',ex=ttl)
            assert first_score()==4
            restored=prepare(backend,db,redis)
            final=integrity(db)
            result=dict(ttl_seconds=ttl,pttl_before_update_ms=remaining,expiry_observed_seconds=expiry_delay,
                invalidation_observed_seconds=invalidation_delay,corrupt_cache_rebuilt=True,
                observations=observations,restored=restored,integrity=final)
            write(output,result);return result
    finally:
        if api and api.poll() is None:
            api.terminate()
            try: api.wait(timeout=10)
            except subprocess.TimeoutExpired: api.kill();api.wait()
        redis.close();mongo.close()


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--backend',type=Path,required=True);args=p.parse_args()
    for ttl in (CONFIG['baseline_ttl'],CONFIG['optimized_ttl']):
        result=verify(args.backend.resolve(),ttl,ROOT/f'evidencia/frescura-ttl{ttl}.json')
        print(json.dumps({k:result[k] for k in ('ttl_seconds','expiry_observed_seconds','invalidation_observed_seconds')}))
if __name__=='__main__': main()
