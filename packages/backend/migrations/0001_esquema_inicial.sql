-- Migration number: 0001 	 2026-09-17T06:14:48.713Z

CREATE TABLE usuarios (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rol TEXT NOT NULL CHECK (rol IN ('cliente','negocio','organizador','admin')),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  nombre_completo TEXT NOT NULL,
  fecha_nacimiento TEXT,
  consentimiento_publicidad INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);


CREATE TABLE comercios (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  nombre TEXT NOT NULL,
  categoria TEXT,
  ruc TEXT,
  latitud REAL,
  longitud REAL,
  es_patrocinado INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);


CREATE TABLE eventos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  organizador_id INTEGER NOT NULL REFERENCES usuarios(id),
  nombre TEXT NOT NULL,
  fecha_inicio TEXT NOT NULL,
  fecha_fin TEXT NOT NULL,
  requiere_entrada INTEGER NOT NULL DEFAULT 0,
  precio_entrada REAL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);


CREATE TABLE rondas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  evento_id INTEGER NOT NULL REFERENCES eventos(id),
  nombre TEXT,
  hora_inicio TEXT NOT NULL,
  hora_fin TEXT NOT NULL
);


CREATE TABLE cupones (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  comercio_id INTEGER NOT NULL REFERENCES comercios(id),
  cliente_id INTEGER REFERENCES usuarios(id),
  codigo_qr TEXT NOT NULL UNIQUE,
  estado TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','utilizado','expirado')),
  descuento REAL,
  expira_en TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);


CREATE TABLE facturas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
  comercio_id INTEGER REFERENCES comercios(id),
  evento_id INTEGER REFERENCES eventos(id),
  nivel_verificacion INTEGER NOT NULL CHECK (nivel_verificacion IN (1,2,3)),
  clave_acceso_49 TEXT UNIQUE,
  numero_factura TEXT,
  ruc_emisor TEXT,
  nombre_comprador_factura TEXT,
  fecha_factura TEXT,
  monto_total REAL,
  descuento_aplicado REAL,
  cupon_id INTEGER REFERENCES cupones(id),
  foto TEXT,
  estado TEXT NOT NULL DEFAULT 'aprobada' CHECK (estado IN ('aprobada','pendiente_revision_nombre','rechazada')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);


CREATE TABLE factura_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  factura_id INTEGER NOT NULL REFERENCES facturas(id),
  producto TEXT,
  precio REAL,
  cantidad INTEGER NOT NULL DEFAULT 1
);


CREATE TABLE entradas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  evento_id INTEGER NOT NULL REFERENCES eventos(id),
  cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
  estado TEXT NOT NULL DEFAULT 'pendiente_pago' CHECK (estado IN ('pendiente_pago','pendiente_revision_comprobante','aprobada','rechazada')),
  comprobante_foto TEXT,
  monto REAL,
  revisado_por INTEGER REFERENCES usuarios(id),
  revisado_en TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);


CREATE TABLE premios (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  evento_id INTEGER NOT NULL REFERENCES eventos(id),
  ronda_id INTEGER REFERENCES rondas(id),
  nombre TEXT NOT NULL,
  stock INTEGER NOT NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('principal','consolacion','frecuencia')),
  criterio_frecuencia INTEGER
);


CREATE TABLE premios_entregados (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  premio_id INTEGER NOT NULL REFERENCES premios(id),
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  ronda_id INTEGER REFERENCES rondas(id),
  estado TEXT NOT NULL DEFAULT 'entregado' CHECK (estado IN ('entregado','revocado')),
  entregado_en TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (usuario_id, ronda_id)
);


CREATE TABLE puntos_evento (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  evento_id INTEGER NOT NULL REFERENCES eventos(id),
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  puntos INTEGER NOT NULL DEFAULT 0,
  UNIQUE (evento_id, usuario_id)
);
