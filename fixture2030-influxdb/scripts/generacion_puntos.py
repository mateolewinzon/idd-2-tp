#!/usr/bin/env python3
"""
==============================================================================
Script: scripts/generacion_puntos.py
Proposito: Generar archivos planos en Line Protocol (.lp) para los 127 partidos
           del Mundial 2030 a partir de los datos maestros en Neo4j import.
           Genera observaciones deterministas para las 4 tablas con precision en
           segundos (s) desacoplado del motor InfluxDB.
Requisitos: Python 3 (solo biblioteca estandar).
Orden de ejecucion: 2 (segundo paso de la Fase 2).
==============================================================================
"""

import csv
import math
import os
import random
import sys
from collections import defaultdict
from datetime import datetime, timezone

# ==============================================================================
# 1. Configuracion y Constantes del Torneo
# ==============================================================================
SEMILLA_ALEATORIA = 2030  # Semilla fija para garantizar reproducibilidad exacta (RF7)
DURACION_PARTIDO_SEG = 5400  # 90 minutos de juego neto (5.400 segundos)
INTERVALO_ESTADISTICAS_SEG = 5  # 1 muestra cada 5 s (0.2 Hz)
INTERVALO_USUARIOS_SEG = 5  # 1 muestra cada 5 s (0.2 Hz)

HORARIOS_INICIO = ["13:00:00", "16:00:00", "19:00:00", "22:00:00"]

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODULE_DIR = os.path.dirname(SCRIPT_DIR)
REPO_DIR = os.path.dirname(MODULE_DIR)
IMPORT_DIR = os.path.join(REPO_DIR, "fixture2030-neo4j", "import")
OUTPUT_DIR = os.path.join(MODULE_DIR, "data", "lp")

# ==============================================================================
# 2. Carga y Verificacion de Datos Fuente (CSV Neo4j)
# ==============================================================================
def cargar_fuentes():
    # encontrado en documentacion Python (modulo csv y os.path)
    partidos_file = os.path.join(IMPORT_DIR, "partidos.csv")
    participaciones_file = os.path.join(IMPORT_DIR, "participaciones.csv")
    alineaciones_file = os.path.join(IMPORT_DIR, "alineaciones.csv")
    equipos_file = os.path.join(IMPORT_DIR, "equipos.csv")

    if not all(os.path.exists(f) for f in [partidos_file, participaciones_file, alineaciones_file, equipos_file]):
        print(f"ERROR: Archivos CSV no encontrados en {IMPORT_DIR}")
        sys.exit(1)

    with open(partidos_file, mode="r", encoding="utf-8") as f:
        partidos = list(csv.DictReader(f))

    with open(participaciones_file, mode="r", encoding="utf-8") as f:
        participaciones = list(csv.DictReader(f))

    with open(alineaciones_file, mode="r", encoding="utf-8") as f:
        alineaciones = list(csv.DictReader(f))

    with open(equipos_file, mode="r", encoding="utf-8") as f:
        equipos = list(csv.DictReader(f))

    # Mapeo de confederaciones
    confederaciones = sorted(list(set(e["confederacion"] for e in equipos if e.get("confederacion"))))

    # Participaciones por partido: {partido_id: [equipo1, equipo2]}
    partidos_equipos = defaultdict(list)
    for p in participaciones:
        partidos_equipos[p["partido_id"]].append(p["equipo_id"])

    # Titulares por partido: {partido_id: [(jugador_id, equipo_id), ...]}
    partidos_titulares = defaultdict(list)
    # Diccionario para resolver equipo del jugador
    jugador_equipo = {}
    for a in alineaciones:
        t_val = a.get("titular", "").strip().lower()
        if t_val in ["true", "1", "t", "si", "s"]:
            partido_id = a["partido_id"]
            jugador_id = a["jugador_id"]
            # En alineaciones.csv el prefijo del jugador suele identificar el equipo (ARG-10 -> ARG)
            equipo_id = jugador_id.split("-")[0]
            partidos_titulares[partido_id].append((jugador_id, equipo_id))

    return partidos, partidos_equipos, partidos_titulares, confederaciones

