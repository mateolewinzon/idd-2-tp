#!/usr/bin/env python3
"""Orquestador del laboratorio real: datos, JMeter, recursos y evidencia sin secretos."""
import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import sys
import tarfile
import threading
import time
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT/'config/escenario.json').read_text())
CACHE = 'fixture:v1:todos'
FIELDS = ('fecha_hora','fase','grupo','local','visitante','estado','resultado')

def write(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str)+'\n')

def cmd(args, **kwargs):
    return subprocess.check_output([str(x) for x in args], text=True, **kwargs).strip()

def digest(data):
    return hashlib.sha256(data).hexdigest()

def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,default=str).encode()

def lab_env(ttl):
    # No heredar conexiones de otros laboratorios. CWD de ejecución sin .env.
    prefixes = ('MONGO_','REDIS_','NEO4J_','CASSANDRA_','INFLUX_','IRIS_','API_','FIXTURE_','DB_')
    env = {k:v for k,v in os.environ.items() if not k.startswith(prefixes)}
    env.update(MONGO_URI=f'mongodb://127.0.0.1:{CONFIG["mongo_port"]}', MONGO_DATABASE=CONFIG['database'],
               REDIS_HOST='127.0.0.1', REDIS_PORT=str(CONFIG['redis_port']), REDIS_DB='0', REDIS_PASSWORD='',
               FIXTURE_CACHE_TTL_SECONDS=str(ttl), DB_TIMEOUT_SECONDS='3', INFLUX_TOKEN_FILE_ENABLED='false',
               NO_PROXY='localhost,127.0.0.1', HTTP_PROXY='', HTTPS_PROXY='', ALL_PROXY='')
    return env

def connect(backend):
    sys.path.insert(0,str(backend))
    from pymongo import MongoClient
    from redis import Redis
    mongo = MongoClient(f'mongodb://127.0.0.1:{CONFIG["mongo_port"]}', tz_aware=True, serverSelectionTimeoutMS=3000, socketTimeoutMS=3000)
    redis = Redis(host='127.0.0.1',port=CONFIG['redis_port'],decode_responses=True,socket_timeout=3)
    return mongo, mongo[CONFIG['database']], redis

def seed_module(backend):
    spec=importlib.util.spec_from_file_location('seed_h12',backend/'scripts/cargar_fixture.py')
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

def prepare(backend, db, redis):
    seed=seed_module(backend)
    docs=seed.preparar(backend/'data/fixture/import',backend/'data/fixture/fixture-calendario.json',backend/'data/fixture/fixture-escenario-demo.json')
    result=seed.cargar(db,docs,reiniciar=True)
    assert db.partidos.count_documents({})==len(docs)==127
    redis.delete(CACHE)
    return result

def source(db):
    return [{'_id':d['_id'], **{k:d[k] for k in FIELDS}} for d in db.partidos.find().sort([('fecha_hora',1),('_id',1)])]

def expected(db):
    from app.schemas.fixture import FixtureResponse
    return FixtureResponse(items=[dict(codigo=d['_id'], **{k:d[k] for k in FIELDS}) for d in source(db)]).model_dump(mode='json')

def http():
    with urlopen(f'http://127.0.0.1:{CONFIG["api_port"]}/fixture',timeout=10) as response:
        return response.read()

def integrity(db):
    docs=source(db); codes=[d['_id'] for d in docs]
    body=http(); actual=json.loads(body)
    assert actual==expected(db), 'La API no coincide con MongoDB'
    assert len(codes)==len(set(codes))==127
    return dict(ok=True,count=len(codes),states=dict(Counter(d['estado'] for d in docs)),
                source_sha256=digest(canonical(docs)),response_sha256=digest(body),response_bytes=len(body))

