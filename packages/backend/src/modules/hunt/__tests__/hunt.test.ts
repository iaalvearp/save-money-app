import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { hunt } from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-hunt";

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/hunt", hunt);
  return app;
}

async function makeToken(sub: number, rol: string): Promise<string> {
  return sign(
    { sub: String(sub), rol, exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
  );
}

function futureDate(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().replace("T", " ").slice(0, 19);
}

function pastDate(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString().replace("T", " ").slice(0, 19);
}

beforeAll(async () => {
  await db.prepare(`CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rol TEXT NOT NULL CHECK (rol IN ('cliente','negocio','organizador','admin')),
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    nombre_completo TEXT NOT NULL,
    fecha_nacimiento TEXT,
    consentimiento_publicidad INTEGER,
    consentimiento_publicidad_fecha TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS comercios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
    nombre TEXT NOT NULL,
    categoria TEXT,
    ruc TEXT,
    latitud REAL,
    longitud REAL,
    es_patrocinado INTEGER NOT NULL DEFAULT 0,
    horario TEXT,
    foto_url TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS eventos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    organizador_id INTEGER NOT NULL REFERENCES usuarios(id),
    nombre TEXT NOT NULL,
    fecha_inicio TEXT NOT NULL,
    fecha_fin TEXT NOT NULL,
    requiere_entrada INTEGER NOT NULL DEFAULT 0,
    precio_entrada REAL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS rondas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    nombre TEXT,
    hora_inicio TEXT NOT NULL,
    hora_fin TEXT NOT NULL
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS cupones (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    comercio_id INTEGER NOT NULL REFERENCES comercios(id),
    cliente_id INTEGER REFERENCES usuarios(id),
    codigo_qr TEXT NOT NULL UNIQUE,
    estado TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','utilizado','expirado')),
    tipo TEXT NOT NULL DEFAULT 'flash' CHECK (tipo IN ('flash','hunt')),
    descuento REAL,
    expira_en TEXT,
    emitido_por INTEGER REFERENCES usuarios(id),
    canjeado_en TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS entradas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
    estado TEXT NOT NULL DEFAULT 'pendiente_pago' CHECK (estado IN ('pendiente_pago','pendiente_revision_comprobante','aprobada','rechazada')),
    comprobante_foto TEXT,
    monto REAL,
    revisado_por INTEGER REFERENCES usuarios(id),
    revisado_en TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS premios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    ronda_id INTEGER REFERENCES rondas(id),
    nombre TEXT NOT NULL,
    stock INTEGER NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('principal','consolacion','frecuencia')),
    criterio_frecuencia INTEGER
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS premios_entregados (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    premio_id INTEGER NOT NULL REFERENCES premios(id),
    usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
    ronda_id INTEGER REFERENCES rondas(id),
    estado TEXT NOT NULL DEFAULT 'entregado' CHECK (estado IN ('entregado','revocado')),
    entregado_en TEXT NOT NULL DEFAULT (datetime('now')),
    reclamado_en TEXT,
    UNIQUE (usuario_id, ronda_id)
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS eventos_sponsors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    comercio_id INTEGER NOT NULL REFERENCES comercios(id),
    estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobado','rechazado')),
    invited_at TEXT NOT NULL DEFAULT (datetime('now')),
    responded_at TEXT,
    UNIQUE (evento_id, comercio_id)
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS puntos_evento (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
    puntos INTEGER NOT NULL DEFAULT 0,
    UNIQUE (evento_id, usuario_id)
  )`).run();

  await db.prepare(`INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`)
    .bind("organizador", "org@test.com", "hash", "Org Test").run();
  await db.prepare(`INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`)
    .bind("negocio", "neg@test.com", "hash", "Neg Test").run();
  await db.prepare(`INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`)
    .bind("cliente", "cli@test.com", "hash", "Cli Test").run();
  await db.prepare(`INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`)
    .bind("admin", "adm@test.com", "hash", "Admin Test").run();

  await db.prepare(`INSERT INTO comercios (usuario_id, nombre, categoria) VALUES (?, ?, ?)`)
    .bind(2, "Café Hunt", "Gastronomía").run();
});

describe("POST /hunt/eventos - crear evento", () => {
  it("organizador crea evento válido", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const res = await app.request(
      "/hunt/eventos",
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          nombre: "Hunt Quito 2026",
          fecha_inicio: futureDate(1),
          fecha_fin: futureDate(3),
          requiere_entrada: true,
          precio_entrada: 25.0,
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { evento: { nombre: string; precio_entrada: number } };
    expect(body.evento.nombre).toBe("Hunt Quito 2026");
    expect(body.evento.precio_entrada).toBe(25.0);
  });

  it("fechas inválidas: error 400", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const res = await app.request(
      "/hunt/eventos",
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          nombre: "Evento Mal",
          fecha_inicio: futureDate(5),
          fecha_fin: futureDate(1),
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(400);
  });
});

describe("POST /hunt/eventos/:id/rondas", () => {
  it("organizador agrega ronda a su evento", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Rondas", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/rondas`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          nombre: "Ronda 1",
          hora_inicio: "10:00",
          hora_fin: "12:00",
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
  });
});

