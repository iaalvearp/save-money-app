-- Migration number: 0009 	 2026-09-18T01:00:00.000Z

-- Add reclamado_en timestamp for atomic prize claims
ALTER TABLE premios_entregados ADD COLUMN reclamado_en TEXT;

-- The existing UNIQUE (usuario_id, ronda_id) already enforces one prize per user per round.
-- Race conditions on stock are handled at the application layer with atomic SELECT + INSERT.
