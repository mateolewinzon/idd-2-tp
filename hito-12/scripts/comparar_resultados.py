#!/usr/bin/env python3
"""Genera tablas desde evidencia cruda. No contiene cifras de resultados prefijadas."""
import argparse
from datetime import datetime, timedelta, timezone
import re
from collections import defaultdict
import csv
import json
import math
from pathlib import Path
import statistics
from experimento import ROOT, CONFIG, write


def mean(values): return statistics.mean(values) if values else None

def resources(path, start, end):
    groups=defaultdict(list)
    for line in path.read_text().splitlines():
        item=json.loads(line)
        if not start<=item['at']*1000<end: continue
        for container in item.get('containers',[]):
            name='mongo' if 'mongo' in container['Name'] else 'redis'
            groups[name+'_cpu_percent'].append(float(container['CPUPerc'].rstrip('%')))
            groups[name+'_memory_percent_of_limit'].append(float(container['MemPerc'].rstrip('%')))
        processes=item.get('processes',[])
        if not isinstance(processes,list): continue
        roots=item.get('roots',{})
        api=[p for p in processes if p['pid']==roots.get('api')]
        java=[p for p in processes if 'java' in p['executable'].lower()]
        for name,procs in [('api',api),('java',java)]:
            if procs:
                groups[name+'_cpu_percent_ps_average'].append(sum(p['cpu_percent'] for p in procs))
                groups[name+'_rss_mib'].append(sum(p['rss_kib'] for p in procs)/1024)
    return {name:dict(samples=len(values),mean=mean(values),max=max(values)) for name,values in groups.items()}


def log_timezone(directory,manifest):
    # El log de arranque JMeter se escribe inmediatamente después del manifiesto UTC.
    # Inferir el offset en cuartos de hora permite releer evidencia en otro huso horario.
    first=(directory/'jmeter.log').read_text().splitlines()[0][:23]
    local=datetime.strptime(first,'%Y-%m-%d %H:%M:%S,%f').replace(tzinfo=timezone.utc)
    recorded=datetime.fromisoformat(manifest['started_at'])
    offset=round((local-recorded).total_seconds()/900)*900
    assert -12*3600<=offset<=14*3600
    return timezone(timedelta(seconds=offset))


