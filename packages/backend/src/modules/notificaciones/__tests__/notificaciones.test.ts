import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "../../auth/index";
import { notificaciones, enviarNotificacion } from "../index";
import {
  generarCredencialesFcmDePrueba,
  interceptarFcm,
  credencialesFcmQueFallan,
  type CredencialesFcm,
} from "../../../test-utils/fcm";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-notificaciones";
const FCM_CLIENT_EMAIL = "firebase-adminsdk-abc@save-money-proyecto.iam.gserviceaccount.com";
const FCM_PRIVATE_KEY = "clave-privada-de-prueba";

let credenciales: CredencialesFcm;
let fcm: ReturnType<typeof interceptarFcm>;

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
  credenciales = await generarCredencialesFcmDePrueba();
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
        fcm_token_updated_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

    await db
      .prepare(
        `CREATE TABLE IF NOT EXISTS notificaciones_enviadas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
          tipo TEXT NOT NULL,
          titulo TEXT NOT NULL,
          cuerpo TEXT NOT NULL,
          data TEXT,
          enviado_en TEXT NOT NULL DEFAULT (datetime('now')),
          fcm_aceptado INTEGER NOT NULL DEFAULT 0
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

beforeEach(async () => {
  fcm = interceptarFcm();
  await db.prepare("DELETE FROM notificaciones_enviadas").run();
});

afterEach(() => {
  fcm.restaurar();
});

describe("POST /notificaciones/test", () => {
  it("deja una fila con tipo prueba, saliendo por el mismo camino que un disparador real", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");
    await db
      .prepare("UPDATE usuarios SET fcm_token = 'device-token-abc' WHERE id = 1")
      .run();

    const res = await app.request(
      "/notificaciones/test",
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET, ...credenciales }
    );

    expect(res.status).toBe(200);
    expect(fcm.envios).toHaveLength(1);

    const fila = await db
      .prepare(
        "SELECT usuario_id, tipo, titulo, cuerpo, data, fcm_aceptado FROM notificaciones_enviadas"
      )
      .first<{
        usuario_id: number;
        tipo: string;
        titulo: string;
        cuerpo: string;
        data: string | null;
        fcm_aceptado: number;
      }>();

    expect(fila?.usuario_id).toBe(1);
    expect(fila?.tipo).toBe("prueba");
    expect(fila?.fcm_aceptado).toBe(1);
    expect(fila?.titulo).toBe("Hola desde Save Money");
    expect(fila?.cuerpo).toContain("notificación de prueba");
    // El botón de prueba no manda data, y queda registrado como tal.
    expect(fila?.data).toBeNull();
  });

  it("deja la fila con fcm_aceptado en 0 si Firebase falla", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");
    await db
      .prepare("UPDATE usuarios SET fcm_token = 'device-token-abc' WHERE id = 1")
      .run();

    const res = await app.request(
      "/notificaciones/test",
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET, ...credencialesFcmQueFallan() }
    );

    // La fila es justo lo que se busca cuando el botón dice que sí y la
    // notificación no aparece: queda constancia del intento.
    expect(res.status).toBe(200);

    const fila = await db
      .prepare("SELECT tipo, fcm_aceptado FROM notificaciones_enviadas")
      .first<{ tipo: string; fcm_aceptado: number }>();
    expect(fila?.tipo).toBe("prueba");
    expect(fila?.fcm_aceptado).toBe(0);
  });

  it("responde 400 con un mensaje claro cuando el usuario no tiene token FCM", async () => {
    const app = buildApp();
    const token = await makeToken(1, "cliente");

    await db.prepare("UPDATE usuarios SET fcm_token = NULL WHERE id = 1").run();

    const res = await app.request(
      "/notificaciones/test",
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY }
    );

    // 400 y no 200 con ok:false: la app tomaba el 200 como un envio exitoso.
    expect(res.status).toBe(400);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("notificaciones");

    // Sin token no se intentó nada, así que tampoco hay fila que lo diga.
    const filas = await db
      .prepare("SELECT COUNT(*) AS n FROM notificaciones_enviadas")
      .first<{ n: number }>();
    expect(filas?.n).toBe(0);
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