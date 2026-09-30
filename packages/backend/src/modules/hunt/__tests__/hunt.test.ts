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

/** El mismo dia que futureDate, pero solo la parte de la fecha. */
function futureDay(days: number): string {
  return futureDate(days).slice(0, 10);
}

/** Un momento concreto del dia futuro indicado. */
function futureMoment(days: number, hora: string): string {
  return `${futureDay(days)} ${hora}`;
}

/**
 * Un momento escrito en hora de Ecuador, desplazado del ahora la cantidad de
 * minutos indicada. Ecuador no tiene horario de verano, asi que la hora de
 * pared es siempre el reloj menos cinco horas.
 */
function momentoAlrededorDeAhora(minutos: number): string {
  return new Date(Date.now() - 5 * 3600_000 + minutos * 60_000)
    .toISOString()
    .replace("T", " ")
    .slice(0, 19);
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
    fcm_token TEXT,
        fcm_token_updated_at TEXT,
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
    estado TEXT NOT NULL DEFAULT 'programado' CHECK (estado IN ('programado','activo','finalizado')),
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

  await db.prepare(`CREATE TABLE IF NOT EXISTS facturas (
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
    cupon_id INTEGER,
    foto TEXT,
    estado TEXT NOT NULL DEFAULT 'aprobada' CHECK (estado IN (
      'aprobada',
      'pendiente_revision_nombre',
      'pendiente_verificacion_sri',
      'rechazada'
    )),
    motivo_rechazo TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    sri_estado_bruto TEXT
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
          hora_inicio: futureMoment(1, "10:00:00"),
          hora_fin: futureMoment(1, "12:00:00"),
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
  });

  it("rechaza una ronda con solo la hora, sin fecha", async () => {
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

    expect(res.status).toBe(400);
    // El mensaje tiene que decir que formato se espera, si no el organizador
    // no sabe que escribir.
    const cuerpo = (await res.json()) as { error: string };
    expect(cuerpo.error).toContain("AAAA-MM-DD HH:MM:SS");
  });

  it("acepta una ronda nocturna con fecha del dia siguiente", async () => {
    const app = buildApp();
    const token = await makeToken(1, "organizador");

    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(1, "Evento Nocturno", futureDate(1), futureDate(3))
      .run();
    const eventoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/hunt/eventos/${eventoId}/rondas`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          nombre: "Ronda de madrugada",
          hora_inicio: futureMoment(1, "22:00:00"),
          hora_fin: futureMoment(2, "02:00:00"),
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
  });

  it("rechaza una ronda que termina antes de empezar", async () => {
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
          nombre: "Ronda al reves",
          hora_inicio: futureMoment(2, "12:00:00"),
          hora_fin: futureMoment(1, "12:00:00"),
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(400);
    const cuerpo = (await res.json()) as { error: string };
    // El mensaje tiene que explicar como se escribe una ronda que cruza la
    // medianoche, que es el caso que la gente se equivoca.
    expect(cuerpo.error).toContain("medianoche");
  });

  it("rechaza una ronda que empieza y acaba en el mismo instante", async () => {
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
          nombre: "Ronda de un instante",
          hora_inicio: futureMoment(1, "10:00:00"),
          hora_fin: futureMoment(1, "10:00:00"),
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(400);
  });
});

