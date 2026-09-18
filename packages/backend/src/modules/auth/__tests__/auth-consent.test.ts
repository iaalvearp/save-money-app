import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-auth-consent";

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/auth", auth);
  return app;
}

async function makeToken(sub: number, rol: string): Promise<string> {
  return sign(
    { sub: String(sub), rol, exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
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
        horario_apertura TEXT,
        horario_cierre TEXT,
        foto_url TEXT,
        latitud REAL,
        longitud REAL
      )`
    )
    .run();
});

describe("Registro: consentimiento publicitario", () => {
  it("registro sin consentimiento: consentimiento_publicidad es null", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "sinconsent@test.com",
          password: "123456",
          nombre_completo: "Sin Consent",
          rol: "cliente",
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const row = await db
      .prepare(
        "SELECT consentimiento_publicidad, consentimiento_publicidad_fecha FROM usuarios WHERE email = ?"
      )
      .bind("sinconsent@test.com")
      .first<{
        consentimiento_publicidad: number | null;
        consentimiento_publicidad_fecha: string | null;
      }>();
    expect(row?.consentimiento_publicidad).toBeNull();
    expect(row?.consentimiento_publicidad_fecha).toBeNull();
  });

  it("registro con consentimiento y fecha de nacimiento válida (mayor 18)", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "adulto@test.com",
          password: "123456",
          nombre_completo: "Adulto Test",
          rol: "cliente",
          fecha_nacimiento: "1990-05-15",
          consentimiento_publicidad: true,
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const row = await db
      .prepare(
        "SELECT consentimiento_publicidad, consentimiento_publicidad_fecha FROM usuarios WHERE email = ?"
      )
      .bind("adulto@test.com")
      .first<{
        consentimiento_publicidad: number | null;
        consentimiento_publicidad_fecha: string | null;
      }>();
    expect(row?.consentimiento_publicidad).toBe(1);
    expect(row?.consentimiento_publicidad_fecha).not.toBeNull();
  });

  it("registro con consentimiento sin fecha de nacimiento: error 422", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "nofecha@test.com",
          password: "123456",
          nombre_completo: "No Fecha",
          rol: "cliente",
          consentimiento_publicidad: true,
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("Fecha de nacimiento requerida");
  });

  it("registro con consentimiento siendo menor de edad: error 422", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "menor@test.com",
          password: "123456",
          nombre_completo: "Menor Test",
          rol: "cliente",
          fecha_nacimiento: "2015-03-20",
          consentimiento_publicidad: true,
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("mayor de 18 años");
  });

  it("registro con consentimiento false: consentimiento_publicidad es null", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "consentfalse@test.com",
          password: "123456",
          nombre_completo: "Consent False",
          rol: "cliente",
          consentimiento_publicidad: false,
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const row = await db
      .prepare(
        "SELECT consentimiento_publicidad FROM usuarios WHERE email = ?"
      )
      .bind("consentfalse@test.com")
      .first<{ consentimiento_publicidad: number | null }>();
    expect(row?.consentimiento_publicidad).toBeNull();
  });
});

describe("PATCH /auth/consentimiento", () => {
  let userId: number;

  beforeAll(async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "consent-manage@test.com",
          password: "123456",
          nombre_completo: "Consent Manage",
          rol: "cliente",
          fecha_nacimiento: "1985-08-10",
        }),
      },
      { DB: db, JWT_SECRET }
    );
    const body = (await res.json()) as { user: { id: number } };
    userId = body.user.id;
  });

  it("activar consentimiento con cuenta adulta", async () => {
    const app = buildApp();
    const token = await makeToken(userId, "cliente");
    const res = await app.request(
      "/auth/consentimiento",
      {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ consentimiento_publicidad: true }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      consentimiento_publicidad: boolean;
      consentimiento_publicidad_fecha: string | null;
    };
    expect(body.consentimiento_publicidad).toBe(true);
    expect(body.consentimiento_publicidad_fecha).not.toBeNull();
  });

  it("revocar consentimiento", async () => {
    const app = buildApp();
    const token = await makeToken(userId, "cliente");
    const res = await app.request(
      "/auth/consentimiento",
      {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ consentimiento_publicidad: false }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      consentimiento_publicidad: boolean;
      consentimiento_publicidad_fecha: string | null;
    };
    expect(body.consentimiento_publicidad).toBe(false);
    expect(body.consentimiento_publicidad_fecha).toBeNull();
  });

  it("sin token: error 401", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/consentimiento",
      {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ consentimiento_publicidad: true }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(401);
  });
});

describe("Menor de edad: bloqueo publicitario", () => {
  it("registro de menor sin consentimiento: permitido", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "menor-sin-con@test.com",
          password: "123456",
          nombre_completo: "Menor Sin Consent",
          rol: "cliente",
          fecha_nacimiento: "2012-01-01",
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
    const row = await db
      .prepare(
        "SELECT consentimiento_publicidad FROM usuarios WHERE email = ?"
      )
      .bind("menor-sin-con@test.com")
      .first<{ consentimiento_publicidad: number | null }>();
    expect(row?.consentimiento_publicidad).toBeNull();
  });

  it("adulto que intenta consentimiento sin fecha: error 422", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: "adulto-sin-fecha@test.com",
          password: "123456",
          nombre_completo: "Adulto Sin Fecha",
          rol: "cliente",
          consentimiento_publicidad: true,
        }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
  });
});
