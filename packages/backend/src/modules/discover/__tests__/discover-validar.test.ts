import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { discover } from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-validar-comercio";

/** RUC válidos generados aparte con las reglas del SRI. */
const RUC_NATURAL = "0951234566001";
const RUC_JURIDICA = "0991234561001";
const RUC_PUBLICO = "0961234507001";

const NEGOCIO = 1;

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/discover", discover);
  return app;
}

async function tokenDeNegocio(): Promise<string> {
  return sign(
    { sub: String(NEGOCIO), rol: "negocio", exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
  );
}

async function crearComercio(cuerpo: Record<string, unknown>): Promise<Response> {
  const app = buildApp();
  const token = await tokenDeNegocio();
  return app.request(
    "/discover/comercios",
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify(cuerpo),
    },
    { DB: db, JWT_SECRET }
  );
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
      `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo)
       VALUES (?, 'negocio', 'negocio@validar.test', 'hash', 'Negocio')`
    )
    .bind(NEGOCIO)
    .run();
});

describe("POST /discover/comercios - RUC", () => {
  it.each([RUC_NATURAL, RUC_JURIDICA, RUC_PUBLICO])(
    "acepta el RUC válido %s",
    async (ruc) => {
      const res = await crearComercio({ nombre: "Café", ruc });

      expect(res.status).toBe(201);
      const body = (await res.json()) as { comercio: { ruc: string } };
      expect(body.comercio.ruc).toBe(ruc);
    }
  );

  it("acepta crear el comercio sin RUC", async () => {
    const res = await crearComercio({ nombre: "Café sin RUC" });

    expect(res.status).toBe(201);
  });

  it.each([
    ["095123456600", "13 dígitos"],
    ["09512345660A1", "13 dígitos"],
    ["2551234566001", "provincia"],
    ["0971234561001", "tercer dígito"],
    ["0991234561000", "establecimiento"],
    ["0991234569001", "persona jurídica"],
  ])("rechaza el RUC %s", async (ruc, motivoEsperado) => {
    const res = await crearComercio({ nombre: "Café malo", ruc });

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain(motivoEsperado);
  });

  it("no crea el comercio cuando el RUC es inválido", async () => {
    const antes = await db.prepare("SELECT COUNT(*) AS n FROM comercios").first<{ n: number }>();

    await crearComercio({ nombre: "No debe existir", ruc: "1234567890123" });

    const despues = await db.prepare("SELECT COUNT(*) AS n FROM comercios").first<{ n: number }>();
    expect(despues?.n).toBe(antes?.n);
  });
});

describe("POST /discover/comercios - horario", () => {
  it("acepta un cierre posterior a la apertura", async () => {
    const res = await crearComercio({
      nombre: "Café horario",
      hora_apertura: "08:00",
      hora_cierre: "18:00",
    });

    expect(res.status).toBe(201);
  });

  it("rechaza un cierre anterior a la apertura", async () => {
    const res = await crearComercio({
      nombre: "Café al revés",
      hora_apertura: "18:00",
      hora_cierre: "08:00",
    });

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("posterior");
  });

  it("rechaza un cierre igual a la apertura", async () => {
    const res = await crearComercio({
      nombre: "Café cero horas",
      hora_apertura: "08:00",
      hora_cierre: "08:00",
    });

    expect(res.status).toBe(400);
  });
});

describe("PUT /discover/comercios/:id - RUC y horario", () => {
  /**
   * El pool de tests revierte lo que se escribe dentro de un test, asi que
   * cada caso arma su propio comercio en vez de heredar el del anterior.
   */
  async function comercioNuevo(
    extra: Record<string, unknown> = {}
  ): Promise<number> {
    const res = await crearComercio({ nombre: "Comercio", ...extra });
    const body = (await res.json()) as { comercio: { id: number } };
    return body.comercio.id;
  }

  async function editar(
    id: number,
    cuerpo: Record<string, unknown>
  ): Promise<Response> {
    const app = buildApp();
    const token = await tokenDeNegocio();
    return app.request(
      `/discover/comercios/${id}`,
      {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify(cuerpo),
      },
      { DB: db, JWT_SECRET }
    );
  }

  it("guarda un RUC válido nuevo", async () => {
    const id = await comercioNuevo({ ruc: RUC_JURIDICA });

    const res = await editar(id, { ruc: RUC_NATURAL });

    expect(res.status).toBe(200);
    const body = (await res.json()) as { comercio: { ruc: string } };
    expect(body.comercio.ruc).toBe(RUC_NATURAL);
  });

  it("rechaza un RUC inválido y deja el anterior guardado", async () => {
    const id = await comercioNuevo({ ruc: RUC_JURIDICA });

    const res = await editar(id, { ruc: "2551234566001" });

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("provincia");

    const guardado = await db
      .prepare("SELECT ruc FROM comercios WHERE id = ?")
      .bind(id)
      .first<{ ruc: string }>();
    expect(guardado?.ruc).toBe(RUC_JURIDICA);
  });

  it("compara el cierre nuevo contra la apertura ya guardada", async () => {
    // El comercio abre a las 09:00; se manda solo el cierre, antes de eso.
    const id = await comercioNuevo({ hora_apertura: "09:00", hora_cierre: "17:00" });

    const res = await editar(id, { hora_cierre: "07:00" });

    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("apertura");
  });

  it("acepta cambiar solo el cierre si sigue siendo posterior", async () => {
    const id = await comercioNuevo({ hora_apertura: "09:00", hora_cierre: "17:00" });

    const res = await editar(id, { hora_cierre: "20:00" });

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      comercio: { hora_cierre: string; hora_apertura: string };
    };
    expect(body.comercio.hora_cierre).toBe("20:00");
    expect(body.comercio.hora_apertura).toBe("09:00");
  });

  it("acepta editar el nombre sin mandar RUC ni horario y no toca el RUC", async () => {
    const id = await comercioNuevo({ ruc: RUC_JURIDICA });

    const res = await editar(id, { nombre: "Nombre nuevo" });

    expect(res.status).toBe(200);
    const body = (await res.json()) as { comercio: { nombre: string; ruc: string } };
    expect(body.comercio.nombre).toBe("Nombre nuevo");
    expect(body.comercio.ruc).toBe(RUC_JURIDICA);
  });

  it("no deja editar el comercio de otro negocio", async () => {
    const id = await comercioNuevo({ ruc: RUC_JURIDICA });
    await db
      .prepare(`INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo)
                VALUES (99, 'negocio', 'otro@validar.test', 'hash', 'Otro')`)
      .run();
    const app = buildApp();
    const tokenDeOtro = await sign(
      { sub: "99", rol: "negocio", exp: Math.floor(Date.now() / 1000) + 3600 },
      JWT_SECRET
    );

    const res = await app.request(
      `/discover/comercios/${id}`,
      {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${tokenDeOtro}` },
        body: JSON.stringify({ ruc: RUC_NATURAL }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(403);
  });
});
