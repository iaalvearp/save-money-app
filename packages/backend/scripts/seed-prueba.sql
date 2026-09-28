-- ============================================================================
-- Datos de prueba para probar los flujos de la app esta noche.
-- ============================================================================
--
-- QUE HACE
--   Carga, sobre las cuentas que ya existen, un comercio, una promocion Flash y
--   tres eventos Hunt con sus rondas, premios, patrocinadores y entradas, mas
--   dos facturas. Todo queda marcado con el prefijo "PRUEBA " (o, en las tablas
--   que no tienen nombre, con una clave de acceso que empieza con 99999) para
--   que scripts/seed-prueba-limpiar.sql pueda borrarlo sin tocar nada mas.
--
-- COMO SE EJECUTA
--   pnpm wrangler d1 execute save-money-db --remote --file scripts/seed-prueba.sql
--
-- SE PUEDE EJECUTAR VARIAS VECES
--   Si. Cada insercion va protegida: los registros con nombre se buscan por su
--   nombre y la relacion con su evento o comercio, y los que tienen una clave
--   unica usan ON CONFLICT. Volver a correrlo no duplica nada.
--   Para que las fechas se refresquen (por ejemplo si se corre al dia
--   siguiente), hay que correr antes el script de limpieza.
--
-- REQUISITOS (verificados antes de cargar)
--   Estas tres cuentas tienen que existir. No se crean ni se les cambia la
--   contrasena, este script solo las usa:
--     cliente      test@test.com
--     negocio      negocio@test.com
--     organizador  organizador@test.com
--   Si falta alguna, los INSERT ... SELECT de abajo no insertan nada y las
--   comprobaciones finales devuelven 0, en vez de dejar datos a medias.
--
-- FECHAS
--   Todo se calcula con la hora de Ecuador (UTC-5) en el momento de correr el
--   script, no con fechas fijas, para que "hoy" sea hoy sin importar cuando se
--   ejecute. Formato AAAA-MM-DD HH:MM:SS, el mismo que espera el backend para
--   eventos y rondas. Las facturas usan ISO con offset -05:00, como el SRI.
--
-- OJO CON LAS FACTURAS
--   Las dos facturas son de "hace 1 hora" y "hace 2 horas", tal como se pidio.
--   Los eventos empiezan hoy a las 00:00:00, asi que para que esas facturas
--   cuenten para el premio por frecuencia hay que correr este script despues de
--   las 02:00 de Ecuador. Si se corre antes, las facturas caen en el dia
--   anterior y quedan fuera de la ventana del evento.
--
-- LO QUE NO SE PIDE Y SE ASUMIO
--   - categoria 'Cafeteria' en el comercio y en la promocion, para que las
--     listas por categoria no salgan vacias.
--   - precio_entrada 10.00 en los dos eventos que requieren entrada, y el
--     mismo monto en la entrada, para que el flujo de compra tenga un precio que
--     mostrar. El otro evento no requiere entrada y no lleva precio.
--   - descripcion corta en la promocion Flash.
--   - La ronda de cada evento se llama "PRUEBA Ronda unica" y va sin ronda
--     asignada en los premios, porque el pedido era que los premios no dependen
--     de ninguna ronda.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) Comercio de negocio@test.com
--    Si ya tiene un comercio (tiene uno), se actualiza; si no, se crea.
-- ---------------------------------------------------------------------------
INSERT INTO comercios
  (usuario_id, nombre, categoria, ruc, latitud, longitud,
   es_patrocinado, horario, hora_apertura, hora_cierre)
SELECT
  u.id, 'PRUEBA Café Central', 'Cafetería', '0991234561001',
  -2.1894, -79.8891, 0, 'Todos los días 00:00 - 23:59', '00:00', '23:59'
FROM usuarios u
WHERE u.email = 'negocio@test.com'
  AND NOT EXISTS (
    SELECT 1 FROM comercios c WHERE c.usuario_id = u.id
  );

UPDATE comercios
SET nombre        = 'PRUEBA Café Central',
    categoria     = 'Cafetería',
    ruc           = '0991234561001',
    latitud       = -2.1894,
    longitud      = -79.8891,
    es_patrocinado = 0,
    horario       = 'Todos los días 00:00 - 23:59',
    hora_apertura = '00:00',
    hora_cierre   = '23:59'
WHERE usuario_id = (SELECT id FROM usuarios WHERE email = 'negocio@test.com');


-- ---------------------------------------------------------------------------
-- 2) Promocion Flash de ese comercio
--    Activa de hoy 00:00:00 hasta hoy + 7 dias, con el maximo radio de 20 km.
--    La columna se llama radio_km y la app la muestra como km, asi que 20.
-- ---------------------------------------------------------------------------
INSERT INTO promociones_flash
  (comercio_id, titulo, descripcion, descuento_porcentaje,
   inicia_en, termina_en, latitud, longitud, radio_km, categoria, max_usuarios)
