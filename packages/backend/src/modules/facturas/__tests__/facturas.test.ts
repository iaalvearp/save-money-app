import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";

const db = env.DB;

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
    .bind("cliente", "test-facturas@example.com", "hash", "Test User")
    .run();
});

const VALID_ESTADOS = [
  "aprobada",
  "pendiente_revision_nombre",
  "pendiente_verificacion_sri",
  "rechazada",
];

describe("facturas - CHECK constraint de estado", () => {
  for (const estado of VALID_ESTADOS) {
    it(`acepta estado "${estado}"`, async () => {
      const result = await db
        .prepare(
          `INSERT INTO facturas
            (cliente_id, nivel_verificacion, estado)
           VALUES (?, ?, ?)`
        )
        .bind(1, 2, estado)
        .run();

      expect(result.success).toBe(true);

      const row = await db
        .prepare("SELECT estado FROM facturas WHERE id = ?")
        .bind(result.meta.last_row_id)
        .first<{ estado: string }>();

      expect(row?.estado).toBe(estado);
    });
  }

  it("rechaza un estado inválido", async () => {
    await expect(
      db
        .prepare(
          `INSERT INTO facturas
            (cliente_id, nivel_verificacion, estado)
           VALUES (?, ?, ?)`
        )
        .bind(1, 2, "estado_inventado")
        .run()
    ).rejects.toThrow(/CHECK constraint failed/);
  });
});

describe("facturas - motivo_rechazo", () => {
  it("motivo_rechazo es null cuando estado es aprobada", async () => {
    const result = await db
      .prepare(
        `INSERT INTO facturas
          (cliente_id, nivel_verificacion, estado, motivo_rechazo)
         VALUES (?, ?, ?, ?)`
      )
      .bind(1, 2, "aprobada", null)
      .run();

    const row = await db
      .prepare("SELECT motivo_rechazo FROM facturas WHERE id = ?")
      .bind(result.meta.last_row_id)
      .first<{ motivo_rechazo: string | null }>();

    expect(row?.motivo_rechazo).toBeNull();
  });

  it("motivo_rechazo tiene texto cuando estado es pendiente_verificacion_sri", async () => {
    const result = await db
      .prepare(
        `INSERT INTO facturas
          (cliente_id, nivel_verificacion, estado, motivo_rechazo)
         VALUES (?, ?, ?, ?)`
      )
      .bind(1, 2, "pendiente_verificacion_sri", "SRI no disponible")
      .run();

    const row = await db
      .prepare("SELECT motivo_rechazo FROM facturas WHERE id = ?")
      .bind(result.meta.last_row_id)
      .first<{ motivo_rechazo: string | null }>();

    expect(row?.motivo_rechazo).toBe("SRI no disponible");
  });

  it("motivo_rechazo tiene texto cuando estado es pendiente_revision_nombre", async () => {
    const result = await db
      .prepare(
        `INSERT INTO facturas
          (cliente_id, nivel_verificacion, estado, motivo_rechazo)
         VALUES (?, ?, ?, ?)`
      )
      .bind(
        1,
        2,
        "pendiente_revision_nombre",
        "Nombre en factura no coincide con el nombre del usuario"
      )
      .run();

    const row = await db
      .prepare("SELECT motivo_rechazo FROM facturas WHERE id = ?")
      .bind(result.meta.last_row_id)
      .first<{ motivo_rechazo: string | null }>();

    expect(row?.motivo_rechazo).toBe(
      "Nombre en factura no coincide con el nombre del usuario"
    );
  });

  it("motivo_rechazo es null por defecto cuando se omite en INSERT", async () => {
    const result = await db
      .prepare(
        `INSERT INTO facturas
          (cliente_id, nivel_verificacion, estado)
         VALUES (?, ?, ?)`
      )
      .bind(1, 2, "aprobada")
      .run();

    const row = await db
      .prepare("SELECT motivo_rechazo FROM facturas WHERE id = ?")
      .bind(result.meta.last_row_id)
      .first<{ motivo_rechazo: string | null }>();

    expect(row?.motivo_rechazo).toBeNull();
  });
});
