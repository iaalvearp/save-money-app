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

/**
 * Convierte una clave privada PEM a DER para poder importarla.
 *
 * La clave se pega en Cloudflare de varias formas y no siempre llega como la
 * que se espera: puede traer los saltos de linea reales, la secuencia de dos
 * caracteres "\n" si se copio desde un archivo JSON, comillas envolventes,
 * finales "\r\n" o espacios sobrantes. Todo eso se limpia antes de decodificar
 * para que el mismo valor funcione en cualquier caso.
 */
function pemToDer(pem: string): ArrayBuffer {
  // 1. Si viene con barras invertidas literales (copiado de un JSON), se
  //    convierten en saltos de linea reales antes de limpiar.
  const conSaltosReales = pem.replace(/\\r\\n|\\n|\\r/g, "\n");

  // 2. Se quitan comillas envolventes que a veces deja el pegado.
  const sinComillas = conSaltosReales.replace(/^["']+|["']+$/g, "");

  // 3. Se elimina la cabecera y el pie del PEM, y todo espacio en blanco
  //    (saltos de linea, CR, tabuladores y espacios) que se haya colado.
  const cuerpo = sinComillas
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----/g, "")
    .replace(/-----END [A-Z ]*PRIVATE KEY-----/g, "")
    .replace(/-----BEGIN [A-Z ]*KEY-----/g, "")
    .replace(/-----END [A-Z ]*KEY-----/g, "")
    .replace(/\s+/g, "");

  if (cuerpo.length === 0) {
    throw new Error(
      "FCM_PRIVATE_KEY está vacía o no contiene una clave privada"
    );
  }

  let binary: string;
  try {
    binary = atob(cuerpo);
  } catch {
    // Un mensaje que diga que hacer, en vez del error interno de atob.
    throw new Error(
      "FCM_PRIVATE_KEY no es una clave privada PEM válida: revisa que se haya guardado completa, con sus líneas BEGIN y END, y sin caracteres raros"
    );
  }

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

  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey(
      "pkcs8",
      pemToDer(privateKeyPem),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"]
    );
  } catch (error) {
    // "Invalid PKCS8 input" no le dice nada a quien Guarda el secreto. Se
    // cambia por un mensaje que diga qué variable revisar y cómo se pega.
    if (error instanceof Error && /FCM_PRIVATE_KEY/.test(error.message)) {
      throw error;
    }
    throw new Error(
      "FCM_PRIVATE_KEY no es una clave privada PEM válida: revisa que se haya guardado completa, con sus líneas BEGIN y END, y sin caracteres raros",
      { cause: error }
    );
  }

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

    // Antes esto devolvia 200 con ok:false, y la app lo tomaba como un envio
    // exitoso. Sin token no hay nada que enviar, asi que es un error del
    // cliente: se responde 400 con un mensaje que dice que hacer.
    if (!usuario?.fcm_token) {
      return c.json(
        {
          error:
            "Tu dispositivo no está registrado para recibir notificaciones. Abre la app de nuevo para volver a registrarlo.",
        },
        400
      );
    }

    // Pasa por notificarAUsuarios, no por enviarNotificacion directo, para que la
    // prueba deje la misma fila de auditoría que un disparador real. Si algún día
    // se aparta de ahí, la auditoría miente sobre lo que la app pidió enviar.
    await notificarAUsuarios(
      { ...c, env: { ...c.env, DB: db } },
      [userId],
      "prueba",
      "Hola desde Save Money",
      "¡Es una notificación de prueba! 🎉"
    );

    return c.json({ ok: true, mensaje: "Notificación de prueba enviada" });
  }
);

/**
 * Los disparadores que dejan registro. La lista es cerrada y coincide con el
 * CHECK de la tabla `notificaciones_enviadas`, para que agregar un disparador
 * nuevo sea una decisión explícita y no una cadena cualquiera en una fila.
 */
export type TipoNotificacion =
  | "hunt_inicia"
  | "entrada_aprobada"
  | "premio_ganado"
  | "flash_cercania"
  | "prueba";

/**
 * Deja la fila de auditoría del envío a un destinatario. Se escribe siempre, tanto
 * si FCM aceptó el mensaje como si no lo aceptó o si el usuario no tenía token:
 * cuando hay que averiguar por qué un push no llegó, la ausencia del registro es
 * tan informativa como su contenido.
 */
async function registrarEnvio(
  db: D1Database,
  usuarioId: number,
  tipo: TipoNotificacion,
  titulo: string,
  cuerpo: string,
  data: Record<string, string> | undefined,
  fcmAceptado: boolean
): Promise<void> {
  const dataJson =
    data && Object.keys(data).length > 0 ? JSON.stringify(data) : null;

  try {
    await db
      .prepare(
        `INSERT INTO notificaciones_enviadas
           (usuario_id, tipo, titulo, cuerpo, data, fcm_aceptado)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .bind(usuarioId, tipo, titulo, cuerpo, dataJson, fcmAceptado ? 1 : 0)
      .run();
  } catch (error) {
    // Perder la auditoría no puede tumbar el envío ni la acción que lo disparó.
    console.error(
      `No se pudo registrar el envío de la notificación "${tipo}" al usuario ${usuarioId}:`,
      error
    );
  }
}

/**
 * Envía una misma notificación a varios usuarios reutilizando `enviarNotificacion`.
 * Los usuarios sin token FCM registrado se omiten silenciosamente, pero igual
 * quedan registrados en la auditoría.
 * Devuelve cuántos envíos reales se hicieron (los que tenían token y FCM aceptó).
 */
export async function notificarAUsuarios(
  c: FcmContexto & { env: { DB: D1Database } },
  usuarioIds: number[],
  tipo: TipoNotificacion,
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
    if (!fila.fcm_token) {
      await registrarEnvio(
        c.env.DB, fila.id, tipo, titulo, cuerpo, data, false
      );
      continue;
    }

    // Un token caduca y FCM lo acepta igual. Un fallo con una persona no puede
    // dejar sin avisar a las demás de la lista, así que se aísla por destinatario
    // y el error se registra aquí y no sube hasta la acción principal.
    try {
      await enviarNotificacion(c, fila.fcm_token, titulo, cuerpo, data);
      enviados++;
      await registrarEnvio(
        c.env.DB, fila.id, tipo, titulo, cuerpo, data, true
      );
    } catch (error) {
      console.error(
        `No se pudo enviar la notificación "${tipo}" al usuario ${fila.id}:`,
        error
      );
      await registrarEnvio(
        c.env.DB, fila.id, tipo, titulo, cuerpo, data, false
      );
    }
  }
  return enviados;
}

export { notificaciones };