SELECT
  c.id, 'PRUEBA 2x1 en cafés', 'Promoción de prueba para verificar el flujo Flash', 50,
  strftime('%Y-%m-%d %H:%M:%S', 'now', '-5 hours', 'start of day'),
  strftime('%Y-%m-%d %H:%M:%S', 'now', '-5 hours', 'start of day', '+7 days'),
  -2.1894, -79.8891, 20, 'Cafetería', NULL
FROM comercios c
WHERE c.nombre = 'PRUEBA Café Central'
  AND NOT EXISTS (
    SELECT 1 FROM promociones_flash p
    WHERE p.comercio_id = c.id AND p.titulo = 'PRUEBA 2x1 en cafés'
  );


-- ---------------------------------------------------------------------------
-- 3) Tres eventos de organizador@test.com
--    Hoy 00:00:00 hasta hoy + 3 dias 23:59:59, estado 'programado', que es el
--    estado de un evento que todavia no se ha iniciado.
-- ---------------------------------------------------------------------------

-- A) Requiere entrada. Premios: principal, consolacion y frecuencia (3).
INSERT INTO eventos
  (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada, estado)
SELECT
  u.id, 'PRUEBA Hunt Norte',
  strftime('%Y-%m-%d %H:%M:%S', 'now', '-5 hours', 'start of day'),
  strftime('%Y-%m-%d %H:%M:%S', 'now', '-5 hours', 'start of day', '+3 days', '23:59:59'),
  1, 10.00, 'programado'
FROM usuarios u
WHERE u.email = 'organizador@test.com'
  AND NOT EXISTS (
    SELECT 1 FROM eventos e WHERE e.nombre = 'PRUEBA Hunt Norte'
  );

-- B) No requiere entrada. Premios: principal y frecuencia (2).
INSERT INTO eventos
  (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada, estado)
SELECT
  u.id, 'PRUEBA Hunt Sur',
  strftime('%Y-%m-%d %H:%M:%S', 'now', '-5 hours', 'start of day'),
  strftime('%Y-%m-%d %H:%M:%S', 'now', '-5 hours', 'start of day', '+3 days', '23:59:59'),
  0, NULL, 'programado'
FROM usuarios u
WHERE u.email = 'organizador@test.com'
  AND NOT EXISTS (
    SELECT 1 FROM eventos e WHERE e.nombre = 'PRUEBA Hunt Sur'
  );

-- C) Requiere entrada. Premio: solo el principal.
INSERT INTO eventos
  (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada, estado)
SELECT
  u.id, 'PRUEBA Hunt Centro',
  strftime('%Y-%m-%d %H:%M:%S', 'now', '-5 hours', 'start of day'),
  strftime('%Y-%m-%d %H:%M:%S', 'now', '-5 hours', 'start of day', '+3 days', '23:59:59'),
  1, 10.00, 'programado'
FROM usuarios u
WHERE u.email = 'organizador@test.com'
  AND NOT EXISTS (
    SELECT 1 FROM eventos e WHERE e.nombre = 'PRUEBA Hunt Centro'
  );


-- ---------------------------------------------------------------------------
-- 4) Una ronda por evento, cubriendo todo el evento
-- ---------------------------------------------------------------------------
INSERT INTO rondas (evento_id, nombre, hora_inicio, hora_fin)
SELECT e.id, 'PRUEBA Ronda única', e.fecha_inicio, e.fecha_fin
FROM eventos e
WHERE e.nombre IN ('PRUEBA Hunt Norte', 'PRUEBA Hunt Sur', 'PRUEBA Hunt Centro')
  AND NOT EXISTS (
    SELECT 1 FROM rondas r
    WHERE r.evento_id = e.id AND r.nombre = 'PRUEBA Ronda única'
  );


-- ---------------------------------------------------------------------------
-- 5) Premios, todos SIN ronda (ronda_id NULL)
-- ---------------------------------------------------------------------------

-- A) Norte: principal (1), consolacion (5), frecuencia (5, criterio 3).
INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo, criterio_frecuencia)
SELECT e.id, NULL, 'PRUEBA Premio principal', 1, 'principal', NULL
FROM eventos e
WHERE e.nombre = 'PRUEBA Hunt Norte'
  AND NOT EXISTS (
    SELECT 1 FROM premios p
    WHERE p.evento_id = e.id AND p.nombre = 'PRUEBA Premio principal'
  );

INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo, criterio_frecuencia)
SELECT e.id, NULL, 'PRUEBA Premio consolación', 5, 'consolacion', NULL
FROM eventos e
WHERE e.nombre = 'PRUEBA Hunt Norte'
  AND NOT EXISTS (
    SELECT 1 FROM premios p
    WHERE p.evento_id = e.id AND p.nombre = 'PRUEBA Premio consolación'
  );

INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo, criterio_frecuencia)
SELECT e.id, NULL, 'PRUEBA Premio frecuente', 5, 'frecuencia', 3
FROM eventos e
WHERE e.nombre = 'PRUEBA Hunt Norte'
  AND NOT EXISTS (
    SELECT 1 FROM premios p
    WHERE p.evento_id = e.id AND p.nombre = 'PRUEBA Premio frecuente'
  );

-- B) Sur: principal (1) y frecuencia (5, criterio 2).
INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo, criterio_frecuencia)
SELECT e.id, NULL, 'PRUEBA Premio principal', 1, 'principal', NULL
FROM eventos e
WHERE e.nombre = 'PRUEBA Hunt Sur'
  AND NOT EXISTS (
    SELECT 1 FROM premios p
    WHERE p.evento_id = e.id AND p.nombre = 'PRUEBA Premio principal'
  );

INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo, criterio_frecuencia)
SELECT e.id, NULL, 'PRUEBA Premio frecuente', 5, 'frecuencia', 2
FROM eventos e
WHERE e.nombre = 'PRUEBA Hunt Sur'
  AND NOT EXISTS (
    SELECT 1 FROM premios p
    WHERE p.evento_id = e.id AND p.nombre = 'PRUEBA Premio frecuente'
  );

-- C) Centro: solo el principal (1).
INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo, criterio_frecuencia)
SELECT e.id, NULL, 'PRUEBA Premio principal', 1, 'principal', NULL
FROM eventos e
WHERE e.nombre = 'PRUEBA Hunt Centro'
  AND NOT EXISTS (
    SELECT 1 FROM premios p
    WHERE p.evento_id = e.id AND p.nombre = 'PRUEBA Premio principal'
  );


-- ---------------------------------------------------------------------------
-- 6) Patrocinador: PRUEBA Café Central en cada evento
--    A y C quedan 'pendiente', B queda 'aprobado'. La tabla tiene
--    UNIQUE (evento_id, comercio_id), asi que se resuelve con ON CONFLICT y el
--    estado se corrige si se vuelve a correr el script.
-- ---------------------------------------------------------------------------
INSERT INTO eventos_sponsors (evento_id, comercio_id, estado, responded_at)
SELECT e.id, c.id, 'pendiente', NULL
FROM eventos e, comercios c
WHERE e.nombre IN ('PRUEBA Hunt Norte', 'PRUEBA Hunt Centro')
  AND c.nombre = 'PRUEBA Café Central'
ON CONFLICT (evento_id, comercio_id) DO UPDATE SET estado = 'pendiente';

INSERT INTO eventos_sponsors (evento_id, comercio_id, estado, responded_at)
SELECT e.id, c.id, 'aprobado', datetime('now')
FROM eventos e, comercios c
WHERE e.nombre = 'PRUEBA Hunt Sur'
  AND c.nombre = 'PRUEBA Café Central'
ON CONFLICT (evento_id, comercio_id) DO UPDATE
  SET estado = 'aprobado', responded_at = datetime('now');


-- ---------------------------------------------------------------------------
-- 7) Entradas de test@test.com para los dos eventos que requieren entrada
--    En 'pendiente_revision_comprobante', con un comprobante minimo: un PNG de
--    1x1 en base64, que es justo lo que espera la app para poder mostrarlo.
-- ---------------------------------------------------------------------------
INSERT INTO entradas (evento_id, cliente_id, estado, comprobante_foto, monto)
SELECT
  e.id, u.id, 'pendiente_revision_comprobante',
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGO4efMmAAUaAoy1sJipAAAAAElFTkSuQmCC',
  e.precio_entrada
FROM eventos e, usuarios u
WHERE e.nombre IN ('PRUEBA Hunt Norte', 'PRUEBA Hunt Centro')
  AND u.email = 'test@test.com'
  AND NOT EXISTS (
    SELECT 1 FROM entradas t WHERE t.evento_id = e.id AND t.cliente_id = u.id
  );


