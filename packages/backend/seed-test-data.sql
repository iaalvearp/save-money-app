INSERT INTO usuarios (rol, email, password_hash, nombre_completo, created_at) VALUES
('negocio', 'seed1@test.local', 'seed', 'Café La Esquina', datetime('now')),
('negocio', 'seed2@test.local', 'seed', 'Panadería Dulce Trigo', datetime('now')),
('negocio', 'seed3@test.local', 'seed', 'Ferretería El Tornillo', datetime('now'));

INSERT INTO comercios (usuario_id, nombre, categoria, ruc, latitud, longitud, horario, foto_url, es_patrocinado)
SELECT id, 'Café La Esquina', 'Cafetería', '0900000000001', -2.170998, -79.922359, 'Lun-Sáb 8am-8pm', NULL, 1
FROM usuarios WHERE email = 'seed1@test.local';

INSERT INTO comercios (usuario_id, nombre, categoria, ruc, latitud, longitud, horario, foto_url, es_patrocinado)
SELECT id, 'Panadería Dulce Trigo', 'Panadería', '0900000000002', -2.163842, -79.909546, 'Lun-Dom 6am-9pm', NULL, 0
FROM usuarios WHERE email = 'seed2@test.local';

INSERT INTO comercios (usuario_id, nombre, categoria, ruc, latitud, longitud, horario, foto_url, es_patrocinado)
SELECT id, 'Ferretería El Tornillo', 'Ferretería', '0900000000003', -2.180312, -79.897201, 'Lun-Vie 8am-6pm', NULL, 0
FROM usuarios WHERE email = 'seed3@test.local';