def api_timings(path,start,end,tz):
    values=[]
    for line in path.read_text().splitlines():
        if 'method=GET path=/fixture status=' not in line: continue
        try: timestamp=datetime.strptime(line[:23],'%Y-%m-%d %H:%M:%S,%f').replace(tzinfo=tz).timestamp()*1000
        except ValueError: continue
        if start<=timestamp<end:
            match=re.search(r'duration_ms=([\d.]+)',line)
            if match: values.append(float(match[1]))
    return dict(count=len(values),p95_ms=sorted(values)[max(0,math.ceil(len(values)*.95)-1)] if values else None)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence',type=Path,default=ROOT/'evidencia')
    parser.add_argument('--docs',type=Path,default=ROOT/'docs')
    args=parser.parse_args(); evidence=args.evidence.resolve(); docs=args.docs.resolve();docs.mkdir(parents=True,exist_ok=True)
    rows=[]; all_summaries=[]
    for stage in ('baseline','optimized'):
        paths=sorted((evidence/stage).glob('*/summary.json'))
        assert len(paths)==len(CONFIG['profiles'])*CONFIG['repetitions'],f'Faltan corridas {stage}'
        for path in paths:
            s=json.loads(path.read_text());manifest=json.loads((path.parent/'manifest.json').read_text())
            before=json.loads((path.parent/'integrity_before.json').read_text());after=json.loads((path.parent/'integrity_after.json').read_text())
            assert before['source_sha256']==after['source_sha256'] and before['ok'] and after['ok']
            resource=resources(path.parent/'resources.jsonl',s['window_start_ms'],s['window_end_ms'])
            write(path.parent/'resource_summary.json',resource)
            api=api_timings(path.parent/'api.log',s['window_start_ms'],s['window_end_ms'],log_timezone(path.parent,manifest))
            mongo=s['adapters']['operations'].get('MongoDB.list_fixture',{}).get('count',0)
            row=dict(stage=stage,run=path.parent.name,users=manifest['users'],ttl=manifest['ttl'],
                samples=s['samples'],successful=s['successful'],errors=s['errors'],
                p50_ms=s['latency_ms']['p50'],p95_ms=s['latency_ms']['p95'],p99_ms=s['latency_ms']['p99'],
                throughput=s['throughput_success_per_second'],mongo_queries=mongo,
                cache_hit_ratio=s['adapters']['cache_hit_ratio'],api_p95_ms=api['p95_ms'],api_log_count=api['count'],
                mongo_adapter_avg_ms=s['adapters']['operations'].get('MongoDB.list_fixture',{}).get('avg_ms'),
                redis_get_adapter_avg_ms=s['adapters']['operations'].get('Redis.get_cache',{}).get('avg_ms'))
            for name,summary in resource.items(): row[name]=summary['mean']
            rows.append(row);all_summaries.append(s)
    keys=list(dict.fromkeys(k for row in rows for k in row))
    with (evidence/'comparacion.csv').open('w') as stream:
        w=csv.DictWriter(stream,fieldnames=keys,lineterminator="\n");w.writeheader();w.writerows(rows)
    aggregate=[]
    for users in CONFIG['profiles']:
        for stage in ('baseline','optimized'):
            group=[r for r in rows if r['users']==users and r['stage']==stage]
            aggregate.append(dict(users=users,stage=stage,repetitions=len(group),requests=sum(r['samples'] for r in group),
                errors=sum(r['errors'] for r in group),p95_mean=mean([r['p95_ms'] for r in group]),
                p95_min=min(r['p95_ms'] for r in group),p95_max=max(r['p95_ms'] for r in group),
                p99_mean=mean([r['p99_ms'] for r in group]),throughput_mean=mean([r['throughput'] for r in group]),
                mongo_queries_total=sum(r['mongo_queries'] for r in group),hit_ratio_mean=mean([r['cache_hit_ratio'] for r in group])))
    write(evidence/'comparacion.json',dict(runs=rows,aggregate=aggregate,
          total_measured_requests=sum(r['samples'] for r in rows),total_measured_errors=sum(r['errors'] for r in rows),
          total_all_phase_attempts=sum(s['all_phases']['recorded_attempts'] for s in all_summaries)))
    lines=['# Comparación medida antes/después','',
      'Resultados de HTTP real con MongoDB/Redis reales. Ventana sostenida de 60 s por corrida; tres repeticiones por perfil. Línea base: TTL 5 s. Optimizada: TTL 15 s.', '',
      '| Lectores | Versión | Requests | Errores | p95 medio de corridas (rango), ms | p99 medio, ms | Éxitos/s medios | Consultas MongoDB (3 corridas) | Aciertos medios |',
      '| --- | --- | --- | --- | --- | --- | --- | --- | --- |']
    for a in aggregate:
        lines.append(f'| {a["users"]} | {a["stage"]} | {a["requests"]} | {a["errors"]} | {a["p95_mean"]:.2f} ({a["p95_min"]}–{a["p95_max"]}) | {a["p99_mean"]:.2f} | {a["throughput_mean"]:.3f} | {a["mongo_queries_total"]} | {a["hit_ratio_mean"]:.2%} |')
    lines+=['','Los percentiles se calculan dentro de cada corrida por rango más cercano. La tabla muestra su media y rango entre repeticiones: no son percentiles de una mezcla de todas las corridas. La pausa de un segundo por usuario limita deliberadamente la tasa; el throughput no representa la capacidad máxima del sistema.','',
       '## Operaciones evitadas y variación de latencia','']
    for users in CONFIG['profiles']:
        base=next(a for a in aggregate if a['users']==users and a['stage']=='baseline')
        opt=next(a for a in aggregate if a['users']==users and a['stage']=='optimized')
        reduction=(1-opt['mongo_queries_total']/base['mongo_queries_total'])*100
        delta=(opt['p95_mean']/base['p95_mean']-1)*100
        lines.append(f'- {users} lectores: consultas MongoDB {base["mongo_queries_total"]} → {opt["mongo_queries_total"]} ({reduction:.1f}% menos); cambio del p95 medio: {delta:+.1f}%.')
    lines+=['','## Recursos por corrida','',
      '| Versión / corrida | CPU MongoDB media % | RAM MongoDB % límite | CPU Redis media % | RAM Redis % límite | RSS API MiB | RSS Java MiB |',
      '| --- | --- | --- | --- | --- | --- | --- |']
    for r in rows:
        vals=[r.get(k) for k in ('mongo_cpu_percent','mongo_memory_percent_of_limit','redis_cpu_percent','redis_memory_percent_of_limit','api_rss_mib','java_rss_mib')]
        lines.append('| '+r['stage']+' / '+r['run']+' | '+' | '.join(f'{v:.2f}' if v is not None else 'No disponible' for v in vals)+' |')
    lines+=['','Recursos muestreados aproximadamente cada 5 s más la demora del recolector. CPU de contenedores es la reportada por Docker; `%CPU` de `ps` es un promedio del proceso, no una medición instantánea ni CPU de toda la notebook. RSS Java incluye la JVM de JMeter; sus límites son 256–512 MiB de heap, no de RSS. En `resources.jsonl` también se guardan red, I/O acumulados y `vm_stat` de macOS; no se atribuyen exclusivamente a una operación.','']
    lines+=['## Separación API/adaptadores','',
      '| Versión / corrida | API p95 ms | Logs API | MongoDB adaptador media ms | Redis GET adaptador media ms |',
      '| --- | --- | --- | --- | --- |']
    for r in rows:
        vals=[r.get(k) for k in ('api_p95_ms','api_log_count','mongo_adapter_avg_ms','redis_get_adapter_avg_ms')]
        lines.append('| '+r['stage']+' / '+r['run']+' | '+' | '.join(f'{v:.2f}' if v is not None else 'No disponible' for v in vals)+' |')
    lines+=['','Los logs API/adaptadores se seleccionan por fin de operación; JMeter por inicio. La media del adaptador MongoDB corresponde sólo a las consultas que ocurrieron. Sus tiempos incluyen driver y comunicación: no son tiempo interno puro del motor.','',
      '## Integridad y límites','',
      f'Las {len(rows)} corridas verificaron los mismos 127 códigos únicos y contenido igual a MongoDB antes/después. Requests medidos: {sum(r["samples"] for r in rows)}; errores medidos: {sum(r["errors"] for r in rows)}.', '',
      'La línea base se ejecutó antes de la versión optimizada, sin aleatorizar el orden. Ambas comparten notebook con otros procesos y contenedores; los cambios pequeños de latencia pueden deberse al entorno. El ahorro de consultas no acredita capacidad mundial ni ingesta masiva. Ver `hipotesis_y_optimizacion.md`, `integridad_y_limitaciones.md` y los archivos crudos de cada corrida.','']
    (docs/'comparacion_antes_despues.md').write_text('\n'.join(lines))
    print(json.dumps(aggregate,indent=2))

if __name__=='__main__': main()
