import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { createFacturas } from "../../../modules/facturas/index";
import type { SRIResultado } from "../../../modules/sri/index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-sri-retry";

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

function makePendingRow(clave: string, clienteId: number) {
  return db
    .prepare(
      `INSERT INTO facturas
        (cliente_id, nivel_verificacion, clave_acceso_49, estado, motivo_rechazo)
       VALUES (?, 1, ?, 'pendiente_verificacion_sri', 'SRI no disponible')`
    )
    .bind(clienteId, clave)
    .run();
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
    .bind("cliente", "test-retry@example.com", "hash", "Test User")
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
       VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "other-user@example.com", "hash", "Other User")
    .run();
});

function buildPendingFactura(clave: string, clienteId: number) {
  return db
    .prepare(
      `INSERT INTO facturas
        (cliente_id, nivel_verificacion, clave_acceso_49, estado, motivo_rechazo)
       VALUES (?, 1, ?, 'pendiente_verificacion_sri', 'SRI no disponible')`
    )
    .bind(clienteId, clave);
}

describe("POST /facturas/registrar - reintento SRI pendiente", () => {
  it("reintento del mismo usuario sobre factura pendiente devuelve 200 con estado pendiente", async () => {
    const clave = buildValidClave();

    const app = buildApp(
      () => true,
      async () => ({
        estado: "servicio_no_disponible",
        ruc_emisor: null,
        nombre_comprador: null,
        fecha_autorizacion: null,
        monto: null,
        mensaje_sri: null,
      })
    );
    const token = await makeToken(1, "cliente");

    await buildPendingFactura(clave, 1).run();

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

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      factura_id: number;
      estado: string;
      mensaje: string;
    };
    expect(body.estado).toBe("pendiente_verificacion_sri");
    expect(body.mensaje).toContain("reintentar");
  });

  it("SRI autoriza en reintento: misma fila pasa a aprobada", async () => {
    const clave = buildValidClave();

    const app = buildApp(
      () => true,
      async () => ({
        estado: "autorizado",
        ruc_emisor: "1792000000001",
        nombre_comprador: "Test User",
        fecha_autorizacion: "2026-09-15",
        monto: 42.5,
        mensaje_sri: null,
      })
    );
    const token = await makeToken(1, "cliente");

    await buildPendingFactura(clave, 1).run();

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

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      factura_id: number;
      estado: string;
      motivo_rechazo: string | null;
      sri_estado: string;
    };
    expect(body.estado).toBe("aprobada");
    expect(body.motivo_rechazo).toBeNull();
    expect(body.sri_estado).toBe("autorizado");

    const row = await db
      .prepare(
        "SELECT estado, motivo_rechazo, ruc_emisor, monto_total, sri_estado_bruto FROM facturas WHERE clave_acceso_49 = ?"
      )
      .bind(clave)
      .first<{
        estado: string;
        motivo_rechazo: string | null;
        ruc_emisor: string | null;
        monto_total: number | null;
        sri_estado_bruto: string | null;
      }>();

    expect(row?.estado).toBe("aprobada");
    expect(row?.motivo_rechazo).toBeNull();
    expect(row?.ruc_emisor).toBe("1792000000001");
    expect(row?.monto_total).toBe(42.5);
    expect(row?.sri_estado_bruto).toBe("autorizado");
  });

  it("SRI sigue caído en reintento: misma fila permanece pendiente", async () => {
    const clave = buildValidClave();

    const app = buildApp(
      () => true,
      async () => ({
        estado: "servicio_no_disponible",
        ruc_emisor: null,
        nombre_comprador: null,
        fecha_autorizacion: null,
        monto: null,
        mensaje_sri: null,
      })
    );
    const token = await makeToken(1, "cliente");

    await buildPendingFactura(clave, 1).run();

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

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      factura_id: number;
      estado: string;
      mensaje: string;
    };
    expect(body.estado).toBe("pendiente_verificacion_sri");
    expect(body.mensaje).toContain("reintentar");

    const row = await db
      .prepare("SELECT estado FROM facturas WHERE clave_acceso_49 = ?")
      .bind(clave)
      .first<{ estado: string }>();

    expect(row?.estado).toBe("pendiente_verificacion_sri");
  });

  it("SRI rechaza en reintento: misma fila pasa a rechazada", async () => {
    const clave = buildValidClave();

    const app = buildApp(
      () => true,
      async () => ({
        estado: "rechazada",
        ruc_emisor: "1792000000001",
        nombre_comprador: "Test User",
        fecha_autorizacion: "2026-09-15",
        monto: 15.0,
        mensaje_sri: "Comprobante rechazado",
      })
    );
    const token = await makeToken(1, "cliente");

    await buildPendingFactura(clave, 1).run();

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

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      factura_id: number;
      estado: string;
      motivo_rechazo: string;
      sri_estado: string;
    };
    expect(body.estado).toBe("rechazada");
    expect(body.motivo_rechazo).toBe("SRI respondió: rechazada");
    expect(body.sri_estado).toBe("rechazada");

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

    expect(row?.estado).toBe("rechazada");
    expect(row?.motivo_rechazo).toBe("SRI respondió: rechazada");
    expect(row?.sri_estado_bruto).toBe("rechazada");
  });

  it("SRI no_autorizado en reintento: misma fila pasa a rechazada", async () => {
    const clave = buildValidClave();

    const app = buildApp(
      () => true,
      async () => ({
        estado: "no_autorizado",
        ruc_emisor: "1792000000001",
        nombre_comprador: null,
        fecha_autorizacion: null,
        monto: null,
        mensaje_sri: "Clave no encontrada",
      })
    );
    const token = await makeToken(1, "cliente");

    await buildPendingFactura(clave, 1).run();

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

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      factura_id: number;
      estado: string;
      motivo_rechazo: string;
    };
    expect(body.estado).toBe("rechazada");
    expect(body.motivo_rechazo).toBe("SRI respondió: no_autorizado");
  });

  it("otro usuario intenta la misma clave: conflicto controlado", async () => {
    const clave = buildValidClave();

    const app = buildApp(
      () => true,
      async () => ({
        estado: "autorizado",
        ruc_emisor: "1792000000001",
        nombre_comprador: "Other User",
        fecha_autorizacion: "2026-09-15",
        monto: 10.0,
        mensaje_sri: null,
      })
    );
    const token = await makeToken(2, "cliente");

    await buildPendingFactura(clave, 1).run();

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

    const row = await db
      .prepare("SELECT cliente_id FROM facturas WHERE clave_acceso_49 = ?")
      .bind(clave)
      .first<{ cliente_id: number }>();

    expect(row?.cliente_id).toBe(1);
  });

  it("nunca crea dos filas para una clave pendiente", async () => {
    const clave = buildValidClave();

    const app = buildApp(
      () => true,
      async () => ({
        estado: "servicio_no_disponible",
        ruc_emisor: null,
        nombre_comprador: null,
        fecha_autorizacion: null,
        monto: null,
        mensaje_sri: null,
      })
    );
    const token = await makeToken(1, "cliente");

    await buildPendingFactura(clave, 1).run();

    for (let i = 0; i < 3; i++) {
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
        { DB: db, JWT_SECRET, SRI_ENFORCE_VALIDATION: "true" }
      );
    }

    const rows = await db
      .prepare("SELECT COUNT(*) as count FROM facturas WHERE clave_acceso_49 = ?")
      .bind(clave)
      .first<{ count: number }>();

    expect(rows?.count).toBe(1);
  });

  it("reintento con nombre no coincide: pasa a pendiente_revision_nombre", async () => {
    const clave = buildValidClave();

    const app = buildApp(
      () => true,
      async () => ({
        estado: "autorizado",
        ruc_emisor: "1792000000001",
        nombre_comprador: "Nombre Diferente",
        fecha_autorizacion: "2026-09-15",
        monto: 30.0,
        mensaje_sri: null,
      })
    );
    const token = await makeToken(1, "cliente");

    await buildPendingFactura(clave, 1).run();

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

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      factura_id: number;
      estado: string;
      motivo_rechazo: string | null;
    };
    expect(body.estado).toBe("pendiente_revision_nombre");
    expect(body.motivo_rechazo).toContain("Nombre");

    const row = await db
      .prepare("SELECT estado FROM facturas WHERE clave_acceso_49 = ?")
      .bind(clave)
      .first<{ estado: string }>();

    expect(row?.estado).toBe("pendiente_revision_nombre");
  });
});
