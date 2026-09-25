-- esquema.cql — keyspace y tablas del módulo de comentarios (idempotente)

-- Laboratorio: nodo único
CREATE KEYSPACE IF NOT EXISTS fixture2030_comentarios
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

USE fixture2030_comentarios;

-- Q1: feed en vivo por partido y ventana de 5 min, TTL 14 días
CREATE TABLE IF NOT EXISTS comentarios_feed (
    partido_id text,
    bloque_temporal timestamp,
    comentario_id timeuuid,
    idioma varchar,
    usuario_id text,
    nombre_usuario text,
    texto text,
    estado_moderacion text,
    PRIMARY KEY ((partido_id, bloque_temporal), comentario_id)
) WITH CLUSTERING ORDER BY (comentario_id DESC)
  AND default_time_to_live = 1209600
  AND compaction = {'class': 'TimeWindowCompactionStrategy',
                    'compaction_window_unit': 'DAYS',
                    'compaction_window_size': 1};

-- Q5: histórico permanente por partido
CREATE TABLE IF NOT EXISTS comentarios_historico (
    partido_id text,
    comentario_id timeuuid,
    bloque_temporal timestamp,
    idioma varchar,
    usuario_id text,
    nombre_usuario text,
    texto text,
    estado_moderacion text,
    PRIMARY KEY (partido_id, comentario_id)
) WITH CLUSTERING ORDER BY (comentario_id ASC)
  AND compaction = {'class': 'SizeTieredCompactionStrategy'};

-- Q2: historial por usuario
CREATE TABLE IF NOT EXISTS comentarios_por_usuario (
    usuario_id text,
    comentario_id timeuuid,
    partido_id text,
    bloque_temporal timestamp,
    idioma varchar,
    texto text,
    estado_moderacion text,
    PRIMARY KEY (usuario_id, comentario_id)
) WITH CLUSTERING ORDER BY (comentario_id DESC);

-- Q3: cola de moderación por estado y fecha
CREATE TABLE IF NOT EXISTS comentarios_moderacion (
    estado_moderacion text,
    fecha date,
    comentario_id timeuuid,
    partido_id text,
    bloque_temporal timestamp,
    idioma varchar,
    usuario_id text,
    texto text,
    motivo_reporte text,
    PRIMARY KEY ((estado_moderacion, fecha), comentario_id)
) WITH CLUSTERING ORDER BY (comentario_id ASC);

-- Q4: likes por comentario
CREATE TABLE IF NOT EXISTS likes_por_comentario (
    comentario_id timeuuid,
    likes counter,
    PRIMARY KEY (comentario_id)
);

-- Q6: total de comentarios por partido
CREATE TABLE IF NOT EXISTS contadores_por_partido (
    partido_id text,
    metrica text,
    valor counter,
    PRIMARY KEY (partido_id, metrica)
);

DESCRIBE KEYSPACE fixture2030_comentarios;
