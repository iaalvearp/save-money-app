-- Migration number: 0014 	 2026-09-27T00:00:02.000Z

-- Last known position per user, reported by the client while the app is in
-- the foreground. Used to evaluate proximity to active Flash promotions.
-- One row per user: the client only ever reports its current position.
CREATE TABLE ubicaciones_usuarios (
  usuario_id INTEGER PRIMARY KEY REFERENCES usuarios(id),
  latitud REAL NOT NULL,
  longitud REAL NOT NULL,
  actualizado_en TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
