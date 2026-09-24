import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { flash } from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-flash";

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/flash", flash);
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
  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rol TEXT NOT NULL CHECK (rol IN ('cliente','negocio','organizador','admin')),
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        nombre_completo TEXT NOT NULL,
        fecha_nacimiento TEXT,
        consentimiento_publicidad INTEGER,
        consentimiento_publicidad_fecha TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS comercios (
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
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS cupones (
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
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS promociones_flash (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        comercio_id INTEGER NOT NULL REFERENCES comercios(id),
        titulo TEXT NOT NULL,
        descripcion TEXT,
        descuento_porcentaje REAL NOT NULL,
        inicia_en TEXT NOT NULL,
        termina_en TEXT NOT NULL,
        latitud REAL,
        longitud REAL,
        radio_km REAL DEFAULT 5,
        categoria TEXT,
        max_usuarios INTEGER,
        usuarios_notificados INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS promociones_flash_claims (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        promocion_id INTEGER NOT NULL REFERENCES promociones_flash(id),
        usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
        cupon_id INTEGER REFERENCES cupones(id),
        claimed_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE (promocion_id, usuario_id)
      )`
    )
    .run();

  // Usuarios
  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("negocio", "negocio@test.com", "hash", "Dueño Flash")
    .run();
  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "cliente@test.com", "hash", "Cliente Flash")
    .run();

  // Comercio con ubicación (Quito centro: -0.18, -78.47)
  await db
    .prepare(
      `INSERT INTO comercios (usuario_id, nombre, categoria, latitud, longitud) VALUES (?, ?, ?, ?, ?)`
    )
    .bind(1, "Café Flash", "Gastronomía", -0.1807, -78.4678)
    .run();
});

describe("GET /flash/promociones - filtros", () => {
  it("retorna promociones activas", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en, latitud, longitud)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(1, "Flash Activa", 25, pastDate(1), futureDate(7), -0.1807, -78.4678)
      .run();

    const res = await app.request(
      "/flash/promociones",
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { promociones: unknown[] };
    expect(body.promociones.length).toBeGreaterThanOrEqual(1);
  });

  it("excluye promociones vencidas", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en)
         VALUES (?, ?, ?, ?, ?)`
      )
      .bind(1, "Flash Vencida", 10, pastDate(10), pastDate(1))
      .run();

    const res = await app.request(
      "/flash/promociones",
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { promociones: { titulo: string }[] };
    expect(
      body.promociones.some((p) => p.titulo === "Flash Vencida")
    ).toBe(false);
  });

  it("filtra por categoría", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en, categoria)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .bind(1, "Flash Gastronomía", 15, pastDate(1), futureDate(3), "Gastronomía")
      .run();

    const res = await app.request(
      "/flash/promociones?categoria=Gastronomía",
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      promociones: { titulo: string }[];
    };
    expect(
      body.promociones.some((p) => p.titulo === "Flash Gastronomía")
    ).toBe(true);
  });
});

describe("POST /flash/promociones - crear", () => {
  it("negocio crea promoción para su comercio", async () => {
    const app = buildApp();
    const token = await makeToken(1, "negocio");

    const res = await app.request(
      "/flash/promociones",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          comercio_id: 1,
          titulo: "Flash Test",
          descuento_porcentaje: 20,
          inicia_en: pastDate(1),
          termina_en: futureDate(5),
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { promocion: { titulo: string } };
    expect(body.promocion.titulo).toBe("Flash Test");
  });

  it("descuento inválido: error 400", async () => {
    const app = buildApp();
    const token = await makeToken(1, "negocio");

    const res = await app.request(
      "/flash/promociones",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          comercio_id: 1,
          titulo: "Flash Inválida",
          descuento_porcentaje: 150,
          inicia_en: pastDate(1),
          termina_en: futureDate(5),
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(400);
  });

  it("fechas inválidas: error 400", async () => {
    const app = buildApp();
    const token = await makeToken(1, "negocio");

    const res = await app.request(
      "/flash/promociones",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          comercio_id: 1,
          titulo: "Flash Fechas Mal",
          descuento_porcentaje: 10,
          inicia_en: futureDate(5),
          termina_en: pastDate(1),
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(400);
  });
});

describe("POST /flash/promociones/:id/claim", () => {
  it("reclama promoción activa y genera cupón", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    const insertRes = await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en, latitud, longitud, radio_km)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(1, "Claim Test", 30, pastDate(1), futureDate(7), -0.1807, -78.4678, 5)
      .run();
    const promoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/flash/promociones/${promoId}/claim`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as {
      cupon: { codigo_qr: string; descuento: number };
      mensaje: string;
    };
    expect(body.cupon.codigo_qr).toMatch(/^FLASH-/);
    expect(body.cupon.descuento).toBe(30);
    expect(body.mensaje).toContain("30%");

    const claim = await db
      .prepare(
        "SELECT id FROM promociones_flash_claims WHERE promocion_id = ? AND usuario_id = ?"
      )
      .bind(promoId, 2)
      .first();
    expect(claim).not.toBeNull();
  });

  it("reclamar dos veces: error 409", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    const insertRes = await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en)
         VALUES (?, ?, ?, ?, ?)`
      )
      .bind(1, "Doble Claim", 10, pastDate(1), futureDate(3))
      .run();
    const promoId = insertRes.meta.last_row_id;

    await app.request(
      `/flash/promociones/${promoId}/claim`,
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    const res = await app.request(
      `/flash/promociones/${promoId}/claim`,
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(409);
  });

  it("reclamar promoción vencida: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    const insertRes = await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en)
         VALUES (?, ?, ?, ?, ?)`
      )
      .bind(1, "Claim Vencida", 10, pastDate(10), pastDate(1))
      .run();
    const promoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/flash/promociones/${promoId}/claim`,
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
  });

  it("reclamar promoción futura: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    const insertRes = await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en)
         VALUES (?, ?, ?, ?, ?)`
      )
      .bind(1, "Claim Futura", 10, futureDate(5), futureDate(10))
      .run();
    const promoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/flash/promociones/${promoId}/claim`,
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
  });

  it("máximo de usuarios alcanzado: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    const insertRes = await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en, max_usuarios, usuarios_notificados)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(1, "Max Users", 10, pastDate(1), futureDate(3), 1, 1)
      .run();
    const promoId = insertRes.meta.last_row_id;

    const res = await app.request(
      `/flash/promociones/${promoId}/claim`,
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
  });
});

