import { describe, it, expect, beforeAll, vi } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "../../auth/index";
import { notificaciones, enviarNotificacion } from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-notificaciones";
const FCM_CLIENT_EMAIL = "firebase-adminsdk-abc@save-money-proyecto.iam.gserviceaccount.com";
const FCM_PRIVATE_KEY = "clave-privada-de-prueba";

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/auth", auth);
  app.route("/notificaciones", notificaciones);
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
    .prepare("DROP TABLE IF EXISTS usuarios")
    .run();
  await db
    .prepare(
      `CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rol TEXT NOT NULL CHECK (rol IN ('cliente','negocio','organizador','admin')),
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        nombre_completo TEXT NOT NULL,
        fecha_nacimiento TEXT,
        consentimiento_publicidad INTEGER,
        consentimiento_publicidad_fecha TEXT,
        fcm_token TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "cliente-notif@test.com", "hash", "Cliente Notif")
    .run();
});

describe("PUT /auth/fcm-token", () => {
  it("guarda el token FCM del usuario autenticado", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    const res = await app.request(
      "/auth/fcm-token",
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ fcm_token: "device-token-abc" }),
      },
      { DB: db, JWT_SECRET }
    );
    expect(res.status).toBe(200);

    const row = await db
      .prepare("SELECT fcm_token FROM usuarios WHERE id = 1")
      .first<{ fcm_token: string }>();
    expect(row?.fcm_token).toBe("device-token-abc");
  });

  it("requiere autenticación", async () => {
    const app = buildApp();

    const res = await app.request(
      "/auth/fcm-token",
      {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ fcm_token: "token-sin-auth" }),
      },
      { DB: db, JWT_SECRET }
    );
    expect(res.status).toBe(401);
  });
});

describe("POST /notificaciones/test", () => {
  it("devuelve ok false cuando el usuario no tiene token FCM registrado", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    await db.prepare("UPDATE usuarios SET fcm_token = NULL WHERE id = 1").run();

    const res = await app.request(
      "/notificaciones/test",
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY }
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean };
    expect(body.ok).toBe(false);
  });
});

describe("enviarNotificacion", () => {
  it("no hace nada cuando el token FCM es null o vacío", async () => {
    const fetchSpy = vi.fn();
    const originalFetch = globalThis.fetch;
    (globalThis as { fetch: unknown }).fetch = fetchSpy;

    const c = {
      env: { FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY },
    } as never;

    try {
      await expect(
        enviarNotificacion(c, null, "Título", "Cuerpo")
      ).resolves.toBeUndefined();
      await expect(
        enviarNotificacion(c, "", "Título", "Cuerpo")
      ).resolves.toBeUndefined();
      expect(fetchSpy).not.toHaveBeenCalled();
    } finally {
      (globalThis as { fetch: unknown }).fetch = originalFetch;
    }
  });
});