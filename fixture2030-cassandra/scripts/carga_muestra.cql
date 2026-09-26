-- carga_muestra.cql — 12 comentarios, 2 partidos, 5 usuarios
-- Idempotente: INSERT es upsert con claves fijas. Cada comentario va a feed, histórico y por_usuario.
-- Los contadores se actualizan en crud.cql.
-- El feed expira a los 14 días de cargado; el histórico no.

USE fixture2030_comentarios;

CONSISTENCY LOCAL_ONE;

-- ============================================================
-- 1. comentarios_feed (Q1)
-- ============================================================

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', '2030-06-24 20:00:00+0000', 7a759300-ec16-11f5-8123-0242ac120002, 'es', 'U001', 'Sofía', 'Gran inicio de partido', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', '2030-06-24 20:00:00+0000', aee94f00-ec16-11f5-8123-0242ac120002, 'en', 'U002', 'Mark', 'What a start!', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', '2030-06-24 20:00:00+0000', ea841900-ec16-11f5-8123-0242ac120002, 'pt', 'U003', 'Joao', 'Vamos Argentina!', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 11424f80-ec17-11f5-8123-0242ac120002, 'es', 'U001', 'Sofía', '¡Gol de Argentina!', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 43ec4800-ec17-11f5-8123-0242ac120002, 'fr', 'U004', 'Amélie', 'Quel but incroyable !', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 52d2fa80-ec17-11f5-8123-0242ac120002, 'es', 'U005', 'Omar', 'Compra seguidores baratos en mi perfil', 'PENDIENTE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', '2030-06-24 20:05:00+0000', ba894580-ec17-11f5-8123-0242ac120002, 'en', 'U002', 'Mark', 'This referee is terrible', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', '2030-06-24 20:10:00+0000', c70d9e00-ec17-11f5-8123-0242ac120002, 'pt', 'U003', 'Joao', 'Que jogada!', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('BRA-FRA-20300625', '2030-06-25 18:00:00+0000', e61b3700-ecce-11f5-8123-0242ac120002, 'fr', 'U004', 'Amélie', 'Allez les Bleus !', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('BRA-FRA-20300625', '2030-06-25 18:00:00+0000', 1ebb1080-eccf-11f5-8123-0242ac120002, 'pt', 'U003', 'Joao', 'Vai Brasil!', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('BRA-FRA-20300625', '2030-06-25 18:05:00+0000', 92f5b400-eccf-11f5-8123-0242ac120002, 'en', 'U002', 'Mark', 'Great tempo from both teams', 'VISIBLE');

INSERT INTO comentarios_feed
(partido_id, bloque_temporal, comentario_id, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('BRA-FRA-20300625', '2030-06-25 18:05:00+0000', a4d75700-eccf-11f5-8123-0242ac120002, 'ar', 'U005', 'Omar', 'ما أجمل هذه المباراة', 'VISIBLE');

-- ============================================================
-- 2. comentarios_historico (Q5)
-- ============================================================

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', 7a759300-ec16-11f5-8123-0242ac120002, '2030-06-24 20:00:00+0000', 'es', 'U001', 'Sofía', 'Gran inicio de partido', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', aee94f00-ec16-11f5-8123-0242ac120002, '2030-06-24 20:00:00+0000', 'en', 'U002', 'Mark', 'What a start!', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', ea841900-ec16-11f5-8123-0242ac120002, '2030-06-24 20:00:00+0000', 'pt', 'U003', 'Joao', 'Vamos Argentina!', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', 11424f80-ec17-11f5-8123-0242ac120002, '2030-06-24 20:05:00+0000', 'es', 'U001', 'Sofía', '¡Gol de Argentina!', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', 43ec4800-ec17-11f5-8123-0242ac120002, '2030-06-24 20:05:00+0000', 'fr', 'U004', 'Amélie', 'Quel but incroyable !', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', 52d2fa80-ec17-11f5-8123-0242ac120002, '2030-06-24 20:05:00+0000', 'es', 'U005', 'Omar', 'Compra seguidores baratos en mi perfil', 'PENDIENTE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', ba894580-ec17-11f5-8123-0242ac120002, '2030-06-24 20:05:00+0000', 'en', 'U002', 'Mark', 'This referee is terrible', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('ARG-ESP-20300624', c70d9e00-ec17-11f5-8123-0242ac120002, '2030-06-24 20:10:00+0000', 'pt', 'U003', 'Joao', 'Que jogada!', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('BRA-FRA-20300625', e61b3700-ecce-11f5-8123-0242ac120002, '2030-06-25 18:00:00+0000', 'fr', 'U004', 'Amélie', 'Allez les Bleus !', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('BRA-FRA-20300625', 1ebb1080-eccf-11f5-8123-0242ac120002, '2030-06-25 18:00:00+0000', 'pt', 'U003', 'Joao', 'Vai Brasil!', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('BRA-FRA-20300625', 92f5b400-eccf-11f5-8123-0242ac120002, '2030-06-25 18:05:00+0000', 'en', 'U002', 'Mark', 'Great tempo from both teams', 'VISIBLE');

INSERT INTO comentarios_historico
(partido_id, comentario_id, bloque_temporal, idioma, usuario_id, nombre_usuario, texto, estado_moderacion)
VALUES ('BRA-FRA-20300625', a4d75700-eccf-11f5-8123-0242ac120002, '2030-06-25 18:05:00+0000', 'ar', 'U005', 'Omar', 'ما أجمل هذه المباراة', 'VISIBLE');

-- ============================================================
-- 3. comentarios_por_usuario (Q2)
-- ============================================================

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U001', 7a759300-ec16-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:00:00+0000', 'es', 'Gran inicio de partido', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U002', aee94f00-ec16-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:00:00+0000', 'en', 'What a start!', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U003', ea841900-ec16-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:00:00+0000', 'pt', 'Vamos Argentina!', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U001', 11424f80-ec17-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 'es', '¡Gol de Argentina!', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U004', 43ec4800-ec17-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 'fr', 'Quel but incroyable !', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U005', 52d2fa80-ec17-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 'es', 'Compra seguidores baratos en mi perfil', 'PENDIENTE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U002', ba894580-ec17-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 'en', 'This referee is terrible', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U003', c70d9e00-ec17-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:10:00+0000', 'pt', 'Que jogada!', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U004', e61b3700-ecce-11f5-8123-0242ac120002, 'BRA-FRA-20300625', '2030-06-25 18:00:00+0000', 'fr', 'Allez les Bleus !', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U003', 1ebb1080-eccf-11f5-8123-0242ac120002, 'BRA-FRA-20300625', '2030-06-25 18:00:00+0000', 'pt', 'Vai Brasil!', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U002', 92f5b400-eccf-11f5-8123-0242ac120002, 'BRA-FRA-20300625', '2030-06-25 18:05:00+0000', 'en', 'Great tempo from both teams', 'VISIBLE');

INSERT INTO comentarios_por_usuario
(usuario_id, comentario_id, partido_id, bloque_temporal, idioma, texto, estado_moderacion)
VALUES ('U005', a4d75700-eccf-11f5-8123-0242ac120002, 'BRA-FRA-20300625', '2030-06-25 18:05:00+0000', 'ar', 'ما أجمل هذه المباراة', 'VISIBLE');

-- ============================================================
-- 4. comentarios_moderacion (Q3): un pendiente y un reportado
-- ============================================================

INSERT INTO comentarios_moderacion
(estado_moderacion, fecha, comentario_id, partido_id, bloque_temporal, idioma, usuario_id, texto, motivo_reporte)
VALUES ('PENDIENTE', '2030-06-24', 52d2fa80-ec17-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 'es', 'U005', 'Compra seguidores baratos en mi perfil', 'SPAM');

INSERT INTO comentarios_moderacion
(estado_moderacion, fecha, comentario_id, partido_id, bloque_temporal, idioma, usuario_id, texto, motivo_reporte)
VALUES ('REPORTADO', '2030-06-24', ba894580-ec17-11f5-8123-0242ac120002, 'ARG-ESP-20300624', '2030-06-24 20:05:00+0000', 'en', 'U002', 'This referee is terrible', 'OFENSIVO');