def snapshot(backend, out):
    """Allowlist explícita: jamás incluye .env ni .git ni datos de otros servicios."""
    target=out/'backend-source.tar.gz'
    files=[]
    for directory in ('app','data/fixture'):
        files.extend(p for p in (backend/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc')
    files += [backend/p for p in ('scripts/cargar_fixture.py','requirements.lock','requirements.txt','AGENTS.md')]
    manifest={str(p.relative_to(backend)):digest(p.read_bytes()) for p in sorted(files)}
    with tarfile.open(target,'w:gz') as tar:
        for p in sorted(files): tar.add(p,arcname='idd-2-backend/'+str(p.relative_to(backend)))
    write(out/'source_manifest.json',dict(files=manifest,archive_sha256=digest(target.read_bytes()),
          commit=cmd(['git','rev-parse','HEAD'],cwd=backend),status=cmd(['git','status','--short'],cwd=backend)))

def environment(backend):
    from importlib.metadata import version
    return dict(recorded_at=datetime.now(timezone.utc).isoformat(),platform=platform.platform(),
      architecture=platform.machine(),logical_cpus=os.cpu_count(),
      memory_bytes=cmd(['sysctl','-n','hw.memsize']) if sys.platform=='darwin' else None,
      python=sys.version,packages={name:version(name) for name in ('fastapi','uvicorn','pymongo','redis','pydantic')},
      java=cmd(['java','-version'],stderr=subprocess.STDOUT),
      docker=json.loads(cmd(['docker','info','--format','{{json .}}'])),
      images={name:json.loads(cmd(['docker','image','inspect',name,'--format','{{json .}}'])) for name in ('mongo:7.0','redis:7.4-alpine')})

def safe_environment(backend):
    e=environment(backend)
    # Reducir inspecciones a información necesaria, sin paths de usuario ni config de Docker.
    d=e['docker']; e['docker']={k:d.get(k) for k in ('ServerVersion','NCPU','MemTotal','OperatingSystem','Architecture','KernelVersion')}
    e['images']={name:{k:v.get(k) for k in ('Id','RepoDigests','Architecture','Os')} for name,v in e['images'].items()}
    return e

def resource_loop(stop, path, pids):
    with path.open('w') as stream:
        while not stop.is_set():
            item=dict(at=time.time())
            try:
                lines=cmd(['docker','stats','--no-stream','--format','{{json .}}','fixture2030-hito12-mongo-1','fixture2030-hito12-redis-1'])
                item['containers']=[json.loads(x) for x in lines.splitlines()]
                # ps %cpu es promedio del proceso; documentar esa frontera.
                process_table = cmd(['ps','-axo','pid=,ppid=,pcpu=,rss=,comm='])
                all_processes = []
                for line in process_table.splitlines():
                    parts=line.strip().split(None,4)
                    if len(parts)==5:
                        all_processes.append(dict(pid=int(parts[0]),ppid=int(parts[1]),cpu_percent=float(parts[2]),rss_kib=int(parts[3]),executable=parts[4]))
                selected=set(pids)
                for _ in range(10):
                    descendants={p['pid'] for p in all_processes if p['ppid'] in selected}
                    if descendants<=selected: break
                    selected|=descendants
                item['processes']=[p for p in all_processes if p['pid'] in selected]
                item['roots']=dict(api=pids[0],generator=pids[1])
                item['load_average']=os.getloadavg()
                if sys.platform=='darwin':
                    item['vm_stat']=cmd(['vm_stat'])
            except Exception as exc: item['collection_error']=type(exc).__name__
            stream.write(json.dumps(item)+'\n'); stream.flush()
            stop.wait(CONFIG['resource_interval_seconds'])

def percentile(values, q):
    return sorted(values)[max(0,math.ceil(len(values)*q)-1)] if values else None

def parse_logs(path, start, end):
    rows=[]; hits=misses=0
    # Timestamps de logging son locales; datetime.timestamp preserva su interpretación local.
    for line in path.read_text().splitlines():
        try: timestamp=datetime.strptime(line[:23],'%Y-%m-%d %H:%M:%S,%f').timestamp()*1000
        except ValueError: continue
        if not start<=timestamp<end: continue
        hits += 'fixture_cache=hit' in line; misses += 'fixture_cache=miss' in line
        match=re.search(r'dependency=(\w+) operation=(\w+) result=(\w+) duration_ms=([\d.]+)',line)
        if match: rows.append(dict(dependency=match[1],operation=match[2],result=match[3],ms=float(match[4])))
    return dict(cache_hits=hits,cache_misses=misses,cache_hit_ratio=hits/(hits+misses) if hits+misses else None,
      operations={f'{dep}.{op}':dict(count=len(group),errors=sum(x['result']!='ok' for x in group),
          avg_ms=statistics.mean(x['ms'] for x in group)) for dep,op in sorted({(r['dependency'],r['operation']) for r in rows})
          if (group:=[r for r in rows if r['dependency']==dep and r['operation']==op])})

def summarize(out, config):
    origin=int((out/'origin.txt').read_text()); start=origin+config['ramp_seconds']*1000; end=start+config['hold_seconds']*1000
    rows=list(csv.DictReader((out/'requests.jtl').open()))
    rows=[r for r in rows if r['label']=='fixture']
    selected=[r for r in rows if start<=int(r['timeStamp'])<end]
    lat=[int(r['elapsed']) for r in selected]; success=[r for r in selected if r['success']=='true']
    errors=Counter(r['responseCode']+':'+(r.get('failureMessage') or r['responseMessage']) for r in selected if r['success']!='true')
    summary=dict(window_start_ms=start,window_end_ms=end,window_seconds=config['hold_seconds'],samples=len(selected),
      successful=len(success),errors=len(selected)-len(success),error_types=dict(errors),
      error_rate=(len(selected)-len(success))/len(selected) if selected else None,
      throughput_success_per_second=len(success)/config['hold_seconds'],
      latency_ms=dict(min=min(lat) if lat else None,mean=statistics.mean(lat) if lat else None,
                      p50=percentile(lat,.5),p95=percentile(lat,.95),p99=percentile(lat,.99),max=max(lat) if lat else None),
      all_phases=dict(recorded_attempts=len(rows),successful=sum(r['success']=='true' for r in rows),errors=sum(r['success']!='true' for r in rows)),
      adapters=parse_logs(out/'api.log',start,end))
    write(out/'summary.json',summary); return summary

def run_one(backend, jmeter, out, ttl, users, config):
    out.mkdir(parents=True,exist_ok=False)
    mongo,db,redis=connect(backend)
    api=None; load=None; thread=None; stop=threading.Event()
    try:
        write(out/'preparation.json',prepare(backend,db,redis))
        assert redis.ping() and mongo.admin.command('ping')['ok']==1
        before=digest(canonical(source(db)))
        with (out/'api.log').open('w') as log:
            api=subprocess.Popen([str(backend/'.venv/bin/python'),'-m','uvicorn','app.main:app','--host','127.0.0.1','--port',str(CONFIG['api_port']),'--no-access-log'],
                 cwd=backend,env={**lab_env(ttl),'PYTHONPATH':str(backend)},stdout=log,stderr=subprocess.STDOUT)
            for _ in range(100):
                if api.poll() is not None: raise RuntimeError('La API terminó al iniciar')
                try: http(); break
                except Exception: time.sleep(.1)
            else: raise RuntimeError('La API no inició')
            baseline=integrity(db); write(out/'integrity_before.json',baseline)
            redis.delete(CACHE)
            warm_end=time.monotonic()+config['warmup_seconds']
            warm_count=0
            while time.monotonic()<warm_end:
                assert digest(http())==baseline['response_sha256']; warm_count+=1; time.sleep(1)
            write(out/'warmup.json',dict(requests=warm_count,seconds=config['warmup_seconds']))
            command=[str(jmeter),'-n','-t',str(ROOT/'carga/fixture.jmx'),'-l',str(out/'requests.jtl'),'-j',str(out/'jmeter.log'),
              f'-Jusers={users}',f'-Jramp={config["ramp_seconds"]}',f'-Jduration={config["ramp_seconds"]+config["hold_seconds"]}',
              f'-Jthink={config["think_ms"]}',f'-Jtimeout={config["timeout_ms"]}',f'-Jport={CONFIG["api_port"]}',
              f'-Jexpected_sha={baseline["response_sha256"]}',f'-Jphasefile={out/"origin.txt"}',
              '-Jhttpclient4.retrycount=0','-Jjmeter.save.saveservice.autoflush=true','-Jjmeter.save.saveservice.assertion_results_failure_message=true',
              '-Jjmeter.save.saveservice.timestamp_format=ms']
            write(out/'manifest.json',dict(started_at=datetime.now(timezone.utc).isoformat(),ttl=ttl,users=users,
                 scenario=config,harness_sha256={str(p.relative_to(ROOT)):digest(p.read_bytes()) for p in sorted((ROOT/'scripts').glob('*.py'))},jmx_sha256=digest((ROOT/'carga/fixture.jmx').read_bytes()),command=command,generator='Apache JMeter 5.6.3',api_workers=1,source='../../source_manifest.json'))
            with (out/'generator.log').open('w') as console:
                load=subprocess.Popen(command,stdout=console,stderr=subprocess.STDOUT,
                        env={**os.environ,'JVM_ARGS':'-Xms256m -Xmx512m'})
                thread=threading.Thread(target=resource_loop,args=(stop,out/'resources.jsonl',[api.pid,load.pid]),daemon=True);thread.start()
                abort_reason=None; limit=time.monotonic()+config['ramp_seconds']+config['hold_seconds']+45
                while load.poll() is None:
                    if time.monotonic()>limit: abort_reason='generator_deadline'; break
                    if api.poll() is not None: abort_reason='api_exited'; break
                    path=out/'requests.jtl'
                    if path.exists():
                        samples=[r for r in csv.DictReader(path.open()) if r.get('label')=='fixture' and r.get('timeStamp','').isdigit()]
                        now=time.time()*1000
                        recent=[r for r in samples if now-30000<=int(r['timeStamp'])<=now]
                        if samples and now-int(samples[0]['timeStamp'])>=30000 and recent and sum(r.get('success')!='true' for r in recent)/len(recent)>.1:
                            abort_reason='error_rate_30_seconds';break
                    stop.wait(2)
                if abort_reason:
                    write(out/'abort.json',dict(reason=abort_reason)); raise RuntimeError('Carga interrumpida: '+abort_reason)
                if load.returncode: raise RuntimeError('JMeter terminó con error')
            stop.set(); thread.join(timeout=10)
            after=integrity(db);write(out/'integrity_after.json',after)
            assert before==after['source_sha256'], 'La carga alteró MongoDB'
            assert baseline['response_sha256']==after['response_sha256']
        summary=summarize(out,config)
        assert summary['samples']>0 and summary['errors']==0
        return summary
    finally:
        stop.set()
        for process in (load,api):
            if process and process.poll() is None:
                process.terminate()
                try: process.wait(timeout=15)
                except subprocess.TimeoutExpired: process.kill();process.wait()
        if thread: thread.join(timeout=10)
        redis.close();mongo.close()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('stage',choices=['pilot','baseline','optimized','prepare','clean'])
    p.add_argument('--backend',type=Path,required=True)
    p.add_argument('--jmeter',type=Path,default=Path('/tmp/apache-jmeter-5.6.3/bin/jmeter'))
    p.add_argument('--output',type=Path,default=ROOT/'evidencia')
    args=p.parse_args(); backend=args.backend.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    if args.stage in ('prepare','clean'):
        mongo,db,redis=connect(backend)
        try:
            if args.stage=='prepare': print(json.dumps(prepare(backend,db,redis)))
            else:
                assert db.name=='fixture2030_hito12'
                print(json.dumps(dict(deleted=db.partidos.delete_many({}).deleted_count,cache_deleted=redis.delete(CACHE))))
        finally: redis.close();mongo.close()
        return
    assert args.jmeter.is_file(), 'Instalar JMeter y pasar --jmeter'
    if not (out/'source_manifest.json').exists():
        snapshot(backend,out); write(out/'environment.json',safe_environment(backend))
        shutil.copyfile(ROOT/'config/escenario.json',out/'scenario.json')
    else:
        manifest=json.loads((out/'source_manifest.json').read_text())['files']
        assert all(digest((backend/name).read_bytes())==sha for name,sha in manifest.items()), 'El backend cambió desde la línea base'
    if args.stage=='pilot':
        config={**CONFIG,'warmup_seconds':2,'ramp_seconds':2,'hold_seconds':10}
        print(json.dumps(run_one(backend,args.jmeter,out/'pilot',5,1,config)),flush=True)
    else:
        ttl=CONFIG['baseline_ttl' if args.stage=='baseline' else 'optimized_ttl']
        for rep in range(1,CONFIG['repetitions']+1):
            for users in CONFIG['profiles']:
                dest=out/args.stage/f'r{rep}-u{users}'
                if (dest/'summary.json').exists(): continue
                print(f'Iniciando {args.stage} repetición={rep} usuarios={users}',flush=True)
                summary=run_one(backend,args.jmeter,dest,ttl,users,CONFIG)
                print(json.dumps(dict(run=dest.name,p95=summary['latency_ms']['p95'],errors=summary['errors'],adapters=summary['adapters'])),flush=True)

if __name__=='__main__': main()
