-- Migration number: 0010 	 2026-09-19T05:23:14.535Z

ALTER TABLE comercios ADD COLUMN hora_apertura TEXT;
ALTER TABLE comercios ADD COLUMN hora_cierre TEXT;
