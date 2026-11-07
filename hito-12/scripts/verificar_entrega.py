#!/usr/bin/env python3
"""Audita que las tablas, datos crudos y fuente identifican el mismo experimento."""
import csv
from datetime import datetime
import hashlib
import json
from pathlib import Path
import tarfile
from experimento import ROOT, CONFIG, digest, write


def main():
    evidence=ROOT/'evidencia'
    source=json.loads((evidence/'source_manifest.json').read_text())
    archive=evidence/'backend-source.tar.gz'
    assert digest(archive.read_bytes())==source['archive_sha256']
    with tarfile.open(archive) as tar:
        archived={m.name.removeprefix('idd-2-backend/'):digest(tar.extractfile(m).read()) for m in tar.getmembers() if m.isfile()}
    assert archived==source['files']
    assert not any('.env' in Path(name).parts or '.git' in Path(name).parts for name in archived)
    scenarios=[];source_hashes=set();experiment_hashes=set();jmx_hashes=set();attempts=measured=errors=0
    for stage,ttl in [('baseline',5),('optimized',15)]:
        paths=list((evidence/stage).glob('*/summary.json'))
        assert len(paths)==9
        for path in paths:
            directory=path.parent
            summary=json.loads(path.read_text())
            manifest=json.loads((directory/'manifest.json').read_text())
            assert manifest['ttl']==ttl and manifest['scenario']==CONFIG
            scenarios.append((stage,manifest['users']))
            experiment_hashes.add(manifest['harness_sha256']['scripts/experimento.py'])
            jmx_hashes.add(manifest['jmx_sha256'])
            before=json.loads((directory/'integrity_before.json').read_text())
            after=json.loads((directory/'integrity_after.json').read_text())
            assert before==after and before['ok'] and before['count']==127
            source_hashes.add(before['source_sha256'])
            raw=[r for r in csv.DictReader((directory/'requests.jtl').open()) if r['label']=='fixture']
            selected=[r for r in raw if summary['window_start_ms']<=int(r['timeStamp'])<summary['window_end_ms']]
            assert len(selected)==summary['samples']
            assert sum(r['success']!='true' for r in selected)==summary['errors']==0
            assert len(raw)==summary['all_phases']['recorded_attempts']
            assert all(r['success']=='true' and r['responseCode']=='200' for r in raw)
            resources=[json.loads(line) for line in (directory/'resources.jsonl').read_text().splitlines()]
            assert resources and all('collection_error' not in r for r in resources)
            assert any(any('java' in p['executable'].lower() for p in r['processes']) for r in resources)
            attempts+=len(raw);measured+=len(selected);errors+=summary['errors']
    assert len(source_hashes)==len(experiment_hashes)==len(jmx_hashes)==1
    assert next(iter(experiment_hashes))==digest((ROOT/'scripts/experimento.py').read_bytes())
    assert next(iter(jmx_hashes))==digest((ROOT/'carga/fixture.jmx').read_bytes())
    for stage in ('baseline','optimized'):
        assert sorted(u for s,u in scenarios if s==stage)==[1,1,1,10,10,10,30,30,30]
    hypothesis=json.loads((evidence/'hipotesis_previa.json').read_text())
    first_optimized=min(datetime.fromisoformat(json.loads(p.read_text())['started_at']) for p in (evidence/'optimized').glob('*/manifest.json'))
    assert datetime.fromisoformat(hypothesis['recorded_at'])<first_optimized
    comparison=json.loads((evidence/'comparacion.json').read_text())
    assert comparison['total_measured_requests']==measured and comparison['total_measured_errors']==errors
    assert comparison['total_all_phase_attempts']==attempts
    for ttl in (5,15):
        result=json.loads((evidence/f'frescura-ttl{ttl}.json').read_text())
        assert result['corrupt_cache_rebuilt'] and result['integrity']['ok']
        assert result['expiry_observed_seconds']<ttl+5
    negative=json.loads((evidence/'generador_negativo/validation.json').read_text())
    assert negative['ok'] and negative['responses']==negative['incorrect_bodies_rejected']>0
    diagnosis=json.loads((evidence/'diagnostico.json').read_text())
    assert diagnosis['reload']['insertados']==0 and diagnosis['unchanged']
    assert 'idx_partidos_fecha_codigo' in json.dumps(diagnosis['explain']['queryPlanner']['winningPlan'])
    mart=json.loads((evidence/'data_mart.json').read_text())
    assert mart['validation']['totals_match_source'] and mart['validation']['fact_count']==2
    result=dict(ok=True,runs=18,profiles=[1,10,30],repetitions=3,measured_requests=measured,
                recorded_attempts_all_phases=attempts,measured_errors=errors,source_snapshot_verified=True,
                same_experiment_code_and_jmx=True,all_integrity_checks_passed=True,hypothesis_before_optimization=True)
    write(evidence/'verificacion_entrega.json',result)
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__': main()
