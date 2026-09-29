-- Migration number: 0018 	 2026-09-29T04:10:00.000Z

-- Registro de auditoría de cada notificación push que el servidor intentó enviar.
--
-- No hay ninguna forma de leer esto desde la app: se consulta directo en la
-- consola de D1, que es donde se investigan los push que no llegan. Guardar solo
-- los envíos aceptados no serviría, porque el caso que hay que diagnosticar es
-- justamente el contrario: FCM acepta el mensaje y aun así no aparece, y ahí lo
-- único que hay es la fila con fcm_aceptado en 0 para saber que se intentó.
--
-- Se escribe una fila por destinatario aunque el usuario no tenga token FCM
-- registrado. Esa ausencia es la explicación más común de un push que no llega,
-- así que queda a la vista en lugar de ser un salto silencioso en el código.
--
-- `tipo` dice qué disparó el envío, para poder filtrar por categoría al
-- investigar. La lista es cerrada a propósito: los disparadores que existen son
-- los que el código registra, y añadir uno nuevo obliga a tocar esta tabla y no
-- a colar una cadena cualquiera.
--
-- Esto no es lo mismo que flash_notificaciones_enviadas (0015), que es una tabla
-- de deduplicación: solo guarda que esa combinación usuario+promoción ya se
-- avisó, y no guarda ni título ni cuerpo. Esta guarda el envío y su contenido.
CREATE TABLE notificaciones_enviadas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  tipo TEXT NOT NULL CHECK (
    tipo IN (
      'hunt_inicia',
      'entrada_aprobada',
      'premio_ganado',
      'flash_cercania',
      'prueba'
    )
  ),
  titulo TEXT NOT NULL,
  cuerpo TEXT NOT NULL,
  data TEXT,
  enviado_en TEXT NOT NULL DEFAULT (datetime('now')),
  fcm_aceptado INTEGER NOT NULL DEFAULT 0 CHECK (fcm_aceptado IN (0, 1))
);

-- Las dos consultas que se harían al revisar: qué se le mandó a una persona, y
-- qué se ha mandando con cada disparador.
CREATE INDEX idx_notificaciones_enviadas_usuario
  ON notificaciones_enviadas (usuario_id, enviado_en DESC);
CREATE INDEX idx_notificaciones_enviadas_tipo
  ON notificaciones_enviadas (tipo, enviado_en DESC);