describe("GET /flash/mis-cupones", () => {
  it("retorna cupones del usuario", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    await db
      .prepare(
        `INSERT INTO cupones
         (comercio_id, cliente_id, codigo_qr, estado, tipo, descuento, expira_en)
         VALUES (?, ?, ?, 'activo', 'flash', ?, ?)`
      )
      .bind(1, 2, "FLASH-TEST-001", 20, futureDate(30))
      .run();

    const res = await app.request(
      "/flash/mis-cupones",
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { cupones: unknown[] };
    expect(body.cupones.length).toBeGreaterThanOrEqual(1);
  });

  it("marca como expirado cupones vencidos al consultar", async () => {
    const app = buildApp();
    const token = await makeToken(2, "cliente");

    await db
      .prepare(
        `INSERT INTO cupones
         (comercio_id, cliente_id, codigo_qr, estado, tipo, descuento, expira_en)
         VALUES (?, ?, ?, 'activo', 'flash', ?, ?)`
      )
      .bind(1, 2, "FLASH-EXPIRED-001", 10, pastDate(1))
      .run();

    await app.request(
      "/flash/mis-cupones",
      { headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET }
    );

    const row = await db
      .prepare("SELECT estado FROM cupones WHERE codigo_qr = ?")
      .bind("FLASH-EXPIRED-001")
      .first<{ estado: string }>();
    expect(row?.estado).toBe("expirado");
  });
});

describe("POST /flash/cupones/:codigo/canjear", () => {
  it("negocio canjea cupón activo de su comercio", async () => {
    const app = buildApp();
    const token = await makeToken(1, "negocio");

    await db
      .prepare(
        `INSERT INTO cupones
         (comercio_id, cliente_id, codigo_qr, estado, tipo, descuento, expira_en)
         VALUES (?, ?, ?, 'activo', 'flash', ?, ?)`
      )
      .bind(1, 2, "FLASH-CANJE-001", 15, futureDate(30))
      .run();

    const res = await app.request(
      "/flash/cupones/FLASH-CANJE-001/canjear",
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);

    const row = await db
      .prepare("SELECT estado, canjeado_en FROM cupones WHERE codigo_qr = ?")
      .bind("FLASH-CANJE-001")
      .first<{ estado: string; canjeado_en: string | null }>();
    expect(row?.estado).toBe("utilizado");
    expect(row?.canjeado_en).not.toBeNull();
  });

  it("canjear cupón ya utilizado: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(1, "negocio");

    await db
      .prepare(
        `INSERT INTO cupones
         (comercio_id, cliente_id, codigo_qr, estado, tipo, descuento)
         VALUES (?, ?, ?, 'utilizado', 'flash', 10)`
      )
      .bind(1, 2, "FLASH-YA-CANJEADO")
      .run();

    const res = await app.request(
      "/flash/cupones/FLASH-YA-CANJEADO/canjear",
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
  });

  it("canjear cupón expirado: error 422", async () => {
    const app = buildApp();
    const token = await makeToken(1, "negocio");

    await db
      .prepare(
        `INSERT INTO cupones
         (comercio_id, cliente_id, codigo_qr, estado, tipo, descuento, expira_en)
         VALUES (?, ?, ?, 'activo', 'flash', 10, ?)`
      )
      .bind(1, 2, "FLASH-EXPIRED-CANJE", pastDate(1))
      .run();

    const res = await app.request(
      "/flash/cupones/FLASH-EXPIRED-CANJE/canjear",
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
    const row = await db
      .prepare("SELECT estado FROM cupones WHERE codigo_qr = ?")
      .bind("FLASH-EXPIRED-CANJE")
      .first<{ estado: string }>();
    expect(row?.estado).toBe("expirado");
  });
});
