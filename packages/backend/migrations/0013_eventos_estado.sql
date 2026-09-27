-- Migration number: 0013 	 2026-09-27T00:00:01.000Z

-- Lifecycle state of a Hunt event, so "Hunt inicia" is an explicit action
-- the organizer triggers (POST /hunt/eventos/:id/iniciar) instead of being
-- implied by the event creation date.
ALTER TABLE eventos
  ADD COLUMN estado TEXT NOT NULL DEFAULT 'programado'
  CHECK (estado IN ('programado','activo','finalizado'));

CREATE INDEX idx_eventos_estado ON eventos (estado);
