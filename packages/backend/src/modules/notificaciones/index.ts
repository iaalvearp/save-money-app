import { Hono } from "hono";
import type { Context } from "hono";
import { authMiddleware } from "../auth/middleware";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const FCM_BASE_URL = "https://fcm.googleapis.com/v1";

type NotificacionesEnv = {
  Bindings: {
    DB: D1Database;
    JWT_SECRET: string;
    FCM_CLIENT_EMAIL: string;
    FCM_PRIVATE_KEY: string;
  };
  Variables: {
    user: { sub: number; rol: string };
  };
};

// Minimum shape required to deliver a push. Declared structurally (instead of
// Hono's Context) so any module (hunt, flash, ...) can reuse this very same
// sender without its env having to match exactly.
type FcmContexto = {
  env: {
    FCM_CLIENT_EMAIL: string;
    FCM_PRIVATE_KEY: string;
  };
};

const notificaciones = new Hono<NotificacionesEnv>();

function base64UrlEncode(data: Uint8Array | ArrayBuffer): string {
  let binary = "";
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN [A-Z ]*KEY-----/g, "")
    .replace(/-----END [A-Z ]*KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer as ArrayBuffer;
}

async function firmaJwt(
  privateKeyPem: string,
  claims: Record<string, unknown>
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const encoder = new TextEncoder();
  const signingInput =
    base64UrlEncode(encoder.encode(JSON.stringify(header))) +
    "." +
    base64UrlEncode(encoder.encode(JSON.stringify(claims)));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKeyPem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(signingInput)
  );

  return signingInput + "." + base64UrlEncode(signature);
}

async function obtenerAccessToken(
  clientEmail: string,
  privateKey: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: clientEmail,
    scope: FCM_SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };

  const assertion = await firmaJwt(privateKey, claims);

  const body = new URLSearchParams();
  body.set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
  body.set("assertion", assertion);

  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (!response.ok) {
    throw new Error(
      `No se pudo obtener access token de Firebase: ${response.status} ${await response.text()}`
    );
  }

  const data = (await response.json()) as { access_token?: string };
  if (!data.access_token) {
    throw new Error("Respuesta de OAuth2 sin access_token");
  }
  return data.access_token;
}

function projectIdDeClientEmail(clientEmail: string): string {
  const match = clientEmail.match(
    /^[^@]+@([^.]+)\.iam\.gserviceaccount\.com$/
  );
  const projectId = match?.[1];
  if (!projectId) {
    throw new Error(
      "FCM_CLIENT_EMAIL no es una cuenta de servicio válida de Google"
    );
  }
  return projectId;
}

export async function enviarNotificacion(
  c: FcmContexto,
  fcmToken: string | null | undefined,
  titulo: string,
  cuerpo: string,
  data?: Record<string, string>
): Promise<void> {
  if (!fcmToken || fcmToken.trim() === "") {
    return;
  }

  const clientEmail = c.env.FCM_CLIENT_EMAIL;
  const privateKey = c.env.FCM_PRIVATE_KEY;

  const projectId = projectIdDeClientEmail(clientEmail);
  const accessToken = await obtenerAccessToken(clientEmail, privateKey);

  const message: Record<string, unknown> = {
    token: fcmToken,
    notification: { title: titulo, body: cuerpo },
  };
  if (data && Object.keys(data).length > 0) {
    message["data"] = data;
  }

  const response = await fetch(
    `${FCM_BASE_URL}/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ message }),
    }
  );

  if (!response.ok) {
    throw new Error(
      `FCM devolvió el error ${response.status}: ${await response.text()}`
    );
  }
}

notificaciones.post(
  "/test",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const userId = c.get("user").sub;

    const usuario = await db
      .prepare("SELECT fcm_token FROM usuarios WHERE id = ?")
      .bind(userId)
      .first<{ fcm_token: string | null }>();

    if (!usuario?.fcm_token) {
      return c.json({
        ok: false,
        error: "El usuario no tiene un token de notificaciones registrado",
      });
    }

    await enviarNotificacion(
      c,
      usuario.fcm_token,
      "Hola desde Save Money",
      "¡Es una notificación de prueba! 🎉"
    );

    return c.json({ ok: true, mensaje: "Notificación de prueba enviada" });
  }
);

/**
 * Envía una misma notificación a varios usuarios reutilizando `enviarNotificacion`.
 * Los usuarios sin token FCM registrado se omiten silenciosamente.
 * Devuelve cuántos envíos reales se hicieron (los que tenían token).
 */
export async function notificarAUsuarios(
  c: FcmContexto & { env: { DB: D1Database } },
  usuarioIds: number[],
  titulo: string,
  cuerpo: string,
  data?: Record<string, string>
): Promise<number> {
  const unicos = [...new Set(usuarioIds)];
  if (unicos.length === 0) {
    return 0;
  }

  const placeholders = unicos.map(() => "?").join(", ");
  const filas = await c.env.DB
    .prepare(`SELECT id, fcm_token FROM usuarios WHERE id IN (${placeholders})`)
    .bind(...unicos)
    .all<{ id: number; fcm_token: string | null }>();

  let enviados = 0;
  for (const fila of filas.results ?? []) {
    if (!fila.fcm_token) continue;
    await enviarNotificacion(c, fila.fcm_token, titulo, cuerpo, data);
    enviados++;
  }
  return enviados;
}

export { notificaciones };