import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-fcm-fecha";

const USUARIO = 1;

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/auth", auth);
  return app;
}

async function registrarToken(token: string | null): Promise<Response> {
  const app = buildApp();
  const jwt = await sign(
    { sub: String(USUARIO), rol: "cliente", exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
  );
  return app.request(
    "/auth/fcm-token",
    {
      method: "PUT",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${jwt}` },
      body: JSON.stringify({ fcm_token: token }),
    },
    { DB: db, JWT_SECRET }
  );
}

async function leerUsuario() {
  return db
    .prepare("SELECT fcm_token, fcm_token_updated_at FROM usuarios WHERE id = ?")
    .bind(USUARIO)
    .first<{ fcm_token: string | null; fcm_token_updated_at: string | null }>();
}

/** Segundos entre la fecha que guardó la base y ahora, para no depender del reloj. */
function segundosDesde(valor: string | null): number {
  expect(valor, "fcm_token_updated_at debería tener fecha").not.toBeNull();
  const guardado = Date.parse(`${valor!.replace(" ", "T")}Z`);
  expect(Number.isNaN(guardado), `fecha ilegible: ${valor}`).toBe(false);
  return (Date.now() - guardado) / 1000;
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
        fcm_token TEXT,
        fcm_token_updated_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db.prepare("DELETE FROM usuarios WHERE id = ?").bind(USUARIO).run();
  await db
    .prepare(
      `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo)
       VALUES (?, 'cliente', 'fecha@fcm.test', 'hash', 'Con Fecha')`
    )
    .bind(USUARIO)
    .run();
});

beforeEach(async () => {
  await db
    .prepare("UPDATE usuarios SET fcm_token = NULL, fcm_token_updated_at = NULL WHERE id = ?")
    .bind(USUARIO)
    .run();
});

describe("Registrar el token de notificaciones", () => {
  it("guarda el token y la fecha del momento", async () => {
    const res = await registrarToken("token-nuevo-abc");

    expect(res.status).toBe(200);

    const usuario = await leerUsuario();
    expect(usuario?.fcm_token).toBe("token-nuevo-abc");

    // La fecha es la de ahora, no una inventada ni una fija.
    const segundos = segundosDesde(usuario?.fcm_token_updated_at ?? null);
    expect(segundos).toBeGreaterThanOrEqual(0);
    expect(segundos).toBeLessThan(120);
  });

  it("el formato es el que usa el resto del proyecto: texto UTC sin T", async () => {
    await registrarToken("token-formato");

    const usuario = await leerUsuario();
    const fecha = usuario?.fcm_token_updated_at ?? "";

    // Igual que datetime('now'): "YYYY-MM-DD HH:MM:SS".
    expect(fecha).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
  });

  it("un token nuevo mueve la fecha", async () => {
    await registrarToken("token-primero");
    const primera = (await leerUsuario())?.fcm_token_updated_at ?? null;

    // Se espera un segundo para que la marca de tiempo cambie de verdad.
    await new Promise((r) => setTimeout(r, 1100));

    await registrarToken("token-segundo");
    const segunda = (await leerUsuario())?.fcm_token_updated_at ?? null;

    expect(segunda).not.toBe(primera);
    expect(segundosDesde(segunda)).toBeLessThan(120);
  });

  it("limpiar el token no borra la última fecha conocida", async () => {
    await registrarToken("token-que-se-va");
    const conToken = await leerUsuario();

    // Vaciar el token es lo que hace un cliente al perder el registro. La
    // fecha del último registro real es justo el dato que sirve para
    // diagnosticar, así que no debe sobrescribirse con "ahora".
    const res = await registrarToken(null);
    expect(res.status).toBe(200);

    const usuario = await leerUsuario();
    expect(usuario?.fcm_token).toBeNull();
    expect(usuario?.fcm_token_updated_at).toBe(conToken?.fcm_token_updated_at);
  });

  it("un token vacío en blanco cuenta como limpiar, no como registrar", async () => {
    const res = await registrarToken("   ");

    expect(res.status).toBe(200);

    const usuario = await leerUsuario();
    expect(usuario?.fcm_token).toBeNull();
    expect(usuario?.fcm_token_updated_at).toBeNull();
  });

  it("exige sesión", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/fcm-token",
      {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ fcm_token: "token-sin-sesion" }),
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(401);
  });
});
