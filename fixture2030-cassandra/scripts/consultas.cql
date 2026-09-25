-- consultas.cql — Q1 a Q6, todas por clave de partición (sin ALLOW FILTERING)
-- Requiere esquema.cql, carga_muestra.cql y crud.cql.

USE fixture2030_comentarios;

CONSISTENCY LOCAL_ONE;

-- Q1. Feed de una ventana de 5 min, el más nuevo primero
SELECT comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion
FROM comentarios_feed
WHERE partido_id = 'ARG-ESP-20300624'
  AND bloque_temporal = '2030-06-24 20:05:00+0000'
LIMIT 20;

-- Q1. Página siguiente (cursor sobre comentario_id)
SELECT comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion
FROM comentarios_feed
WHERE partido_id = 'ARG-ESP-20300624'
  AND bloque_temporal = '2030-06-24 20:05:00+0000'
  AND comentario_id < ba894580-ec17-11f5-8123-0242ac120002
LIMIT 20;

-- Q2. Historial de un usuario
SELECT comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion
FROM comentarios_por_usuario
WHERE usuario_id = 'U001'
LIMIT 20;

-- Q3. Cola de moderación de un estado y un día (tras crud.cql queda el REPORTADO)
SELECT comentario_id, partido_id, bloque_temporal, idioma, usuario_id, texto, motivo_reporte
FROM comentarios_moderacion
WHERE estado_moderacion = 'REPORTADO'
  AND fecha = '2030-06-24'
LIMIT 50;

-- Q4. Likes de un comentario
SELECT comentario_id, likes
FROM likes_por_comentario
WHERE comentario_id = 11424f80-ec17-11f5-8123-0242ac120002;

-- Q5. Auditoría pospartido
CONSISTENCY LOCAL_QUORUM;

SELECT comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion
FROM comentarios_historico
WHERE partido_id = 'ARG-ESP-20300624';

-- Q6. Total de comentarios por partido
CONSISTENCY LOCAL_ONE;

SELECT metrica, valor
FROM contadores_por_partido
WHERE partido_id = 'ARG-ESP-20300624';
