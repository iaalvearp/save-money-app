-- Migration number: 0008 	 2026-09-18T00:00:00.000Z

-- Sponsors for Hunt events (distinct from Discover 'es_patrocinado')
CREATE TABLE eventos_sponsors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  evento_id INTEGER NOT NULL REFERENCES eventos(id),
  comercio_id INTEGER NOT NULL REFERENCES comercios(id),
  estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobado','rechazado')),
  invited_at TEXT NOT NULL DEFAULT (datetime('now')),
  responded_at TEXT,
  UNIQUE (evento_id, comercio_id)
);

-- Hunt consolation coupons: issued by organizer to non-winners
-- Uses cupones table with tipo='hunt' per cupones-decision.md
