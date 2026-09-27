-- Migration number: 0015 	 2026-09-27T00:00:03.000Z

-- Guarantees a "Flash por cercanía" push is sent at most once per
-- user + promotion, no matter how many times the user enters the radius.
-- The unique constraint is what enforces it, so concurrent reports cannot
-- duplicate a notification.
CREATE TABLE flash_notificaciones_enviadas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  promocion_id INTEGER NOT NULL REFERENCES promociones_flash(id),
  enviado_en TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (usuario_id, promocion_id)
);
