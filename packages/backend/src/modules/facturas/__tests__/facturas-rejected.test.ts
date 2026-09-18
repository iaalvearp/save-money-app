import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { createFacturas } from "../../../modules/facturas/index";
import type { SRIResultado } from "../../../modules/sri/index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-facturas-rejected";

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
  validarChecksumFn: (clave: string) => boolean,
  consultarSRIFn: (clave: string) => Promise<SRIResultado>
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
        sri_estado_bruto TEXT
      )`
    )
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
       VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "test-rejected@example.com", "hash", "Test User")
    .run();
});

describe("POST /facturas/registrar - persistencia de rechazos", () => {
  it("checksum inválido crea fila rechazada y devuelve error 400", async () => {
    const app = buildApp(
      () => false,
      async () => ({
        estado: "autorizado",
        ruc_emisor: "0000000000000",
        nombre_comprador: "Test User",
        fecha_autorizacion: "2026-01-01",
        monto: 10.0,
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

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string; detalle?: string };
    expect(body.error).toContain("dígito verificador inválido");

    const row = await db
      .prepare(
        "SELECT estado, motivo_rechazo, clave_acceso_49 FROM facturas WHERE clave_acceso_49 = ?"
      )
      .bind(clave)
      .first<{
        estado: string;
        motivo_rechazo: string | null;
        clave_acceso_49: string;
      }>();

    expect(row).not.toBeNull();
    expect(row?.estado).toBe("rechazada");
    expect(row?.motivo_rechazo).toBe("Checksum inválido en clave de acceso");
    expect(row?.clave_acceso_49).toBe(clave);
  });

  it("SRI rechazada crea fila rechazada y devuelve error 422", async () => {
    const app = buildApp(
      () => true,
      async () => ({
        estado: "rechazada",
        ruc_emisor: "0000000000000",
        nombre_comprador: "Test User",
        fecha_autorizacion: "2026-01-01",
        monto: 25.5,
        mensaje_sri: "Comprobante no válido",
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

    expect(res.status).toBe(422);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("rechazada");

    const row = await db
      .prepare(
        "SELECT estado, motivo_rechazo, sri_estado_bruto FROM facturas WHERE clave_acceso_49 = ?"
      )
      .bind(clave)
      .first<{
        estado: string;
        motivo_rechazo: string | null;
        sri_estado_bruto: string | null;
      }>();

    expect(row).not.toBeNull();
    expect(row?.estado).toBe("rechazada");
    expect(row?.motivo_rechazo).toBe("SRI respondió: rechazada");
    expect(row?.sri_estado_bruto).toBe("rechazada");
  });

  it("SRI no_autorizado crea fila rechazada y devuelve error 422", async () => {
    const app = buildApp(
      () => true,
      async () => ({
        estado: "no_autorizado",
        ruc_emisor: "0000000000000",
        nombre_comprador: "Test User",
        fecha_autorizacion: "2026-01-01",
        monto: 5.0,
        mensaje_sri: "Clave de acceso no encontrada",
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

    expect(res.status).toBe(422);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("no_autorizado");

    const row = await db
      .prepare(
        "SELECT estado, motivo_rechazo, sri_estado_bruto FROM facturas WHERE clave_acceso_49 = ?"
      )
      .bind(clave)
      .first<{
        estado: string;
        motivo_rechazo: string | null;
        sri_estado_bruto: string | null;
      }>();

    expect(row).not.toBeNull();
    expect(row?.estado).toBe("rechazada");
    expect(row?.motivo_rechazo).toBe("SRI respondió: no_autorizado");
    expect(row?.sri_estado_bruto).toBe("no_autorizado");
  });

  it("reintentar misma clave_acceso_49 devuelve 409 con mensaje claro", async () => {
    const app = buildApp(
      () => true,
      async () => ({
        estado: "rechazada",
        ruc_emisor: "0000000000000",
        nombre_comprador: "Test User",
        fecha_autorizacion: "2026-01-01",
        monto: 10.0,
        mensaje_sri: "",
      })
    );
    const token = await makeToken(1, "cliente");
    const clave = buildValidClave();

    await db
      .prepare(
        `INSERT INTO facturas
          (cliente_id, nivel_verificacion, clave_acceso_49, estado, motivo_rechazo)
         VALUES (?, ?, ?, 'rechazada', 'previo')`
      )
      .bind(1, 1, clave)
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
          nivel_verificacion: 1,
          comercio_id: 1,
          clave_acceso_49: clave,
        }),
      },
      { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "true" }
    );

    expect(res.status).toBe(409);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("intentada anteriormente");
  });
});
