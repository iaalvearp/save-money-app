import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { createFacturas } from "../../../modules/facturas/index";
import type { SRIResultado } from "../../../modules/sri/index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-facturas-ocr";

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
    .bind("cliente", "test-ocr@example.com", "hash", "Test User")
    .run();
});

describe("POST /facturas/registrar - nivel 2 OCR", () => {
  it("nivel 2 crea fila con estado pendiente_revision_nombre", async () => {
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
          numero_factura: "001-001-0000123",
          ruc_emisor: "0999999999999",
          nombre_comprador_factura: "Test User",
          fecha_factura: "2026-09-15",
          monto_total: 25.50,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { factura_id: number; estado: string };
    expect(body.estado).toBe("pendiente_revision_nombre");

    const row = await db
      .prepare(
        `SELECT estado, motivo_rechazo, numero_factura, ruc_emisor,
                nombre_comprador_factura, fecha_factura, monto_total
         FROM facturas WHERE id = ?`
      )
      .bind(body.factura_id)
      .first<{
        estado: string;
        motivo_rechazo: string | null;
        numero_factura: string | null;
        ruc_emisor: string | null;
        nombre_comprador_factura: string | null;
        fecha_factura: string | null;
        monto_total: number | null;
      }>();

    expect(row).not.toBeNull();
    expect(row?.estado).toBe("pendiente_revision_nombre");
    expect(row?.motivo_rechazo).toBe(
      "Comprobante verificado por OCR, pendiente validación"
    );
    expect(row?.numero_factura).toBe("001-001-0000123");
    expect(row?.ruc_emisor).toBe("0999999999999");
    expect(row?.nombre_comprador_factura).toBe("Test User");
    expect(row?.fecha_factura).toBe("2026-09-15");
    expect(row?.monto_total).toBe(25.5);
  });

  it("nivel 3 con challenge válido crea fila con estado pendiente_revision_nombre", async () => {
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

    const row = await db
      .prepare("SELECT estado, motivo_rechazo FROM facturas WHERE id = ?")
      .bind(body.factura_id)
      .first<{ estado: string; motivo_rechazo: string | null }>();

    expect(row?.estado).toBe("pendiente_revision_nombre");
    expect(row?.motivo_rechazo).toContain("sin comprobante");
  });

  it("nivel 2 con campos mínimos acepta valores nulos", async () => {
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
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "false" }
    );

    expect(res.status).toBe(201);
    const body = (await res.json()) as { factura_id: number; estado: string };
    expect(body.estado).toBe("pendiente_revision_nombre");

    const row = await db
      .prepare(
        `SELECT numero_factura, ruc_emisor, nombre_comprador_factura,
                fecha_factura, monto_total
         FROM facturas WHERE id = ?`
      )
      .bind(body.factura_id)
      .first<{
        numero_factura: string | null;
        ruc_emisor: string | null;
        nombre_comprador_factura: string | null;
        fecha_factura: string | null;
        monto_total: number | null;
      }>();

    expect(row?.numero_factura).toBeNull();
    expect(row?.ruc_emisor).toBeNull();
    expect(row?.nombre_comprador_factura).toBeNull();
    expect(row?.fecha_factura).toBeNull();
    expect(row?.monto_total).toBeNull();
  });
});
