import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { discover } from "../index";

const db = env.DB;

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/discover", discover);
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
        hora_apertura TEXT,
        hora_cierre TEXT,
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
        descuento REAL,
        expira_en TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
       VALUES (?, ?, ?, ?)`
    )
    .bind("negocio", "negocio1@test.com", "hash", "Dueño 1")
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo)
       VALUES (?, ?, ?, ?)`
    )
    .bind("negocio", "negocio2@test.com", "hash", "Dueño 2")
    .run();

  // Quito -0.18 (cercano a centro Quito: -0.18, -78.47)
  await db
    .prepare(
      `INSERT INTO comercios (usuario_id, nombre, categoria, latitud, longitud, es_patrocinado, horario)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    )
    .bind(1, "Café Central", "Gastronomía", -0.1807, -78.4678, 0, "08:00-20:00")
    .run();

  // Quito -0.31 (lejos del centro: ~15km)
  await db
    .prepare(
      `INSERT INTO comercios (usuario_id, nombre, categoria, latitud, longitud, es_patrocinado, horario)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    )
    .bind(1, "Tienda Norte", "Retail", -0.3100, -78.4600, 1, "09:00-18:00")
    .run();

  // Sin ubicación
  await db
    .prepare(
      `INSERT INTO comercios (usuario_id, nombre, categoria, latitud, longitud, es_patrocinado)
       VALUES (?, ?, ?, ?, ?, ?)`
    )
    .bind(2, "Comercio Sin GPS", "Servicios", null, null, 0)
    .run();

  // Cupón activo para Café Central
  await db
    .prepare(
      `INSERT INTO cupones (comercio_id, codigo_qr, estado, descuento, expira_en)
       VALUES (?, ?, 'activo', ?, datetime('now', '+30 days'))`
    )
    .bind(1, "QR-CAFE-001", 10.0)
    .run();

  // Cupón expirado
  await db
    .prepare(
      `INSERT INTO cupones (comercio_id, codigo_qr, estado, descuento, expira_en)
       VALUES (?, ?, 'expirado', ?, datetime('now', '-5 days'))`
    )
    .bind(2, "QR-TIENDA-001", 5.0)
    .run();
});

describe("GET /discover/comercios - búsqueda por texto", () => {
  it("sin resultados para término inexistente", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios?q=xyz123nonexistent",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { comercios: unknown[] };
    expect(body.comercios).toHaveLength(0);
  });

  it("encuentra por nombre parcial", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios?q=Café",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { comercios: { nombre: string }[] };
    expect(body.comercios.length).toBeGreaterThanOrEqual(1);
    expect(body.comercios.some((c) => c.nombre === "Café Central")).toBe(true);
  });

  it("encuentra por categoría", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios?q=Retail",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { comercios: { nombre: string }[] };
    expect(body.comercios.some((c) => c.nombre === "Tienda Norte")).toBe(true);
  });
});

describe("GET /discover/comercios - filtro por categoría", () => {
  it("filtra por categoría existente", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios?categoria=Gastronomía",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { comercios: { categoria: string }[] };
    expect(body.comercios.length).toBeGreaterThanOrEqual(1);
    expect(
      body.comercios.every((c) => c.categoria === "Gastronomía")
    ).toBe(true);
  });

  it("retorna vacío para categoría inexistente", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios?categoria=CategoríaFicticia",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { comercios: unknown[] };
    expect(body.comercios).toHaveLength(0);
  });
});

describe("GET /discover/comercios - filtro por promociones activas", () => {
  it("solo comercios con cupones activos", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios?con_promociones=true",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { comercios: { nombre: string }[] };
    expect(body.comercios.length).toBeGreaterThanOrEqual(1);
    expect(
      body.comercios.some((c) => c.nombre === "Café Central")
    ).toBe(true);
    expect(
      body.comercios.some((c) => c.nombre === "Tienda Norte")
    ).toBe(false);
  });
});

describe("GET /discover/comercios/cercanos", () => {
  it("sin parámetros lat/lng: error 400", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios/cercanos",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("lat");
  });

  it("retorna comercios dentro del radio", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios/cercanos?lat=-0.18&lng=-78.47&radio=1",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      comercios: { nombre: string; distancia_km: number }[];
    };
    expect(body.comercios.length).toBeGreaterThanOrEqual(1);
    expect(body.comercios[0].distancia_km).toBeLessThan(1);
  });

  it("excluye comercios fuera del radio", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios/cercanos?lat=-0.18&lng=-78.47&radio=1",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      comercios: { nombre: string; distancia_km: number }[];
    };
    expect(
      body.comercios.every((c) => c.distancia_km <= 1)
    ).toBe(true);
  });

  it("excluye comercios sin ubicación", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios/cercanos?lat=-0.18&lng=-78.47&radio=50",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      comercios: { nombre: string }[];
    };
    expect(
      body.comercios.some((c) => c.nombre === "Comercio Sin GPS")
    ).toBe(false);
  });
});

describe("GET /discover/comercios/:id - detalle con promociones", () => {
  it("retorna comercio con cupones activos", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios/1",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      comercio: { nombre: string };
      promociones: { codigo_qr: string; descuento: number }[];
    };
    expect(body.comercio.nombre).toBe("Café Central");
    expect(body.promociones.length).toBeGreaterThanOrEqual(1);
    expect(body.promociones[0].descuento).toBe(10.0);
  });

  it("comercio inexistente: 404", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios/9999",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(404);
  });

  it("comercio sin promociones activas: lista vacía", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios/3",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as { promociones: unknown[] };
    expect(body.promociones).toHaveLength(0);
  });
});

describe("GET /discover/comercios - patrocinado ordering", () => {
  it("patrocinados aparecen primero", async () => {
    const app = buildApp();
    const res = await app.request(
      "/discover/comercios",
      {},
      { DB: db, JWT_SECRET: "test" }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      comercios: { nombre: string; es_patrocinado: number }[];
    };
    const patrocinadoIndex = body.comercios.findIndex(
      (c) => c.es_patrocinado === 1
    );
    const noPatrocinadoIndex = body.comercios.findIndex(
      (c) => c.es_patrocinado === 0
    );
    if (patrocinadoIndex >= 0 && noPatrocinadoIndex >= 0) {
      expect(patrocinadoIndex).toBeLessThan(noPatrocinadoIndex);
    }
  });
});
