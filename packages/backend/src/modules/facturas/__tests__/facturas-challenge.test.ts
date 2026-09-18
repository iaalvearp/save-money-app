import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { createFacturas } from "../../../modules/facturas/index";
import type { SRIResultado } from "../../../modules/sri/index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-facturas-challenge";

async function makeToken(sub: number, rol: string): Promise<string> {
  return sign(
    { sub: String(sub), rol, exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
  );
}

function buildApp() {
  const facturas = createFacturas(
    () => true,
    async () => ({
      estado: "autorizado",
      ruc_emisor: "",
      nombre_comprador: "",
      fecha_autorizacion: "",
      monto: 0,
      mensaje_sri: "",
    })
  );
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
    .bind("cliente", "test-challenge@example.com", "hash", "Test User")
    .run();
});

describe("POST /facturas/challenge", () => {
  it("crea un desafío con nonce y expiración", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    const res = await app.request(
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

    expect(res.status).toBe(201);
    const body = (await res.json()) as { nonce: string; expira_en: string };
    expect(body.nonce).toMatch(/^[0-9a-f]{64}$/);
    expect(body.expira_en).toBeTruthy();

    const expira = new Date(body.expira_en);
    const now = new Date();
    const diffMs = expira.getTime() - now.getTime();
    expect(diffMs).toBeGreaterThan(4 * 60 * 1000);
    expect(diffMs).toBeLessThanOrEqual(5 * 60 * 1000 + 1000);
  });
});

describe("POST /facturas/registrar - nivel 3 challenge-response", () => {
  it("nivel 3 sin challenge_nonce devuelve error 400", async () => {
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
          nivel_verificacion: 3,
          comercio_id: 1,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("challenge_nonce");
  });

  it("nivel 3 con nonce inválido devuelve error 400", async () => {
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
          nivel_verificacion: 3,
          comercio_id: 1,
          challenge_nonce: "nonce_inexistente",
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("inválido");
  });

  it("nivel 3 con nonce ya usado devuelve error 409", async () => {
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

    await app.request(
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
          nivel_verificacion: 3,
          comercio_id: 1,
          challenge_nonce: challengeBody.nonce,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(409);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("utilizado");
  });

  it("nivel 3 con nonce válido crea factura pendiente", async () => {
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
          claim_hash: "abc123hash",
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as {
      factura_id: number;
      estado: string;
      motivo_rechazo: string;
    };
    expect(body.estado).toBe("pendiente_revision_nombre");
    expect(body.motivo_rechazo).toContain("sin comprobante");

    const row = await db
      .prepare(
        `SELECT estado, motivo_rechazo, challenge_nonce, claim_hash
         FROM facturas WHERE id = ?`
      )
      .bind(body.factura_id)
      .first<{
        estado: string;
        motivo_rechazo: string | null;
        challenge_nonce: string | null;
        claim_hash: string | null;
      }>();

    expect(row?.estado).toBe("pendiente_revision_nombre");
    expect(row?.challenge_nonce).toBe(challengeBody.nonce);
    expect(row?.claim_hash).toBe("abc123hash");

    const challengeRow = await db
      .prepare("SELECT usado FROM challenges WHERE nonce = ?")
      .bind(challengeBody.nonce)
      .first<{ usado: number }>();
    expect(challengeRow?.usado).toBe(1);
  });

  it("nivel 3 con nonce expirado devuelve error 410", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    const expiraEn = new Date(Date.now() - 1000).toISOString();
    await db
      .prepare(
        `INSERT INTO challenges (cliente_id, nonce, expira_en, usado)
         VALUES (?, ?, ?, 0)`
      )
      .bind(1, "expired_nonce_123", expiraEn)
      .run();

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
          challenge_nonce: "expired_nonce_123",
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(410);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("expirado");
  });

  it("nivel 3 con claim_hash nulo es aceptado", async () => {
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
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { factura_id: number; estado: string };
    expect(body.estado).toBe("pendiente_revision_nombre");
  });
});
