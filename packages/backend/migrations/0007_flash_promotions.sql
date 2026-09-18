-- Migration number: 0007 	 2026-09-18T00:00:00.000Z

-- Extend cupones with type tracking per cupones-decision.md
ALTER TABLE cupones ADD COLUMN tipo TEXT NOT NULL DEFAULT 'flash'
  CHECK (tipo IN ('flash', 'hunt'));
ALTER TABLE cupones ADD COLUMN emitido_por INTEGER REFERENCES usuarios(id);
ALTER TABLE cupones ADD COLUMN canjeado_en TEXT;

-- Flash promotions: time-limited discounts near a comercio
CREATE TABLE promociones_flash (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  comercio_id INTEGER NOT NULL REFERENCES comercios(id),
  titulo TEXT NOT NULL,
  descripcion TEXT,
  descuento_porcentaje REAL NOT NULL,
  inicia_en TEXT NOT NULL,
  termina_en TEXT NOT NULL,
  latitud REAL,
  longitud REAL,
  radio_km REAL DEFAULT 5,
  categoria TEXT,
  max_usuarios INTEGER,
  usuarios_notificados INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Track which users claimed a flash promotion (prevent duplicates)
CREATE TABLE promociones_flash_claims (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  promocion_id INTEGER NOT NULL REFERENCES promociones_flash(id),
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  cupon_id INTEGER REFERENCES cupones(id),
  claimed_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (promocion_id, usuario_id)
);
