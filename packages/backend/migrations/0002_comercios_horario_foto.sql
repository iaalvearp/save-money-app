-- Migration number: 0002 	 2026-09-17T11:24:42.054Z

ALTER TABLE comercios ADD COLUMN horario TEXT;
ALTER TABLE comercios ADD COLUMN foto_url TEXT;
