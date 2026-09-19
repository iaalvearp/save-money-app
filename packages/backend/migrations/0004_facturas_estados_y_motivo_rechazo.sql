-- Migration number: 0004 	 2026-09-18T21:31:18.859Z
-- Reconstruye la tabla facturas para:
--   1. Ampliar el CHECK de estado con 'pendiente_verificacion_sri' (que el código ya escribía)
--   2. Agregar columna motivo_rechazo TEXT (nullable)

-- SQLite no permite modificar un CHECK existente con ALTER Table,
-- así que recreamos la tabla completa.

PRAGMA foreign_keys = OFF;

CREATE TABLE facturas_nueva (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
  comercio_id INTEGER REFERENCES comercios(id),
  evento_id INTEGER REFERENCES eventos(id),
  nivel_verificacion INTEGER NOT NULL CHECK (nivel_verificacion IN (1,2,3)),
  clave_acceso_49 TEXT UNIQUE,
  numero_factura TEXT,
  ruc_emisor TEXT,
  nombre_comprador_factura TEXT,
  fecha_factura TEXT,
  monto_total REAL,
  descuento_aplicado REAL,
  cupon_id INTEGER REFERENCES cupones(id),
  foto TEXT,
  estado TEXT NOT NULL DEFAULT 'aprobada' CHECK (estado IN (
    'aprobada',
    'pendiente_revision_nombre',
    'pendiente_verificacion_sri',
    'rechazada'
  )),
  motivo_rechazo TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  sri_estado_bruto TEXT
);

INSERT INTO facturas_nueva
  (id, cliente_id, comercio_id, evento_id, nivel_verificacion,
   clave_acceso_49, numero_factura, ruc_emisor, nombre_comprador_factura,
   fecha_factura, monto_total, descuento_aplicado, cupon_id, foto,
   estado, created_at, sri_estado_bruto)
SELECT
  id, cliente_id, comercio_id, evento_id, nivel_verificacion,
  clave_acceso_49, numero_factura, ruc_emisor, nombre_comprador_factura,
  fecha_factura, monto_total, descuento_aplicado, cupon_id, foto,
  estado, created_at, sri_estado_bruto
FROM facturas;

DROP TABLE facturas;

ALTER TABLE facturas_nueva RENAME TO facturas;

PRAGMA foreign_keys = ON;
