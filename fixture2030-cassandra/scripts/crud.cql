-- crud.cql — actualizaciones y eliminación (siempre con clave completa)
-- Las secciones 1 y 2 suman cada vez que se ejecutan (counter no es idempotente).

USE fixture2030_comentarios;

-- 1. Likes
CONSISTENCY LOCAL_ONE;

-- gol de Argentina
UPDATE likes_por_comentario
SET likes = likes + 3
WHERE comentario_id = 11424f80-ec17-11f5-8123-0242ac120002;

-- "Gran inicio de partido"
UPDATE likes_por_comentario
SET likes = likes + 1
WHERE comentario_id = 7a759300-ec16-11f5-8123-0242ac120002;

-- 2. Totales por partido
UPDATE contadores_por_partido
SET valor = valor + 8
WHERE partido_id = 'ARG-ESP-20300624' AND metrica = 'TOTAL_COMENTARIOS';

UPDATE contadores_por_partido
SET valor = valor + 3
WHERE partido_id = 'ARG-ESP-20300624' AND metrica = 'COMENTARIOS_ES';

UPDATE contadores_por_partido
SET valor = valor + 4
WHERE partido_id = 'BRA-FRA-20300625' AND metrica = 'TOTAL_COMENTARIOS';

-- 3. Moderación: ocultar el comentario de spam en las tres copias
CONSISTENCY LOCAL_QUORUM;

UPDATE comentarios_feed
SET estado_moderacion = 'OCULTO'
WHERE partido_id = 'ARG-ESP-20300624'
  AND bloque_temporal = '2030-06-24 20:05:00+0000'
  AND comentario_id = 52d2fa80-ec17-11f5-8123-0242ac120002;

UPDATE comentarios_historico
SET estado_moderacion = 'OCULTO'
WHERE partido_id = 'ARG-ESP-20300624'
  AND comentario_id = 52d2fa80-ec17-11f5-8123-0242ac120002;

UPDATE comentarios_por_usuario
SET estado_moderacion = 'OCULTO'
WHERE usuario_id = 'U005'
  AND comentario_id = 52d2fa80-ec17-11f5-8123-0242ac120002;

-- 4. Sacar el comentario revisado de la cola
DELETE FROM comentarios_moderacion
WHERE estado_moderacion = 'PENDIENTE'
  AND fecha = '2030-06-24'
  AND comentario_id = 52d2fa80-ec17-11f5-8123-0242ac120002;