describe("POST /hunt/eventos/:id/sponsors", () => {
  it("organizador invita negocio como sponsor", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Sponsor", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/sponsors`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ comercio_id: 1 }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
  });

  it("duplicar invitación: error 409", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Sponsor Dup", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    await app.request(
      `/hunt/eventos/${eventoId}/sponsors`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ comercio_id: 1 }),
      },
      { DB: db, JWT_SECRET }
    );

    const res = await app.request(
      `/hunt/eventos/${eventoId}/sponsors`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ comercio_id: 1 }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(409);
  });
});

describe("POST /hunt/eventos/:eventoId/sponsors/:sponsorId/responder", () => {
  it("negocio acepta patrocinio", async () => {
    const app = buildApp();
    const orgToken = await makeToken(1, "organizador");
    const negToken = await makeToken(2, "negocio");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Aceptar", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    await app.request(
      `/hunt/eventos/${eventoId}/sponsors`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${orgToken}` },
        body: JSON.stringify({ comercio_id: 1 }),
      },
      { DB: db, JWT_SECRET }
    );

    const sponsors = await db
      .prepare("SELECT id FROM eventos_sponsors WHERE evento_id = ?")
      .bind(eventoId)
      .all();
    const sponsorId = sponsors.results[0].id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/sponsors/${sponsorId}/responder`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${negToken}` },
        body: JSON.stringify({ acepta: true }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const row = await db
      .prepare("SELECT estado FROM eventos_sponsors WHERE id = ?")
      .bind(sponsorId)
      .first<{ estado: string }>();
    expect(row?.estado).toBe("aprobado");
  });
});

describe("POST /hunt/eventos/:eventoId/entradas/comprar", () => {
  it("cliente compra entrada para evento que la requiere", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada)
                VALUES (?, ?, ?, ?, 1, ?)`)
      .bind(1, "Evento Pago", futureDate(1), futureDate(3), 30.0)
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/entradas/comprar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { entrada: { estado: string; monto: number } };
    expect(body.entrada.estado).toBe("pendiente_pago");
    expect(body.entrada.monto).toBe(30.0);
  });

  it("evento sin entrada requerida: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada)
                VALUES (?, ?, ?, ?, 0)`)
      .bind(1, "Evento Gratis", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/entradas/comprar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
  });

  it("comprar entrada dos veces: error 409", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada)
                VALUES (?, ?, ?, ?, 1, ?)`)
      .bind(1, "Evento Dup", futureDate(1), futureDate(3), 20.0)
      .run();
    const eventoId = insertRes.meta.last_row_id;

    await app.request(
      `/hunt/eventos/${eventoId}/entradas/comprar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    const res = await app.request(
      `/hunt/eventos/${eventoId}/entradas/comprar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(409);
  });
});

describe("POST /hunt/entradas/:id/revisar", () => {
  it("organizador aprueba entrada", async () => {
    const app = buildApp();
    const orgToken = await makeToken(1, "organizador");
    const cliToken = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada)
                VALUES (?, ?, ?, ?, 1, ?)`)
      .bind(1, "Evento Aprobar", futureDate(1), futureDate(3), 10.0)
      .run();
    const eventoId = insertRes.meta.last_row_id;

    await app.request(
      `/hunt/eventos/${eventoId}/entradas/comprar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${cliToken}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    const entradas = await db
      .prepare("SELECT id FROM entradas WHERE evento_id = ?")
      .bind(eventoId)
      .all();
    const entradaId = entradas.results[0].id;

    await db
      .prepare(`UPDATE entradas SET estado = 'pendiente_revision_comprobante', comprobante_foto = 'photo.jpg' WHERE id = ?`)
      .bind(entradaId)
      .run();

    const res = await app.request(
      `/hunt/entradas/${entradaId}/revisar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${orgToken}` },
        body: JSON.stringify({ aprueba: true }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const row = await db
      .prepare("SELECT estado FROM entradas WHERE id = ?")
      .bind(entradaId)
      .first<{ estado: string }>();
    expect(row?.estado).toBe("aprobada");
  });

  it("organizador rechaza entrada", async () => {
    const app = buildApp();
    const orgToken = await makeToken(1, "organizador");
    const cliToken = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada)
                VALUES (?, ?, ?, ?, 1, ?)`)
      .bind(1, "Evento Rechazar", futureDate(1), futureDate(3), 10.0)
      .run();
    const eventoId = insertRes.meta.last_row_id;

    await app.request(
      `/hunt/eventos/${eventoId}/entradas/comprar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${cliToken}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    const entradas = await db
      .prepare("SELECT id FROM entradas WHERE evento_id = ?")
      .bind(eventoId)
      .all();
    const entradaId = entradas.results[0].id;

    await db
      .prepare(`UPDATE entradas SET estado = 'pendiente_revision_comprobante', comprobante_foto = 'fake.jpg' WHERE id = ?`)
      .bind(entradaId)
      .run();

    const res = await app.request(
      `/hunt/entradas/${entradaId}/revisar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${orgToken}` },
        body: JSON.stringify({ aprueba: false }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const row = await db
      .prepare("SELECT estado FROM entradas WHERE id = ?")
      .bind(entradaId)
      .first<{ estado: string }>();
    expect(row?.estado).toBe("rechazada");
  });
});

