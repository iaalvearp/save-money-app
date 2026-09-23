import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-auth-roundtrip";

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/auth", auth);
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
});

describe("Round-trip registro -> login (sin mocks)", () => {
  it("registra con contraseña conocida y hace login con esa misma contraseña", async () => {
    const app = buildApp();
    const email = "roundtrip-ok@test.com";
    const password = "Contraseña-Secreta-123";

    const regRes = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          password,
          nombre_completo: "Round Trip Ok",
          rol: "cliente",
        }),
      },
      { DB: db, JWT_SECRET }
    );
    expect(regRes.status).toBe(201);

    const loginRes = await app.request(
      "/auth/login",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      },
      { DB: db, JWT_SECRET }
    );
    expect(loginRes.status).toBe(200);
    const body = (await loginRes.json()) as {
      user: { email: string };
      access_token: string;
      refresh_token: string;
    };
    expect(body.user.email).toBe(email);
    expect(body.access_token).toBeTruthy();
    expect(body.refresh_token).toBeTruthy();
  });

  it("login con contraseña incorrecta falla con 401", async () => {
    const app = buildApp();
    const email = "roundtrip-fail@test.com";
    const password = "Contraseña-Correcta-456";

    const regRes = await app.request(
      "/auth/registro",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          password,
          nombre_completo: "Round Trip Fail",
          rol: "cliente",
        }),
      },
      { DB: db, JWT_SECRET }
    );
    expect(regRes.status).toBe(201);

    const loginRes = await app.request(
      "/auth/login",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password: "Contraseña-Incorrecta-999" }),
      },
      { DB: db, JWT_SECRET }
    );
    expect(loginRes.status).toBe(401);

    const row = await db
      .prepare(
        "SELECT password_hash FROM usuarios WHERE email = ?"
      )
      .bind(email)
      .first<{ password_hash: string }>();
    expect(row?.password_hash.startsWith("pbkdf2:")).toBe(true);
  });
});