# ==============================================================================
# 3. Asignacion de Horarios Escalonados Realistas
# ==============================================================================
def calcular_timestamp_inicio(partidos):
    # Agrupar partidos por fecha para asignarles turnos escalonados
    partidos_por_fecha = defaultdict(list)
    for p in partidos:
        partidos_por_fecha[p["fecha"]].append(p["id"])

    horarios_partidos = {}
    for fecha, p_ids in partidos_por_fecha.items():
        for i, pid in enumerate(p_ids):
            slot = HORARIOS_INICIO[i % len(HORARIOS_INICIO)]
            # Convertir a epoch UTC en segundos (encontrado en documentacion Python: datetime.strptime)
            dt_str = f"{fecha} {slot}"
            dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
            horarios_partidos[pid] = int(dt.timestamp())

    return horarios_partidos

# ==============================================================================
# 4. Generacion de Archivos Line Protocol (.lp)
# ==============================================================================
def generar_line_protocol():
    random.seed(SEMILLA_ALEATORIA)
    partidos, partidos_equipos, partidos_titulares, confederaciones = cargar_fuentes()
    horarios_partidos = calcular_timestamp_inicio(partidos)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    total_puntos_jugadores = 0
    total_puntos_pelota = 0
    total_puntos_estadisticas = 0
    total_puntos_usuarios = 0

    print(f"Iniciando generacion de Line Protocol para {len(partidos)} partidos...")

    # Generamos archivos por tabla y partido para facilitar modularidad y carga
    for p in partidos:
        pid = p["id"]
        sede_id = p["sede_id"]
        t_base = horarios_partidos[pid]
        equipos = partidos_equipos.get(pid, ["EQ1", "EQ2"])
        eq1, eq2 = equipos[0], equipos[1] if len(equipos) > 1 else equipos[0]
        titulares = partidos_titulares.get(pid, [])

        # ----------------------------------------------------------------------
        # 4.1 tracking_pelota (1 punto cada segundo, 5.400 segundos)
        # ----------------------------------------------------------------------
        pelota_file = os.path.join(OUTPUT_DIR, f"tracking_pelota_{pid}.lp")
        # Variables de estado de pelota
        px, py, pz = 52.5, 34.0, 0.0
        with open(pelota_file, "w", encoding="utf-8") as f_pelota:
            for s in range(DURACION_PARTIDO_SEG):
                t_sec = t_base + s
                # Movimiento plausible de pelota
                px = max(1.0, min(104.0, px + random.uniform(-1.5, 1.5)))
                py = max(1.0, min(67.0, py + random.uniform(-1.2, 1.2)))
                pz = max(0.0, min(8.0, 0.0 if random.random() > 0.25 else random.uniform(0.1, 4.0)))
                vel = round(random.uniform(5.0, 95.0), 2)
                f_pelota.write(f"tracking_pelota,partido_id={pid} x_m={px:.2f},y_m={py:.2f},z_m={pz:.2f},velocidad_kmh={vel:.2f} {t_sec}\n")
                total_puntos_pelota += 1

        # ----------------------------------------------------------------------
        # 4.2 tracking_jugador (22 titulares x 5.400 segundos = 118.800 por partido)
        # ----------------------------------------------------------------------
        jugador_file = os.path.join(OUTPUT_DIR, f"tracking_jugador_{pid}.lp")
        # Inicializar posiciones de los 22 jugadores
        pos_jugadores = {}
        for j_id, eq_id in titulares:
            pos_jugadores[j_id] = {
                "x": random.uniform(10.0, 95.0),
                "y": random.uniform(10.0, 58.0),
                "dist": 0.0
            }

        with open(jugador_file, "w", encoding="utf-8") as f_jugador:
            for s in range(DURACION_PARTIDO_SEG):
                t_sec = t_base + s
                for j_id, eq_id in titulares:
                    pj = pos_jugadores[j_id]
                    # Velocidad instantanea (km/h) y desplazamiento en metros
                    vel_kmh = round(random.uniform(0.0, 31.5), 2)
                    desp_m = (vel_kmh / 3.6) * 1.0  # metros en 1 segundo
                    pj["dist"] += desp_m
                    pj["x"] = max(0.5, min(104.5, pj["x"] + random.uniform(-0.8, 0.8)))
                    pj["y"] = max(0.5, min(67.5, pj["y"] + random.uniform(-0.6, 0.6)))

                    f_jugador.write(
                        f"tracking_jugador,partido_id={pid},equipo_id={eq_id},jugador_id={j_id} "
                        f"x_m={pj['x']:.2f},y_m={pj['y']:.2f},velocidad_kmh={vel_kmh:.2f},distancia_acum_m={pj['dist']:.2f} {t_sec}\n"
                    )
                    total_puntos_jugadores += 1

        # ----------------------------------------------------------------------
        # 4.3 estadisticas_partido (cada 5 s, 2 equipos = 2.160 puntos por partido)
        # ----------------------------------------------------------------------
        est_file = os.path.join(OUTPUT_DIR, f"estadisticas_partido_{pid}.lp")
        tiros_eq1 = 0
        tiros_eq2 = 0
        with open(est_file, "w", encoding="utf-8") as f_est:
            for s in range(0, DURACION_PARTIDO_SEG, INTERVALO_ESTADISTICAS_SEG):
                t_sec = t_base + s
                # Posesion fluctuante entre rivales
                pos_eq1 = round(random.uniform(40.0, 60.0), 1)
                pos_eq2 = round(100.0 - pos_eq1, 1)

                # Tiros acumulados monótonos
                if random.random() < 0.04:
                    tiros_eq1 += 1
                if random.random() < 0.04:
                    tiros_eq2 += 1

                pases_eq1 = random.randint(2, 9)
                pases_eq2 = random.randint(2, 9)

                # Enteros con 'i' segun sintaxis de Line Protocol
                f_est.write(
                    f"estadisticas_partido,partido_id={pid},equipo_id={eq1},sede_id={sede_id} "
                    f"posesion_pct={pos_eq1:.1f},tiros_acumulados={tiros_eq1}i,pases_intervalo={pases_eq1}i {t_sec}\n"
                )
                f_est.write(
                    f"estadisticas_partido,partido_id={pid},equipo_id={eq2},sede_id={sede_id} "
                    f"posesion_pct={pos_eq2:.1f},tiros_acumulados={tiros_eq2}i,pases_intervalo={pases_eq2}i {t_sec}\n"
                )
                total_puntos_estadisticas += 2

        # ----------------------------------------------------------------------
        # 4.4 actividad_usuarios (cada 5 s, 6 confederaciones = 6.480 por partido)
        # ----------------------------------------------------------------------
        usr_file = os.path.join(OUTPUT_DIR, f"actividad_usuarios_{pid}.lp")
        with open(usr_file, "w", encoding="utf-8") as f_usr:
            for s in range(0, DURACION_PARTIDO_SEG, INTERVALO_USUARIOS_SEG):
                t_sec = t_base + s
                for conf in confederaciones:
                    # Concurrencia de espectadores (gauge entero)
                    base_aud = 250000 if conf in ["UEFA", "CONMEBOL"] else 80000
                    variacion = int(random.uniform(-15000, 25000))
                    audiencia = max(5000, base_aud + variacion)
                    f_usr.write(
                        f"actividad_usuarios,partido_id={pid},region={conf} "
                        f"usuarios_conectados={audiencia}i {t_sec}\n"
                    )
                    total_puntos_usuarios += 1

    total_general = (
        total_puntos_jugadores
        + total_puntos_pelota
        + total_puntos_estadisticas
        + total_puntos_usuarios
    )

    print("\n=== Resumen de Generacion Line Protocol ===")
    print(f"tracking_jugador:     {total_puntos_jugadores:,} puntos")
    print(f"tracking_pelota:      {total_puntos_pelota:,} puntos")
    print(f"estadisticas_partido: {total_puntos_estadisticas:,} puntos")
    print(f"actividad_usuarios:   {total_puntos_usuarios:,} puntos")
    print(f"TOTAL GENERAL:        {total_general:,} puntos")
    print(f"Directorio de salida: {OUTPUT_DIR}")

if __name__ == "__main__":
    generar_line_protocol()
