-- ============================================================================
-- Borra SOLO los datos de prueba cargados con scripts/seed-prueba.sql
-- ============================================================================
--
-- QUE BORRA
--   Los eventos cuyo nombre empieza con "PRUEBA ", la promocion Flash con
--   "PRUEBA " en el titulo, el comercio con "PRUEBA " en el nombre y las
--   facturas cuya clave de acceso empieza con 99999.
--
-- QUE NO BORRA
--   Nada mas. En particular no toca:
--     - las tres cuentas (test@test.com, negocio@test.com, organizador@test.com)
--     - las facturas que ya existian, cuyas claves no empiezan con 99999
--     - los comercios, eventos o promociones que no llevan el prefijo "PRUEBA "
--     - la tabla challenges (nivel 3) ni la ubicacion de los usuarios
--   Para estar seguro, cada DELETE lleva su propia condicion de nombre o de
--   clave. No hay un unico DELETE masivo por tabla.
--
-- ORDEN
--   De los mas dependientes a los menos, para no dejar referencias colgando:
--   primero lo que cuelga de premios y entradas, luego premios, entradas,
--   patrocinadores, rondas y eventos, despues promociones, facturas, cupones
--   y por ultimo el comercio.
--
-- COMO SE EJECUTA
--   pnpm wrangler d1 execute save-money-db --remote --file scripts/seed-prueba-limpiar.sql
--   Ojo: esto borra datos. Pedir confirmacion antes de correrlo en remoto.
--   Para probarlo sin riesgo, en una base local:
--     pnpm wrangler d1 migrations apply save-money-db --local
--     pnpm wrangler d1 execute save-money-db --local --file scripts/seed-prueba.sql
--     pnpm wrangler d1 execute save-money-db --local --file scripts/seed-prueba-limpiar.sql
--
-- CONSECUENCIA SOBRE EL COMERCIO
--   El comercio "PRUEBA Café Central" se borra. Si la cuenta de negocio ya
--   tenia un comercio antes del seed (tenia uno), al limpiar queda otra vez sin
--   comercio, que es como estaba antes de cargar los datos de prueba. La app
--   le mostrara de nuevo el formulario de crear su comercio.
--   En el improbable caso de que una factura que no es de prueba estuviera
--   apuntando a ese comercio, esa factura no se borra: solo se le vacia el
--   comercio_id para poder borrar el comercio. Ver el paso 10.
--
-- CON LO QUE SE GENERE DURANTE LAS PRUEBAS
--   Ademas de lo que carga el seed, este script tambien borra lo que la app
--   pueda crear esta noche sobre esos mismos datos de prueba: premios
--   entregados, puntos del evento, cupones canjeados, claims de promociones
--   Flash y sus notificaciones enviadas. Todo se identifica por colgar de un
--   evento o un comercio "PRUEBA ", o por ser una factura con clave 99999, asi
--   que lo de otra persona no se ve afectado.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) Lo que cuelga de los premios de los eventos de prueba
-- ---------------------------------------------------------------------------
DELETE FROM premios_entregados
WHERE premio_id IN (
  SELECT p.id
  FROM premios p
  JOIN eventos e ON e.id = p.evento_id
  WHERE e.nombre LIKE 'PRUEBA %'
)
OR ronda_id IN (
  SELECT r.id
  FROM rondas r
  JOIN eventos e ON e.id = r.evento_id
  WHERE e.nombre LIKE 'PRUEBA %'
);


-- ---------------------------------------------------------------------------
-- 2) Lo que cuelga de los eventos de prueba
-- ---------------------------------------------------------------------------
DELETE FROM puntos_evento
WHERE evento_id IN (
  SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %'
);

DELETE FROM promociones_flash_claims
WHERE promocion_id IN (
  SELECT p.id
  FROM promociones_flash p
  JOIN comercios c ON c.id = p.comercio_id
  WHERE p.titulo LIKE 'PRUEBA %' OR c.nombre LIKE 'PRUEBA %'
);

DELETE FROM flash_notificaciones_enviadas
WHERE promocion_id IN (
  SELECT p.id
  FROM promociones_flash p
  JOIN comercios c ON c.id = p.comercio_id
  WHERE p.titulo LIKE 'PRUEBA %' OR c.nombre LIKE 'PRUEBA %'
);


-- ---------------------------------------------------------------------------
-- 3) Items de las facturas de prueba
-- ---------------------------------------------------------------------------
DELETE FROM factura_items
WHERE factura_id IN (
  SELECT id FROM facturas WHERE clave_acceso_49 LIKE '99999%'
);


-- ---------------------------------------------------------------------------
-- 4) Premios y entradas de los eventos de prueba
-- ---------------------------------------------------------------------------
DELETE FROM premios
WHERE evento_id IN (
  SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %'
);

DELETE FROM entradas
WHERE evento_id IN (
  SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %'
);


-- ---------------------------------------------------------------------------
-- 5) Patrocinios de prueba
-- ---------------------------------------------------------------------------
DELETE FROM eventos_sponsors
WHERE evento_id IN (
  SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %'
)
OR comercio_id IN (
  SELECT id FROM comercios WHERE nombre LIKE 'PRUEBA %'
);


