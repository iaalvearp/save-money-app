import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { createFacturas } from "../../../modules/facturas/index";
import type { SRIResultado } from "../../../modules/sri/index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-antifraude";

function computeCheckDigit(digits: number[]): number {
  let sum = 0;
  let multiplier = 2;
  for (let i = digits.length - 1; i >= 0; i--) {
    sum += digits[i] * multiplier;
    multiplier++;
    if (multiplier > 7) multiplier = 2;
  }
  const remainder = sum % 11;
  return remainder === 0 ? 0 : 11 - remainder;
}

function buildValidClave(): string {
  const base = "123456789012345678901234567890123456789012345678";
  const digits = base.split("").map(Number);
  const checkDigit = computeCheckDigit(digits);
  return base.slice(0, 48) + String(checkDigit);
}

async function makeToken(sub: number, rol: string): Promise<string> {
  return sign(
    { sub: String(sub), rol, exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
  );
}

function buildApp(
  validarChecksumFn: (clave: string) => boolean = () => true,
  consultarSRIFn: (clave: string) => Promise<SRIResultado> = async () => ({
    estado: "autorizado",
    ruc_emisor: "0999999999999",
    nombre_comprador: "Test User",
    fecha_autorizacion: "2026-09-15",
    monto: 25.5,
    mensaje_sri: "",
  })
) {
  const facturas = createFacturas(validarChecksumFn, consultarSRIFn);
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/facturas", facturas);
  return app;
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
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS eventos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organizador_id INTEGER NOT NULL REFERENCES usuarios(id),
        nombre TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        requiere_entrada INTEGER NOT NULL DEFAULT 0,
        precio_entrada REAL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS facturas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
        comercio_id INTEGER,
        evento_id INTEGER,
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
        sri_estado_bruto TEXT,
        challenge_nonce TEXT,
        claim_hash TEXT
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS challenges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
        nonce TEXT NOT NULL UNIQUE,
        expira_en TEXT NOT NULL,
        usado INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
       VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "antifraude1@example.com", "hash", "Test User")
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
       VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "antifraude2@example.com", "hash", "Otro Usuario")
    .run();

  await db
    .prepare(
      `INSERT INTO comercios (usuario_id, nombre)
       VALUES (?, ?)`
    )
    .bind(1, "Mi Comercio")
    .run();

  await db
    .prepare(
      `INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
       VALUES (?, ?, ?, ?)`
    )
    .bind(1, "Festival Test", "2026-09-01", "2026-09-30")
    .run();
});

describe("Antifraude - Duplicados SRI (nivel 1)", () => {
  it("rechaza clave SRI ya registrada por el mismo usuario", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");
    const clave = buildValidClave();

    await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 1,
          comercio_id: 1,
          clave_acceso_49: clave,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 1,
          comercio_id: 1,
          clave_acceso_49: clave,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(409);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("registrada");
  });
});

describe("Antifraude - Duplicados ticket físico (nivel 2)", () => {
  it("rechaza ticket con mismos datos estructurados", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-1000001",
          ruc_emisor: "0999999999999",
          fecha_factura: "2026-09-15",
          monto_total: 25.50,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-1000001",
          ruc_emisor: "0999999999999",
          fecha_factura: "2026-09-15",
          monto_total: 25.50,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(409);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("previamente");
  });

  it("permite ticket con datos diferentes", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-2000001",
          ruc_emisor: "0999999999999",
          fecha_factura: "2026-09-15",
          monto_total: 25.50,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-2000002",
          ruc_emisor: "0999999999999",
          fecha_factura: "2026-09-15",
          monto_total: 30.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
  });
});

describe("Antifraude - Duplicados ticket físico (nivel 3)", () => {
  it("rechaza nivel 3 con mismo ticket que nivel 2", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-3000001",
          ruc_emisor: "0999999999999",
          fecha_factura: "2026-09-15",
          monto_total: 15.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    const challengeRes = await app.request(
      "/facturas/challenge",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );
    const challengeBody = (await challengeRes.json()) as { nonce: string };

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 3,
          comercio_id: 1,
          challenge_nonce: challengeBody.nonce,
          numero_factura: "001-001-3000001",
          ruc_emisor: "0999999999999",
          fecha_factura: "2026-09-15",
          monto_total: 15.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(409);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("registrado");
  });
});