-- ---------------------------------------------------------------------------
-- 8) Dos facturas de test@test.com, aprobadas, nivel 1, en PRUEBA Café Central
--    De hace 1 hora y de hace 2 horas, montos 10.00 y 12.50, con claves de
--    acceso de 49 digitos que empiezan con 99999.
--    La clave es unica en la base, asi que ON CONFLICT evita duplicar y ademas
--    refresca montos y fechas si se vuelve a correr el script.
-- ---------------------------------------------------------------------------
INSERT INTO facturas
  (cliente_id, comercio_id, evento_id, nivel_verificacion, clave_acceso_49,
   fecha_factura, monto_total, estado)
SELECT
  u.id, c.id, NULL, 1, '9999900000000000000000000000000000000002026092801',
  strftime('%Y-%m-%dT%H:%M:%S-05:00', 'now', '-5 hours', '-1 hour'),
  10.00, 'aprobada'
FROM usuarios u, comercios c
WHERE u.email = 'test@test.com' AND c.nombre = 'PRUEBA Café Central'
ON CONFLICT (clave_acceso_49) DO UPDATE SET
  cliente_id          = excluded.cliente_id,
  comercio_id         = excluded.comercio_id,
  nivel_verificacion  = excluded.nivel_verificacion,
  fecha_factura       = excluded.fecha_factura,
  monto_total         = excluded.monto_total,
  estado              = excluded.estado;

INSERT INTO facturas
  (cliente_id, comercio_id, evento_id, nivel_verificacion, clave_acceso_49,
   fecha_factura, monto_total, estado)
SELECT
  u.id, c.id, NULL, 1, '9999900000000000000000000000000000000002026092802',
  strftime('%Y-%m-%dT%H:%M:%S-05:00', 'now', '-5 hours', '-2 hour'),
  12.50, 'aprobada'
FROM usuarios u, comercios c
WHERE u.email = 'test@test.com' AND c.nombre = 'PRUEBA Café Central'
ON CONFLICT (clave_acceso_49) DO UPDATE SET
  cliente_id          = excluded.cliente_id,
  comercio_id         = excluded.comercio_id,
  nivel_verificacion  = excluded.nivel_verificacion,
  fecha_factura       = excluded.fecha_factura,
  monto_total         = excluded.monto_total,
  estado              = excluded.estado;


-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 9) Que quedo cargado, para confirmar a simple vista que esta todo.
--    Va en dos SELECT y no en uno con muchos UNION ALL porque D1 no acepta
--    mas de 5 términos en un SELECT compuesto.
-- ---------------------------------------------------------------------------
SELECT 'comercio' AS tipo, c.id, c.nombre AS nombre,
       'ruc ' || c.ruc || ', ' || c.hora_apertura || '-' || c.hora_cierre AS detalle
FROM comercios c WHERE c.nombre LIKE 'PRUEBA %'
UNION ALL
SELECT 'promocion', p.id, p.titulo,
       p.descuento_porcentaje || '% off, radio ' || p.radio_km || ' km, ' ||
       p.inicia_en || ' a ' || p.termina_en
FROM promociones_flash p WHERE p.titulo LIKE 'PRUEBA %'
UNION ALL
SELECT 'evento', e.id, e.nombre,
       e.estado || ', requiere entrada ' || e.requiere_entrada ||
       ', ' || e.fecha_inicio || ' a ' || e.fecha_fin
FROM eventos e WHERE e.nombre LIKE 'PRUEBA %'
UNION ALL
SELECT 'ronda', r.id, r.nombre,
       'evento ' || r.evento_id || ', ' || r.hora_inicio || ' a ' || r.hora_fin
FROM rondas r WHERE r.nombre LIKE 'PRUEBA %'
ORDER BY tipo, id;

SELECT 'patrocinio' AS tipo, s.id, c.nombre AS nombre,
       'evento ' || s.evento_id || ', ' || s.estado AS detalle
FROM eventos_sponsors s JOIN comercios c ON c.id = s.comercio_id
WHERE s.evento_id IN (SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %')
UNION ALL
SELECT 'entrada', t.id, 'test@test.com',
       'evento ' || t.evento_id || ', ' || t.estado ||
       ', monto ' || COALESCE(t.monto, '-')
FROM entradas t
WHERE t.evento_id IN (SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %')
UNION ALL
SELECT 'premio', p.id, p.nombre,
       p.tipo || ', stock ' || p.stock || ', ronda ' || COALESCE(p.ronda_id, 'sin ronda') ||
       ', criterio ' || COALESCE(p.criterio_frecuencia, '-')
FROM premios p
WHERE p.evento_id IN (SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %')
UNION ALL
SELECT 'factura', f.id, f.clave_acceso_49,
       f.estado || ', nivel ' || f.nivel_verificacion || ', ' || f.fecha_factura ||
       ', monto ' || f.monto_total
FROM facturas f WHERE f.clave_acceso_49 LIKE '99999%'
ORDER BY tipo, id;
