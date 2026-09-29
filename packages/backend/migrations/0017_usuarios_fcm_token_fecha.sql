-- Migration number: 0017 	 2026-09-29T02:30:00.000Z

-- Cuándo se guardó el token de notificaciones de cada usuario por última vez.
--
-- Sin esta columna no hay forma de saber si el token guardado corresponde a la
-- instalación actual del teléfono o a una anterior: cuando una app se reinstala
-- FCM genera un token nuevo y el viejo sigue pareciendo válido hasta que FCM lo
-- retira, así que un envío se acepta y no se entrega en ninguna parte. Con la
-- fecha, un diagnóstico distingue "el token es viejo" de "el permiso está
-- denegado" sin depender de la longitud del token ni de suposiciones.
ALTER TABLE usuarios ADD COLUMN fcm_token_updated_at TEXT;