describe("POST /hunt/eventos/:eventoId/premios", () => {
  it("organizador crea premio", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Premios", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          nombre: "Premio Mayor",
          stock: 5,
          tipo: "principal",
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { premio: { nombre: string; stock: number } };
    expect(body.premio.stock).toBe(5);
  });

  it("premio sin stock: error 400", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento SinStock", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          nombre: "Premio Cero",
          stock: 0,
          tipo: "principal",
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(400);
  });
});

describe("POST /hunt/eventos/:eventoId/premios/:premioId/entregar", () => {
  it("entrega premio con stock", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Entregar", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Test", 2, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/entregar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ usuario_id: 3 }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
  });

  it("premio sin stock: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento SinStockEntrega", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Agotado", 1, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    await db
      .prepare(`INSERT INTO premios_entregados (premio_id, usuario_id) VALUES (?, ?)`)
      .bind(premioId, 3)
      .run();

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/entregar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ usuario_id: 2 }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
  });
});

describe("POST /hunt/eventos/:eventoId/cupones-consolacion", () => {
  it("organizador emite cupones hunt de consolación", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Consolación", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/cupones-consolacion`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          comercio_id: 1,
          usuario_ids: [2, 3],
          descuento: 15,
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { cupones_creados: number; expira_en: string };
    expect(body.cupones_creados).toBe(2);
    expect(body.expira_en).toBeTruthy();

    const cupones = await db
      .prepare("SELECT tipo, descuento FROM cupones WHERE cliente_id IN (2, 3) AND tipo = 'hunt'")
      .all();
    expect(cupones.results.length).toBe(2);
    expect(cupones.results[0].descuento).toBe(15);
  });
});