describe("Antifraude - Usuario distinto con misma evidencia", () => {
  it("rechaza cuando otro usuario intenta registrar el mismo ticket", async () => {
    const app = buildApp();
    const token1 = await makeToken(1, "cliente");
    const token2 = await makeToken(2, "cliente");

    await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token1}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-4000001",
          ruc_emisor: "0999999999999",
          fecha_factura: "2026-09-15",
          monto_total: 10.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token2}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-4000001",
          ruc_emisor: "0999999999999",
          fecha_factura: "2026-09-15",
          monto_total: 10.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(409);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("otro usuario");
  });
});

describe("Antifraude - Compra fuera del horario del evento", () => {
  it("rechaza compra con fecha fuera del rango del evento", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          evento_id: 1,
          numero_factura: "001-001-5000001",
          fecha_factura: "2026-08-15",
          monto_total: 20.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(422);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("fuera del rango");
  });

  it("acepta compra con fecha dentro del rango del evento", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          evento_id: 1,
          numero_factura: "001-001-5000002",
          fecha_factura: "2026-09-15",
          monto_total: 20.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
  });

  it("acepta compra sin evento_id (no aplica validación de horario)", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-5000003",
          fecha_factura: "2026-01-01",
          monto_total: 10.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
  });
});

describe("Antifraude - Nombre no coincidente", () => {
  it("nivel 1 con enforce crea estado pendiente_revision_nombre cuando nombre no coincide", async () => {
    const app = buildApp(
      () => true,
      async () => ({
        estado: "autorizado",
        ruc_emisor: "0999999999999",
        nombre_comprador: "Nombre Diferente",
        fecha_autorizacion: "2026-09-15",
        monto: 25.5,
        mensaje_sri: "",
      })
    );
    const token = await makeToken(1, "cliente");
    const clave = buildValidClave();

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 1,
          comercio_id: 1,
          clave_acceso_49: clave,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "true" }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { factura_id: number; estado: string };
    expect(body.estado).toBe("pendiente_revision_nombre");

    const row = await db
      .prepare("SELECT motivo_rechazo FROM facturas WHERE id = ?")
      .bind(body.factura_id)
      .first<{ motivo_rechazo: string | null }>();
    expect(row?.motivo_rechazo).toContain("no coincide");
  });
});

describe("Antifraude - Factura pendiente no genera beneficios", () => {
  it("factura nivel 2 con estado pendiente_revision_nombre no tiene descuento_aplicado", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 2,
          comercio_id: 1,
          numero_factura: "001-001-6000001",
          monto_total: 50.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { factura_id: number; estado: string };
    expect(body.estado).toBe("pendiente_revision_nombre");

    const row = await db
      .prepare("SELECT descuento_aplicado FROM facturas WHERE id = ?")
      .bind(body.factura_id)
      .first<{ descuento_aplicado: number | null }>();
    expect(row?.descuento_aplicado).toBeNull();
  });

  it("factura nivel 3 con estado pendiente_revision_nombre no tiene descuento_aplicado", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    const challengeRes = await app.request(
      "/facturas/challenge",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );
    const challengeBody = (await challengeRes.json()) as { nonce: string };

    const res = await app.request(
      "/facturas/registrar",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          nivel_verificacion: 3,
          comercio_id: 1,
          challenge_nonce: challengeBody.nonce,
          monto_total: 30.00,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { factura_id: number; estado: string };
    expect(body.estado).toBe("pendiente_revision_nombre");

    const row = await db
      .prepare("SELECT descuento_aplicado FROM facturas WHERE id = ?")
      .bind(body.factura_id)
      .first<{ descuento_aplicado: number | null }>();
    expect(row?.descuento_aplicado).toBeNull();
  });
});
