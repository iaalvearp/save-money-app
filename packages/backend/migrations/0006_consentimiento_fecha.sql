-- Migration number: 0006 	 2026-09-18T00:00:00.000Z

-- Track when advertising consent was granted or revoked
ALTER TABLE usuarios ADD COLUMN consentimiento_publicidad_fecha TEXT;
