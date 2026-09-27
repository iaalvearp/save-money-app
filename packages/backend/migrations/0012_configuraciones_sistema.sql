-- Migration number: 0012 	 2026-09-27T00:00:00.000Z

-- Runtime configuration that must be changeable without redeploying the Worker.
-- For 'hunt_inicio_notificar_a' the allowed values are:
--   'aprobados' -> only users holding an approved ticket for the event
--   'todos'     -> every user registered in the event (approved or not)
CREATE TABLE configuraciones_sistema (
  clave TEXT PRIMARY KEY,
  valor TEXT NOT NULL,
  actualizado_en TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO configuraciones_sistema (clave, valor) VALUES ('hunt_inicio_notificar_a', 'aprobados');
