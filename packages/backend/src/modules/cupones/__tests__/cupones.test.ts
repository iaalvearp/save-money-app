import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { emitirCupon, listarCuponesDeUsuario, canjearCupon } from "../index";

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
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("negocio", "neg@test.com", "hash", "Neg Test")
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "cli@test.com", "hash", "Cli Test")
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "cli2@test.com", "hash", "Cli 2 Test")
    .run();

  await db
    .prepare(
      `INSERT INTO comercios (usuario_id, nombre, categoria) VALUES (?, ?, ?)`
    )
    .bind(1, "Cafe Cupones", "Gastronomia")
    .run();
});

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

describe("emitirCupon", () => {
  it("emite cupon flash con codigo_qr y tipo correcto", async () => {
    const result = await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 2,
      descuento: 20,
      expiraEn: futureDate(30),
      tipo: "flash",
      emitidoPor: 2,
    });

    expect(result.id).toBeDefined();
    expect(result.codigo_qr).toMatch(/^FLASH-[A-Z0-9]{12}$/);

    const row = await db
      .prepare("SELECT * FROM cupones WHERE id = ?")
      .bind(result.id)
      .first<{
        estado: string;
        tipo: string;
        descuento: number;
        comercio_id: number;
        cliente_id: number;
      }>();
    expect(row?.estado).toBe("activo");
    expect(row?.tipo).toBe("flash");
    expect(row?.descuento).toBe(20);
    expect(row?.comercio_id).toBe(1);
    expect(row?.cliente_id).toBe(2);
  });

  it("emite cupon hunt con prefijo HUNT", async () => {
    const result = await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 2,
      descuento: 15,
      expiraEn: futureDate(7),
      tipo: "hunt",
    });

    expect(result.codigo_qr).toMatch(/^HUNT-[A-Z0-9]{12}$/);

    const row = await db
      .prepare("SELECT tipo FROM cupones WHERE id = ?")
      .bind(result.id)
      .first<{ tipo: string }>();
    expect(row?.tipo).toBe("hunt");
  });
});

describe("listarCuponesDeUsuario", () => {
  it("retorna cupones del usuario con info del comercio", async () => {
    await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 2,
      descuento: 10,
      expiraEn: futureDate(30),
      tipo: "flash",
    });

    const cupones = await listarCuponesDeUsuario(db, 2);
    expect(cupones.length).toBeGreaterThanOrEqual(1);
    expect(cupones[0].comercio_nombre).toBe("Cafe Cupones");
  });

  it("expira cupones vencidos automaticamente", async () => {
    await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 3,
      descuento: 5,
      expiraEn: pastDate(1),
      tipo: "flash",
    });

    const cupones = await listarCuponesDeUsuario(db, 3);
    const expirados = cupones.filter((c) => c.estado === "expirado");
    expect(expirados.length).toBeGreaterThanOrEqual(1);
  });

  it("no retorna cupones de otro usuario", async () => {
    const cupones = await listarCuponesDeUsuario(db, 999);
    expect(cupones.length).toBe(0);
  });
});

describe("canjearCupon", () => {
  it("canjea cupon activo exitosamente", async () => {
    const { id } = await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 2,
      descuento: 25,
      expiraEn: futureDate(30),
      tipo: "flash",
    });

    const result = await canjearCupon(db, id, 1);
    expect(result.ok).toBe(true);

    const row = await db
      .prepare("SELECT estado, canjeado_en FROM cupones WHERE id = ?")
      .bind(id)
      .first<{ estado: string; canjeado_en: string | null }>();
    expect(row?.estado).toBe("utilizado");
    expect(row?.canjeado_en).toBeTruthy();
  });

  it("rechaza cupon inexistente", async () => {
    const result = await canjearCupon(db, 99999, 1);
    expect(result.ok).toBe(false);
    expect(result.error).toContain("no encontrado");
  });

  it("rechaza canje con comercio incorrecto", async () => {
    const { id } = await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 2,
      descuento: 10,
      expiraEn: futureDate(30),
      tipo: "flash",
    });

    const result = await canjearCupon(db, id, 999);
    expect(result.ok).toBe(false);
    expect(result.error).toContain("no pertenece");
  });

  it("rechaza cupon ya utilizado", async () => {
    const { id } = await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 2,
      descuento: 10,
      expiraEn: futureDate(30),
      tipo: "flash",
    });

    await canjearCupon(db, id, 1);
    const result = await canjearCupon(db, id, 1);
    expect(result.ok).toBe(false);
    expect(result.error).toContain("utilizado");
  });

  it("rechaza cupon expirado", async () => {
    const { id } = await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 2,
      descuento: 10,
      expiraEn: pastDate(1),
      tipo: "flash",
    });

    const result = await canjearCupon(db, id, 1);
    expect(result.ok).toBe(false);
    expect(result.error).toContain("expirado");

    const row = await db
      .prepare("SELECT estado FROM cupones WHERE id = ?")
      .bind(id)
      .first<{ estado: string }>();
    expect(row?.estado).toBe("expirado");
  });

  it("dos canjes simultaneos: exactamente uno tiene exito", async () => {
    const { id } = await emitirCupon({
      db,
      comercioId: 1,
      clienteId: 2,
      descuento: 30,
      expiraEn: futureDate(30),
      tipo: "flash",
    });

    const [r1, r2] = await Promise.all([
      canjearCupon(db, id, 1),
      canjearCupon(db, id, 1),
    ]);

    const successes = [r1, r2].filter((r) => r.ok);
    const failures = [r1, r2].filter((r) => !r.ok);

    expect(successes.length).toBe(1);
    expect(failures.length).toBe(1);

    const row = await db
      .prepare("SELECT estado FROM cupones WHERE id = ?")
      .bind(id)
      .first<{ estado: string }>();
    expect(row?.estado).toBe("utilizado");
  });
});