-- ---------------------------------------------------------------------------
-- 6) Rondas de los eventos de prueba
-- ---------------------------------------------------------------------------
DELETE FROM rondas
WHERE evento_id IN (
  SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %'
)
OR nombre LIKE 'PRUEBA %';


-- ---------------------------------------------------------------------------
-- 7) Los eventos de prueba
-- ---------------------------------------------------------------------------
DELETE FROM eventos
WHERE nombre LIKE 'PRUEBA %';


-- ---------------------------------------------------------------------------
-- 8) Las facturas de prueba (clave 99999) y la promocion Flash de prueba
-- ---------------------------------------------------------------------------
DELETE FROM facturas
WHERE clave_acceso_49 LIKE '99999%';

DELETE FROM promociones_flash
WHERE titulo LIKE 'PRUEBA %'
   OR comercio_id IN (
     SELECT id FROM comercios WHERE nombre LIKE 'PRUEBA %'
   );


-- ---------------------------------------------------------------------------
-- 9) Los cupones de prueba
--    Los del comercio "PRUEBA ", los emitidos por las promociones Flash de
--    prueba y los que esten pegados a una factura con clave 99999. Se borran
--    despues de las facturas y de los claims, que son los que los referencian.
-- ---------------------------------------------------------------------------
DELETE FROM cupones
WHERE comercio_id IN (
  SELECT id FROM comercios WHERE nombre LIKE 'PRUEBA %'
)
OR id IN (
  SELECT cupon_id
  FROM promociones_flash_claims
  WHERE cupon_id IS NOT NULL
    AND promocion_id IN (
      SELECT p.id
      FROM promociones_flash p
      JOIN comercios c ON c.id = p.comercio_id
      WHERE p.titulo LIKE 'PRUEBA %' OR c.nombre LIKE 'PRUEBA %'
    )
);


-- ---------------------------------------------------------------------------
-- 10) El comercio de prueba
--
--     Antes, un caso raro: como el seed actualiza el comercio que ya tenia la
--     cuenta de negocio en vez de crear otro, alguna factura que no sea de
--     prueba puede haber quedado apuntando a "PRUEBA Café Central". Esas facturas
--     no se borran (su clave no empieza con 99999), pero su comercio_id se
--     vacia para que el comercio se pueda borrar sin tocarlas. La columna
--     admite nulo, asi que la factura sobrevive con todos sus demas datos.
-- ---------------------------------------------------------------------------
UPDATE facturas
SET comercio_id = NULL
WHERE clave_acceso_49 NOT LIKE '99999%'
  AND comercio_id IN (
    SELECT id FROM comercios WHERE nombre LIKE 'PRUEBA %'
  );

DELETE FROM comercios
WHERE nombre LIKE 'PRUEBA %';


-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 11) Que queda. Todo en 0 significa que se borro todo lo de prueba, y que las
--     tres cuentas y las facturas que no son de prueba siguen intactas.
--     Va en tres SELECT porque D1 no acepta mas de 5 términos en un SELECT
--     compuesto.
-- ---------------------------------------------------------------------------
SELECT 'eventos PRUEBA' AS que, COUNT(*) AS restantes FROM eventos WHERE nombre LIKE 'PRUEBA %'
UNION ALL SELECT 'rondas PRUEBA', COUNT(*) FROM rondas WHERE nombre LIKE 'PRUEBA %'
UNION ALL SELECT 'premios en eventos PRUEBA', COUNT(*) FROM premios
  WHERE evento_id IN (SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %')
UNION ALL SELECT 'patrocinios de PRUEBA', COUNT(*) FROM eventos_sponsors
  WHERE comercio_id IN (SELECT id FROM comercios WHERE nombre LIKE 'PRUEBA %');

SELECT 'entradas en eventos PRUEBA' AS que, COUNT(*) AS restantes FROM entradas
  WHERE evento_id IN (SELECT id FROM eventos WHERE nombre LIKE 'PRUEBA %')
UNION ALL SELECT 'premios entregados de PRUEBA', COUNT(*) FROM premios_entregados
  WHERE premio_id IN (
    SELECT p.id FROM premios p JOIN eventos e ON e.id = p.evento_id
    WHERE e.nombre LIKE 'PRUEBA %'
  )
UNION ALL SELECT 'facturas clave 99999', COUNT(*) FROM facturas
  WHERE clave_acceso_49 LIKE '99999%'
UNION ALL SELECT 'promociones PRUEBA', COUNT(*) FROM promociones_flash
  WHERE titulo LIKE 'PRUEBA %';

SELECT 'comercios PRUEBA' AS que, COUNT(*) AS restantes FROM comercios
  WHERE nombre LIKE 'PRUEBA %'
UNION ALL SELECT 'cupones de PRUEBA', COUNT(*) FROM cupones
  WHERE comercio_id IN (SELECT id FROM comercios WHERE nombre LIKE 'PRUEBA %')
UNION ALL SELECT 'CUENTAS de prueba (deben seguir 3)', COUNT(*) FROM usuarios
  WHERE email IN ('test@test.com', 'negocio@test.com', 'organizador@test.com')
UNION ALL SELECT 'facturas NO de prueba (deben quedar)', COUNT(*) FROM facturas
  WHERE clave_acceso_49 IS NULL OR clave_acceso_49 NOT LIKE '99999%';