describe("POST /hunt/eventos/:eventoId/premios/:premioId/reclamar", () => {
  it("cliente reclama premio con stock y evento activo", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Reclamar", pastDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Reclamo", 3, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { mensaje: string; puntos_ganados: number };
    expect(body.puntos_ganados).toBe(10);

    const puntos = await db
      .prepare("SELECT puntos FROM puntos_evento WHERE evento_id = ? AND usuario_id = ?")
      .bind(eventoId, 3)
      .first<{ puntos: number }>();
    expect(puntos?.puntos).toBe(10);
  });

  it("reclamo repetido del mismo usuario: error 409", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Dup Reclamo", pastDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Dup", 5, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(409);
  });

  it("reclamo sin compra aprobada: error 403", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada)
                VALUES (?, ?, ?, ?, 1, ?)`)
      .bind(1, "Evento SinEntrada", pastDate(1), futureDate(3), 20.0)
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio SinEntrada", 5, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(403);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("entrada aprobada");
  });

  it("reclamo fuera del horario: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Futuro", futureDate(5), futureDate(10))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Futuro", 5, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("Fuera del horario");
  });

  it("stock cero: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Agotado", pastDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Agotado", 1, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    await db
      .prepare(`INSERT INTO premios_entregados (premio_id, usuario_id, estado)
                VALUES (?, ?, 'entregado')`)
      .bind(premioId, 2)
      .run();

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("sin stock");
  });

  it("premio revocado no afecta stock ni genera inconsistencias", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Revocado", pastDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Revocado", 2, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    await db
      .prepare(`INSERT INTO premios_entregados (premio_id, usuario_id, estado)
                VALUES (?, ?, 'revocado')`)
      .bind(premioId, 2)
      .run();

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);

    const stockRow = await db
      .prepare(`SELECT COUNT(*) AS cnt FROM premios_entregados
                WHERE premio_id = ? AND estado = 'entregado'`)
      .bind(premioId)
      .first<{ cnt: number }>();
    expect(stockRow?.cnt).toBe(1);
  });

  it("puntos de un evento no visibles en otro", async () => {
    const app = buildApp();
    const token = await makeToken(3, "cliente");

    const evento1Res = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento A", pastDate(1), futureDate(3))
      .run();
    const evento1Id = evento1Res.meta.last_row_id;

    const premio1Res = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(evento1Id, "Premio A", 5, "principal")
      .run();

    await app.request(
      `/hunt/eventos/${evento1Id}/premios/${premio1Res.meta.last_row_id}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );

    const evento2Res = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento B", pastDate(1), futureDate(3))
      .run();
    const evento2Id = evento2Res.meta.last_row_id;

    const puntos2 = await db
      .prepare("SELECT puntos FROM puntos_evento WHERE evento_id = ? AND usuario_id = ?")
      .bind(evento2Id, 3)
      .first<{ puntos: number }>();

    expect(puntos2).toBeNull();

    const puntos1 = await db
      .prepare("SELECT puntos FROM puntos_evento WHERE evento_id = ? AND usuario_id = ?")
      .bind(evento1Id, 3)
      .first<{ puntos: number }>();
    expect(puntos1?.puntos).toBe(10);
  });

  it("dos reclamos por el último premio: uno gana, otro recibe 422 por stock agotado", async () => {
    const app = buildApp();
    const token3 = await makeToken(3, "cliente");
    const token4 = await makeToken(4, "cliente");

    await db
      .prepare(`INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`)
      .bind("cliente", "cli4@test.com", "hash", "Cli 4 Test")
      .run();

    const eventoRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento UltimoPremio", pastDate(1), futureDate(3))
      .run();
    const eventoId = eventoRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Último Premio", 1, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    const res1 = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token3}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );
    expect(res1.status).toBe(201);

    const res2 = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token4}` },
        body: JSON.stringify({}),
      },
      { DB: db, JWT_SECRET }
    );
    expect(res2.status).toBe(422);

    const stockRow = await db
      .prepare(`SELECT COUNT(*) AS cnt FROM premios_entregados
                WHERE premio_id = ? AND estado = 'entregado'`)
      .bind(premioId)
      .first<{ cnt: number }>();
    expect(stockRow?.cnt).toBe(1);
  });
});

describe("GET /hunt/eventos/:eventoId/premios/:premioId/ganadores", () => {
  it("devuelve los ganadores del premio", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Ganadores", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Ganador", 2, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    await db
      .prepare(`INSERT INTO premios_entregados (premio_id, usuario_id, estado)
                VALUES (?, ?, 'entregado')`)
      .bind(premioId, 3)
      .run();

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/ganadores`,
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { ganadores: Array<Record<string, unknown>> };
    expect(body.ganadores.length).toBe(1);
    expect(body.ganadores[0].usuario_id).toBe(3);
    expect(body.ganadores[0].usuario_nombre).toBe("Cli Test");
    expect(body.ganadores[0].usuario_email).toBe("cli@test.com");
    expect(body.ganadores[0].estado).toBe("entregado");
  });

  it("devuelve lista vacía cuando nadie ha ganado el premio", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento SinGanadores", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio SinGanadores", 2, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/ganadores`,
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { ganadores: unknown[] };
    expect(body.ganadores).toEqual([]);
  });

  it("niega el acceso a otro organizador", async () => {
    const app = buildApp();

    await db
      .prepare(`INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
                VALUES (?, ?, ?, ?)`)
      .bind("organizador", "org2@test.com", "hash", "Org 2")
      .run();
    const org2Id = (await db.prepare("SELECT id FROM usuarios WHERE email = ?")
      .bind("org2@test.com")
      .first<{ id: number }>())?.id;
    if (!org2Id) throw new Error("org2 no creado");

    const otherToken = await makeToken(org2Id, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Ajeno", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio Ajeno", 2, "principal")
      .run();
    const premioId = premioRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/ganadores`,
      { headers: { Authorization: `Bearer ${otherToken}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(403);
  });

  it("404 si el premio no pertenece al evento", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento PremioAjeno", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const otroPremioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Premio De Otro Evento", 2, "principal")
      .run();

    const res = await app.request(
      `/hunt/eventos/${eventoId}/premios/${otroPremioRes.meta.last_row_id + 999}/ganadores`,
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(404);
  });
});
