-- Migration number: 0005 	 2026-09-18T22:00:00.000Z
-- Agrega tabla challenges para nivel 3 (evidencia sin comprobante).
-- Agrega challenge_nonce y claim_hash a facturas para trazabilidad.

CREATE TABLE IF NOT EXISTS challenges (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
  nonce TEXT NOT NULL UNIQUE,
  expira_en TEXT NOT NULL,
  usado INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_challenges_nonce ON challenges(nonce);
CREATE INDEX IF NOT EXISTS idx_challenges_cliente ON challenges(cliente_id);

-- Agregar columnas para nivel 3 a facturas
-- SQLite no permite IF NOT EXISTS en ALTER TABLE,
-- pero las migraciones se ejecutan una sola vez.
ALTER TABLE facturas ADD COLUMN challenge_nonce TEXT;
ALTER TABLE facturas ADD COLUMN claim_hash TEXT;
