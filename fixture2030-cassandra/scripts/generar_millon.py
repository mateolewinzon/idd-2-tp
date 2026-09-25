#!/usr/bin/env python3
"""Genera comentarios CSV deterministas con timeuuid v1 únicos."""

import argparse
import csv
import sys
import uuid
from datetime import datetime, timedelta, timezone


UUID_EPOCH_OFFSET = 0x01B21DD213814000
NODE_ID = 0x0242AC120002

PARTIDOS = (
    ("FINAL-20300713", datetime(2030, 7, 13, 19, 0, tzinfo=timezone.utc), 0.50),
    ("SEMI-20300709-A", datetime(2030, 7, 9, 19, 0, tzinfo=timezone.utc), 0.20),
    ("SEMI-20300710-B", datetime(2030, 7, 10, 19, 0, tzinfo=timezone.utc), 0.20),
    ("GRUPO-20300610-A", datetime(2030, 6, 10, 16, 0, tzinfo=timezone.utc), 0.025),
    ("GRUPO-20300611-B", datetime(2030, 6, 11, 16, 0, tzinfo=timezone.utc), 0.025),
    ("GRUPO-20300612-C", datetime(2030, 6, 12, 16, 0, tzinfo=timezone.utc), 0.025),
    ("GRUPO-20300613-D", datetime(2030, 6, 13, 16, 0, tzinfo=timezone.utc), 0.025),
)

IDIOMAS = ("es",) * 8 + ("en",) * 6 + ("pt",) * 3 + ("fr",) * 2 + ("ar",)


def timeuuid_from_datetime(value: datetime, sequence: int) -> uuid.UUID:
    unix_100ns = int(value.timestamp() * 10_000_000)
    timestamp = unix_100ns + UUID_EPOCH_OFFSET
    time_low = timestamp & 0xFFFFFFFF
    time_mid = (timestamp >> 32) & 0xFFFF
    time_hi_version = ((timestamp >> 48) & 0x0FFF) | 0x1000
    clock_seq = sequence & 0x3FFF
    clock_seq_hi_variant = ((clock_seq >> 8) & 0x3F) | 0x80
    clock_seq_low = clock_seq & 0xFF
    return uuid.UUID(
        fields=(
            time_low,
            time_mid,
            time_hi_version,
            clock_seq_hi_variant,
            clock_seq_low,
            NODE_ID,
        )
    )


def allocation(total: int) -> list[int]:
    counts = [int(total * weight) for _, _, weight in PARTIDOS]
    counts[0] += total - sum(counts)
    return counts


def moderation_state(index: int) -> str:
    bucket = index % 200
    if bucket == 0:
        return "REPORTADO"
    if bucket <= 3:
        return "PENDIENTE"
    return "VISIBLE"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--total", type=int, default=1_000_000)
    args = parser.parse_args()
    if args.total <= 0:
        parser.error("--total debe ser positivo")

    writer = csv.writer(sys.stdout, lineterminator="\n")
    global_index = 0

    for (partido_id, inicio, _), cantidad in zip(PARTIDOS, allocation(args.total)):
        for local_index in range(cantidad):
            # Distribuye cada partido sobre 150 minutos y redondea la clave de
            # partición al inicio del bloque de cinco minutos correspondiente.
            offset_100ns = (local_index * 9_000 * 10_000_000) // cantidad
            instante = inicio + timedelta(microseconds=offset_100ns // 10)
            bloque_segundos = (int((instante - inicio).total_seconds()) // 300) * 300
            bloque = inicio + timedelta(seconds=bloque_segundos)
            comentario_id = timeuuid_from_datetime(instante, global_index)
            usuario = f"U{global_index % 100_000:06d}"

            writer.writerow(
                (
                    partido_id,
                    bloque.strftime("%Y-%m-%d %H:%M:%S+0000"),
                    str(comentario_id),
                    IDIOMAS[global_index % len(IDIOMAS)],
                    usuario,
                    f"Usuario_{global_index % 100_000:06d}",
                    f"Comentario sintetico numero {global_index + 1}",
                    moderation_state(global_index),
                )
            )
            global_index += 1


if __name__ == "__main__":
    main()