describe("validacion de premios", () => {
  async function crearEvento(organizadorId: number): Promise<number> {
    const insertRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(organizadorId, "Evento Premios", futureDate(1), futureDate(3))
      .run();
    return insertRes.meta.last_row_id;
  }

  async function crearPremio(
    token: string,
    eventoId: number,
    cuerpo: Record<string, unknown>
  ) {
    const app = buildApp();
    return app.request(
      `/hunt/eventos/${eventoId}/premios`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify(cuerpo),
      },
      { DB: db, JWT_SECRET }
    );
  }

  it("rechaza un premio de frecuencia sin umbral de compras", async () => {
    const token = await makeToken(1, "organizador");
    const eventoId = await crearEvento(1);

    const res = await crearPremio(token, eventoId, {
      nombre: "Camiseta",
      stock: 5,
      tipo: "frecuencia",
    });

    // Sin numero de compras no se sabe cuando se gana, asi que no se crea.
    expect(res.status).toBe(400);
    const cuerpo = (await res.json()) as { error: string };
    expect(cuerpo.error).toContain("criterio_frecuencia");
  });

  it("acepta un premio de frecuencia con umbral de compras", async () => {
    const token = await makeToken(1, "organizador");
    const eventoId = await crearEvento(1);

    const res = await crearPremio(token, eventoId, {
      nombre: "Camiseta",
      stock: 5,
      tipo: "frecuencia",
      criterio_frecuencia: 3,
    });

    expect(res.status).toBe(201);
  });

  it("rechaza un umbral de compras que no sea un entero positivo", async () => {
    const token = await makeToken(1, "organizador");
    const eventoId = await crearEvento(1);

    for (const criterio of [0, -2, 2.5]) {
      const res = await crearPremio(token, eventoId, {
        nombre: "Camiseta",
        stock: 5,
        tipo: "frecuencia",
        criterio_frecuencia: criterio,
      });
      expect(res.status).toBe(400);
    }
  });

  it("no exige umbral de compras a los premios que no son de frecuencia", async () => {
    const token = await makeToken(1, "organizador");
    const eventoId = await crearEvento(1);

    const res = await crearPremio(token, eventoId, {
      nombre: "Combo",
      stock: 5,
      tipo: "principal",
    });

    expect(res.status).toBe(201);
  });

  it("rechaza una ronda de otro evento", async () => {
    const token = await makeToken(1, "organizador");
    const eventoId = await crearEvento(1);
    const otroEventoId = await crearEvento(1);

    const rondaRes = await db
      .prepare(`INSERT INTO rondas (evento_id, nombre, hora_inicio, hora_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(otroEventoId, "Ronda ajena", futureMoment(1, "10:00:00"), futureMoment(1, "12:00:00"))
      .run();
    const rondaId = rondaRes.meta.last_row_id;

    const res = await crearPremio(token, eventoId, {
      nombre: "Premio con ronda ajena",
      stock: 5,
      tipo: "consolacion",
      ronda_id: rondaId,
    });

    // El premio contaria con las horas de una ronda que no es suya.
    expect(res.status).toBe(400);
  });

  it("acepta una ronda de su propio evento", async () => {
    const token = await makeToken(1, "organizador");
    const eventoId = await crearEvento(1);

    const rondaRes = await db
      .prepare(`INSERT INTO rondas (evento_id, nombre, hora_inicio, hora_fin)
                VALUES (?, ?, ?, ?)`)
      .bind(eventoId, "Ronda propia", futureMoment(1, "10:00:00"), futureMoment(1, "12:00:00"))
      .run();
    const rondaId = rondaRes.meta.last_row_id;

    const res = await crearPremio(token, eventoId, {
      nombre: "Premio con ronda propia",
      stock: 5,
      tipo: "consolacion",
      ronda_id: rondaId,
    });

    expect(res.status).toBe(201);
  });

  it("rechaza un stock con decimales", async () => {
    const token = await makeToken(1, "organizador");
    const eventoId = await crearEvento(1);

    const res = await crearPremio(token, eventoId, {
      nombre: "Stock raro",
      stock: 2.5,
      tipo: "consolacion",
    });

    expect(res.status).toBe(400);
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
  describe("ventana horaria de la ronda del premio", () => {
    /** Evento abierto con un premio que pertenece a una ronda. */
    async function premioDeRonda(
      nombre: string,
      horaInicio: string,
      horaFin: string
    ) {
      const eventoRes = await db
        .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                  VALUES (?, ?, ?, ?)`)
        .bind(1, nombre, pastDate(1), futureDate(3))
        .run();
      const eventoId = eventoRes.meta.last_row_id;

      const rondaRes = await db
        .prepare(`INSERT INTO rondas (evento_id, nombre, hora_inicio, hora_fin)
                  VALUES (?, ?, ?, ?)`)
        .bind(eventoId, "Ronda de prueba", horaInicio, horaFin)
        .run();

      const premioRes = await db
        .prepare(`INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo)
                  VALUES (?, ?, ?, ?, ?)`)
        .bind(eventoId, rondaRes.meta.last_row_id, "Premio de ronda", 3, "principal")
        .run();

      return { eventoId, premioId: Number(premioRes.meta.last_row_id) };
    }

    async function reclamar(eventoId: number, premioId: number) {
      const app = buildApp();
      const token = await makeToken(3, "cliente");
      return app.request(
        `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
          body: JSON.stringify({}),
        },
        { DB: db, JWT_SECRET }
      );
    }

    it("reclama con normalidad dentro de la ventana de la ronda", async () => {
      const { eventoId, premioId } = await premioDeRonda(
        "Evento Ronda Abierta",
        momentoAlrededorDeAhora(-60),
        momentoAlrededorDeAhora(60)
      );

      const res = await reclamar(eventoId, premioId);

      expect(res.status).toBe(201);
      const body = (await res.json()) as { premio_id: string; puntos_ganados: number };
      expect(body.premio_id).toBe(String(premioId));
      expect(body.puntos_ganados).toBe(10);

      const entregado = await db
        .prepare("SELECT id FROM premios_entregados WHERE premio_id = ? AND usuario_id = 3")
        .bind(premioId)
        .first();
      expect(entregado).toBeTruthy();
    });

    it("rechaza con 422 cuando la ronda ya cerro", async () => {
      const { eventoId, premioId } = await premioDeRonda(
        "Evento Ronda Cerrada",
        momentoAlrededorDeAhora(-120),
        momentoAlrededorDeAhora(-60)
      );

      const res = await reclamar(eventoId, premioId);

      expect(res.status).toBe(422);
      expect((await res.json()) as { error: string }).toEqual({
        error: "Esta ronda ya cerró.",
      });

      // Lo importante: no se entrega nada ni se suman puntos.
      const entregado = await db
        .prepare("SELECT id FROM premios_entregados WHERE premio_id = ? AND usuario_id = 3")
        .bind(premioId)
        .first();
      expect(entregado).toBeNull();

      const puntos = await db
        .prepare("SELECT puntos FROM puntos_evento WHERE evento_id = ? AND usuario_id = 3")
        .bind(eventoId)
        .first();
      expect(puntos).toBeNull();
    });

    it("rechaza con 422 cuando la ronda aun no empieza", async () => {
      const { eventoId, premioId } = await premioDeRonda(
        "Evento Ronda Por Empezar",
        momentoAlrededorDeAhora(60),
        momentoAlrededorDeAhora(120)
      );

      const res = await reclamar(eventoId, premioId);

      expect(res.status).toBe(422);
      expect((await res.json()) as { error: string }).toEqual({
        error: "Esta ronda ya cerró.",
      });

      const entregado = await db
        .prepare("SELECT id FROM premios_entregados WHERE premio_id = ? AND usuario_id = 3")
        .bind(premioId)
        .first();
      expect(entregado).toBeNull();
    });

    it("un premio sin ronda no depende de ninguna ventana de ronda", async () => {
      // El evento sigue abierto, asi que este premio se entrega como siempre.
      const eventoRes = await db
        .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                  VALUES (?, ?, ?, ?)`)
        .bind(1, "Evento Premio De Evento", pastDate(1), futureDate(3))
        .run();
      const eventoId = eventoRes.meta.last_row_id;

      const premioRes = await db
        .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                  VALUES (?, ?, ?, ?)`)
        .bind(eventoId, "Premio de todo el evento", 3, "principal")
        .run();

      const premioId = Number(premioRes.meta.last_row_id);
      const res = await reclamar(eventoId, premioId);

      expect(res.status).toBe(201);
      expect((await res.json()) as { puntos_ganados: number }).toEqual({
        mensaje: 'Premio "Premio de todo el evento" reclamado',
        premio_id: String(premioId),
        puntos_ganados: 10,
      });
    });
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

describe("GET /hunt/eventos/:eventoId/participantes-sin-premio", () => {
  /**
   * El pool de tests revierte lo que se escribe dentro de un test, asi que cada
   * caso arma su propio evento y sus propias compras.
   */

  async function crearCliente(email: string, nombre: string): Promise<number> {
    await db
      .prepare(`INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
                VALUES (?, ?, ?, ?)`)
      .bind("cliente", email, "hash", nombre)
      .run();
    const row = await db
      .prepare("SELECT id FROM usuarios WHERE email = ?")
      .bind(email)
      .first<{ id: number }>();
    if (!row) throw new Error("cliente no creado");
    return row.id;
  }

  async function crearComercio(nombre: string): Promise<number> {
    const res = await db
      .prepare(`INSERT INTO comercios (usuario_id, nombre, categoria)
                VALUES (1, ?, 'Cafeteria')`)
      .bind(nombre)
      .run();
    return res.meta.last_row_id;
  }

  async function crearEvento(opciones: { requiere_entrada?: number } = {}): Promise<number> {
    const res = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada)
                VALUES (1, 'Evento Participantes', ?, ?, ?)`)
      .bind(futureDate(1), futureDate(3), opciones.requiere_entrada ?? 0)
      .run();
    return res.meta.last_row_id;
  }

  async function patrocinar(
    eventoId: number,
    comercioId: number,
    estado = "aprobado"
  ): Promise<void> {
    await db
      .prepare(`INSERT INTO eventos_sponsors (evento_id, comercio_id, estado)
                VALUES (?, ?, ?)`)
      .bind(eventoId, comercioId, estado)
      .run();
  }

  /**
   * Compra como la deja la app: con comercio y fecha, nunca atada a un evento.
   * El evento se reconoce por el patrocinio del comercio.
   */
  async function comprar(
    clienteId: number,
    comercioId: number,
    fechaFactura: string,
    estado = "aprobada"
  ): Promise<void> {
    await db
      .prepare(`INSERT INTO facturas (cliente_id, comercio_id, nivel_verificacion, fecha_factura, estado)
                VALUES (?, ?, 2, ?, ?)`)
      .bind(clienteId, comercioId, fechaFactura, estado)
      .run();
  }

  async function consultar(eventoId: number, token: string): Promise<{
    status: number;
    participantes: Array<{ id: number; nombre_completo: string; email: string }>;
    advertencias?: string[];
  }> {
    const app = buildApp();
    const res = await app.request(
      `/hunt/eventos/${eventoId}/participantes-sin-premio`,
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );
    return (await res.json()) as {
      status: number;
      participantes: Array<{ id: number; nombre_completo: string; email: string }>;
      advertencias?: string[];
    };
  }

  it("lista clientes con compra en comercio patrocinador y sin premio entregado", async () => {
    const token = await makeToken(1, "organizador");
    const sinPremio = await crearCliente("cli-sin@test.com", "Cliente Sin Premio");
    const conPremio = await crearCliente("cli-con@test.com", "Cliente Con Premio");
    const eventoId = await crearEvento();
    const comercio = await crearComercio("Cafeteria Patrocinadora");
    await patrocinar(eventoId, comercio);

    await comprar(sinPremio, comercio, futureDate(2));
    await comprar(conPremio, comercio, futureDate(2));

    const premioRes = await db
      .prepare(`INSERT INTO premios (evento_id, nombre, stock, tipo)
                VALUES (?, 'Premio Entregado', 5, 'principal')`)
      .bind(eventoId)
      .run();
    await db
      .prepare(`INSERT INTO premios_entregados (premio_id, usuario_id, estado)
                VALUES (?, ?, 'entregado')`)
      .bind(premioRes.meta.last_row_id, conPremio)
      .run();

    const body = await consultar(eventoId, token);

    expect(body.participantes).toHaveLength(1);
    expect(body.participantes[0].id).toBe(sinPremio);
    expect(body.participantes[0].nombre_completo).toBe("Cliente Sin Premio");
    expect(body.participantes[0].email).toBe("cli-sin@test.com");
  });

  it("no cuenta compras de otro evento, de un patrocinador sin aprobar o no aprobadas", async () => {
    const token = await makeToken(1, "organizador");
    const eventoId = await crearEvento();
    const otroEventoId = await crearEvento();

    const patrocinado = await crearComercio("Cafeteria Aprobada");
    const pendiente = await crearComercio("Cafeteria Sin Aprobar");
    const ajeno = await crearComercio("Cafeteria de Otro Evento");
    await patrocinar(eventoId, patrocinado, "aprobado");
    await patrocinar(eventoId, pendiente, "pendiente");
    await patrocinar(otroEventoId, ajeno, "aprobado");

    const antesDeEvento = await crearCliente("cli-antes@test.com", "Compra Antes");
    const despuesDeEvento = await crearCliente("cli-despues@test.com", "Compra Despues");
    const sinAprobar = await crearCliente("cli-pendiente@test.com", "Patrocinador Pendiente");
    const deOtro = await crearCliente("cli-otro@test.com", "Otro Evento");
    const noAprobada = await crearCliente("cli-rechazada@test.com", "Compra Rechazada");

    // Fuera de la ventana del evento (1 a 3 dias desde hoy).
    await comprar(antesDeEvento, patrocinado, futureDate(-5));
    await comprar(despuesDeEvento, patrocinado, futureDate(9));
    // En un comercio que todavia no acepto ser patrocinador.
    await comprar(sinAprobar, pendiente, futureDate(2));
    // Comercio patrocinador de otro evento.
    await comprar(deOtro, ajeno, futureDate(2));
    // Compra que el SRI no aprobo.
    await comprar(noAprobada, patrocinado, futureDate(2), "rechazada");

    const body = await consultar(eventoId, token);

    expect(body.participantes).toEqual([]);
  });

  it("incluye a quien solo tiene entrada aprobada cuando el evento pide entrada", async () => {
    const token = await makeToken(1, "organizador");
    const soloEntrada = await crearCliente("cli-entrada@test.com", "Solo Entrada");
    const entradaPendiente = await crearCliente("cli-pagada@test.com", "Entrada Pendiente");
    const conCompra = await crearCliente("cli-compra@test.com", "Con Compra");
    const eventoId = await crearEvento({ requiere_entrada: 1 });
    const comercio = await crearComercio("Cafeteria Con Entrada");
    await patrocinar(eventoId, comercio);

    await db
      .prepare(`INSERT INTO entradas (evento_id, cliente_id, estado) VALUES (?, ?, 'aprobada')`)
      .bind(eventoId, soloEntrada)
      .run();
    await db
      .prepare(`INSERT INTO entradas (evento_id, cliente_id, estado) VALUES (?, ?, 'pendiente_pago')`)
      .bind(eventoId, entradaPendiente)
      .run();
    await comprar(conCompra, comercio, futureDate(2));

    const body = await consultar(eventoId, token);

    expect(body.participantes.map((p) => p.id).sort()).toEqual(
      [soloEntrada, conCompra].sort()
    );
  });

  it("no cuenta la entrada si el evento no la pide", async () => {
    const token = await makeToken(1, "organizador");
    const soloEntrada = await crearCliente("cli-solo-entrada@test.com", "Solo Entrada");
    const eventoId = await crearEvento({ requiere_entrada: 0 });

    await db
      .prepare(`INSERT INTO entradas (evento_id, cliente_id, estado) VALUES (?, ?, 'aprobada')`)
      .bind(eventoId, soloEntrada)
      .run();

    const body = await consultar(eventoId, token);

    expect(body.participantes).toEqual([]);
  });

  it("avisa que no pudo leer las fechas en vez de devolver una lista vacia", async () => {
    const token = await makeToken(1, "organizador");
    const cliente = await crearCliente("cli-fechas@test.com", "Cliente Con Fechas");
    const eventoRes = await db
      .prepare(`INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
                VALUES (1, 'Evento Sin Fechas Legibles', 'no-es-fecha', 'tampoco')`)
      .run();
    const eventoId = eventoRes.meta.last_row_id;
    const comercio = await crearComercio("Cafeteria Sin Fechas");
    await patrocinar(eventoId, comercio);
    await comprar(cliente, comercio, futureDate(2));

    const body = await consultar(eventoId, token);

    expect(body.participantes).toEqual([]);
    expect(body.advertencias?.[0]).toContain("fechas");
  });

  it("niega el acceso a otro organizador", async () => {
    const app = buildApp();

    await db
      .prepare(`INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
                VALUES (?, ?, ?, ?)`)
      .bind("organizador", "org3@test.com", "hash", "Org 3")
      .run();
    const org3Id = (await db.prepare("SELECT id FROM usuarios WHERE email = ?")
      .bind("org3@test.com")
      .first<{ id: number }>())?.id;
    if (!org3Id) throw new Error("org3 no creado");

    const otherToken = await makeToken(org3Id, "organizador");
    const eventoId = await crearEvento();

    const res = await app.request(
      `/hunt/eventos/${eventoId}/participantes-sin-premio`,
      { headers: { Authorization: `Bearer ${otherToken}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(403);
  });
});
