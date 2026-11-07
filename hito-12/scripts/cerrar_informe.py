#!/usr/bin/env python3
"""Escribe conclusiones desde resultados ya medidos y controles de frescura."""
import json
from experimento import ROOT


def main():
    evidence=ROOT/'evidencia'
    comparison=json.loads((evidence/'comparacion.json').read_text())
    formatted_total=format(comparison['total_measured_requests'],',').replace(',','.')
    base=[r for r in comparison['runs'] if r['stage']=='baseline']
    opt=[r for r in comparison['runs'] if r['stage']=='optimized']
    b=sum(r['mongo_queries'] for r in base);o=sum(r['mongo_queries'] for r in opt)
    freshness=[json.loads((evidence/f'frescura-ttl{ttl}.json').read_text()) for ttl in (5,15)]
    lines=['# Conclusiones del experimento','',
      f"Se completaron 18 corridas principales, con {formatted_total} respuestas HTTP correctas dentro de las ventanas sostenidas y {comparison['total_measured_errors']} errores medidos. Los 127 partidos conservaron contenido, códigos únicos y orden antes/después de cada corrida.", '',
      f'El cambio de TTL de 5 a 15 s redujo las consultas MongoDB de {b} a {o} en el conjunto de ventanas sostenidas ({(1-o/b)*100:.1f}% menos). Esto respalda la hipótesis de menor trabajo repetido para este listado compartido; no demuestra saturación previa ni capacidad máxima posterior.', '',
      '## Latencia por perfil','']
    for users in (1,10,30):
        a=next(x for x in comparison['aggregate'] if x['users']==users and x['stage']=='baseline')
        z=next(x for x in comparison['aggregate'] if x['users']==users and x['stage']=='optimized')
        lines.append(f"- {users} lectores: p95 medio de corridas {a['p95_mean']:.2f} → {z['p95_mean']:.2f} ms; rango base {a['p95_min']}–{a['p95_max']} ms y variante {z['p95_min']}–{z['p95_max']} ms. p99 medio {a['p99_mean']:.2f} → {z['p99_mean']:.2f} ms. Throughput medio {a['throughput_mean']:.3f} → {z['throughput_mean']:.3f} respuestas correctas/s.")
    regressions=[]
    for users in (1,10,30):
        a=next(x for x in comparison['aggregate'] if x['users']==users and x['stage']=='baseline')
        z=next(x for x in comparison['aggregate'] if x['users']==users and x['stage']=='optimized')
        if z['p99_mean']>a['p99_mean']: regressions.append(str(users))
    if regressions:
        lines+=['', 'Se observó una regresión del p99 medio con '+', '.join(regressions)+' lectores. La variante no mejora uniformemente la latencia; se conserva esa regresión aunque disminuyan el p95 y las consultas.']
    lines+=['','La tasa está limitada deliberadamente por la pausa de un segundo. La variación entre corridas y el host compartido impiden atribuir cada diferencia de latencia exclusivamente al TTL. La tabla completa conserva p99, errores, recursos y resultados individuales; no se selecciona sólo la mejor corrida. El consumo de memoria de MongoDB creció a lo largo de las corridas y no se reinició el motor entre variantes; no se atribuye ese crecimiento al TTL ni se afirma ahorro general de memoria.','',
      '## Costo de frescura comprobado','']
    for f in freshness:
        lines.append(f"- TTL {f['ttl_seconds']} s: cambio sin invalidar visible después de {f['expiry_observed_seconds']:.3f} s; con invalidación, primera lectura correcta después de {f['invalidation_observed_seconds']*1000:.2f} ms. Caché inválida reconstruida correctamente.")
    lines+=['','Son retrasos observados en actualizaciones controladas, con sondeo cada 200 ms; no máximos garantizados ni latencias de producción.','',
      '## Decisión y alcance','',
      'Conservar la variante de 15 s como configuración explícita del experimento para consultas previas al partido cuando se acepta esa antigüedad. Mantener 5 s como valor por defecto del backend: el marcador en vivo no adopta automáticamente la tolerancia de este caso. Las escrituras deben invalidar la caché; el TTL limita el tiempo de una copia vieja si eso falla. El cambio no elimina reconstrucciones concurrentes al vencer una clave.', '',
      'La integridad se verificó con comparación contra MongoDB y huellas de cada respuesta. El control negativo confirma que HTTP 200 con contenido incorrecto falla la validación. La propuesta de Data Mart tiene un prototipo validado de dos filas para el único partido finalizado de la demo y pruebas de corrección/reintento; no es una plataforma BI ni una integración de seis motores. La alternativa SQL es conceptual, sin cifras experimentales inventadas.', '',
      'El resultado se limita a esta notebook, dataset de 127 partidos y carga cerrada de hasta 30 lectores. No se midieron ingesta masiva, replicación, regiones, saturación máxima ni rendimiento SQL. Prometheus y Grafana quedan para el Hito 13, según la clase de monitoreo.','']
    (ROOT/'docs/conclusiones.md').write_text('\n'.join(lines))
    print(f'Conclusiones generadas: MongoDB {b} → {o}; {(1-o/b)*100:.1f}% menos.')

if __name__=='__main__':main()
