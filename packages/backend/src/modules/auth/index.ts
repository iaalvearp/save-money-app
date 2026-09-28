import { Hono } from "hono";
import { partesDeFecha, calendarioEcuador } from "../../lib/fechas";
import type { Context } from "hono";
import { sign, verify } from "@tsndr/cloudflare-worker-jwt";
import type { AppEnv } from "../../index";
import { notificarAUsuarios } from "../notificaciones/index";
import { haversineDistance } from "../flash/index";

const auth = new Hono<AppEnv>();

interface CustomJwtPayload {
  sub?: string;
  rol?: string;
  type?: string;
  iat?: number;
  exp?: number;
}

const PBKDF2_ITERATIONS = 10_000;

async function hashPassword(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const salt = crypto.getRandomValues(new Uint8Array(16));

  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    encoder.encode(password),
    "PBKDF2",
    false,
    ["deriveBits"]
  );

  const hash = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt,
      iterations: PBKDF2_ITERATIONS,
    },
    keyMaterial,
    256
  );

  const saltHex = Array.from(salt)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const hashHex = Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return `pbkdf2:${PBKDF2_ITERATIONS}:${saltHex}:${hashHex}`;
}

async function verifyPassword(
  password: string,
  storedHash: string
): Promise<boolean> {
  const encoder = new TextEncoder();

  if (storedHash.startsWith("pbkdf2:")) {
    const [, iterStr, saltHex, expectedHash] = storedHash.split(":");
    const iterations = parseInt(iterStr, 10);
    const salt = new Uint8Array(
      saltHex.match(/.{1,2}/g)!.map((byte) => parseInt(byte, 16))
    );

    const keyMaterial = await crypto.subtle.importKey(
      "raw",
      encoder.encode(password),
      "PBKDF2",
      false,
      ["deriveBits"]
    );

    const hash = await crypto.subtle.deriveBits(
      {
        name: "PBKDF2",
        hash: "SHA-256",
        salt,
        iterations,
      },
      keyMaterial,
      256
    );

    const hashHex = Array.from(new Uint8Array(hash))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    return hashHex === expectedHash;
  }

  // Legacy SHA-256 format: saltHex:hashHex
  const [saltHex, expectedHash] = storedHash.split(":");
  const salt = new Uint8Array(
    saltHex.match(/.{1,2}/g)!.map((byte) => parseInt(byte, 16))
  );
  const saltedPassword = encoder.encode(salt.toString() + password);
  const hash = await crypto.subtle.digest("SHA-256", saltedPassword);
  const hashHex = Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return hashHex === expectedHash;
}

function nowEpoch(): number {
  return Math.floor(Date.now() / 1000);
}

/**
 * Cuántos años tiene alguien, en el calendario de Ecuador.
 *
 * Antes se hacía con `getFullYear()`, `getMonth()` y `getDate()` sobre un
 * `new Date(fechaNacimiento)`. Eso tenía dos problemas encadenados:
 *
 * - Un texto de solo fecha, como "2008-01-01", es medianoche **UTC**. Los
 *   getters, en cambio, leen la **hora local del runtime**. Con el runtime en
 *   UTC el día salía bien, pero en Ecuador la medianoche UTC ya era la tarde
 *   del día anterior, y el nacimiento se leía corrido un día.
 * - `hoy` sí era un instante, pero sus getters también son de hora local. Con
 *   runtime UTC, el calendario que ve el backend va cinco horas adelantado al
 *   de Ecuador, así que entre las 19:00 y la medianoche de Ecuador el sistema
 *   ya creía que había cambiado el día.
 *
 * El resultado no era un problema de pruebas locales: en producción, quien
 * cumple años entre las 19:00 y la medianoche de Ecuador veía reconocido su
 * estatus de adulto hasta cinco horas antes, y eso abre la puerta al
 * consentimiento publicitario de un menor.
 *
 * Ahora se leen el año, el mes y el día del texto, y se comparan contra el día
 * de hoy en Ecuador. El resultado no depende de dónde corra el código.
 *
 * Devuelve `null` cuando la fecha no se puede leer. Quien llama tiene que
 * mirar ese `null` explícitamente: en una puerta que protege a un menor,
 * dejar pasar lo que no se entiende sería justo el error que se quiere evitar.
 */
function calcularEdad(
  fechaNacimiento: string,
  hoy: number = Date.now()
): number | null {
  const nacimiento = partesDeFecha(fechaNacimiento);
  if (nacimiento === null) return null;

  const hoyEcuador = calendarioEcuador(hoy);

  let edad = hoyEcuador.anio - nacimiento.anio;
  const yaCumplioEsteAnio =
    hoyEcuador.mes > nacimiento.mes ||
    (hoyEcuador.mes === nacimiento.mes && hoyEcuador.dia >= nacimiento.dia);

  // Un 29 de febrero solo existe en años bisiestos. En los que no, se cumple
  // años el 28 de febrero, que es lo que la ley y la costumbre usan.
  const cumpleHoy =
    hoyEcuador.mes === 2 &&
    hoyEcuador.dia === 28 &&
    nacimiento.mes === 2 &&
    nacimiento.dia === 29;

  if (!yaCumplioEsteAnio && !cumpleHoy) {
    edad--;
  }

  return edad;
}

async function createAccessToken(
  payload: Record<string, unknown>,
  secret: string
): Promise<string> {
  return sign(
    { ...payload, iat: nowEpoch(), exp: nowEpoch() + 60 * 20 },
    secret
  );
}

async function createRefreshToken(
  payload: Record<string, unknown>,
  secret: string
): Promise<string> {
  return sign(
    { ...payload, type: "refresh", iat: nowEpoch(), exp: nowEpoch() + 60 * 60 * 24 * 14 },
    secret
  );
}

auth.post("/registro", async (c) => {
  const db = c.env.DB;
  const body = await c.req.json<{
    email: string;
    password: string;
    nombre_completo: string;
    rol: string;
    fecha_nacimiento?: string;
    consentimiento_publicidad?: boolean;
  }>();

  const validRoles = ["cliente", "negocio", "organizador"];
  if (!validRoles.includes(body.rol)) {
    return c.json(
      { error: "Rol inválido. Debe ser: cliente, negocio o organizador" },
      400
    );
  }

  const existing = await db
    .prepare("SELECT id FROM usuarios WHERE email = ?")
    .bind(body.email)
    .first();
  if (existing) {
    return c.json({ error: "El email ya está registrado" }, 409);
  }

  if (body.consentimiento_publicidad === true) {
    if (!body.fecha_nacimiento) {
      return c.json(
        {
          error:
            "Fecha de nacimiento requerida para otorgar consentimiento publicitario",
        },
        422
      );
    }
    const edad = calcularEdad(body.fecha_nacimiento);
    // Un null es una fecha que no se entiende, no una edad. Antes `null < 18`
    // daba falso y la peticion pasaba de largo; ahora se rechaza explicita.
    if (edad === null) {
      return c.json(
        {
          error: "La fecha de nacimiento no es valida",
        },
        422
      );
    }
    if (edad < 18) {
      return c.json(
        {
          error:
            "Debes ser mayor de 18 años para otorgar consentimiento publicitario",
        },
        422
      );
    }
  }

  const consentValue = body.consentimiento_publicidad === true ? 1 : null;
  const consentFecha =
    body.consentimiento_publicidad === true ? new Date().toISOString() : null;

  const passwordHash = await hashPassword(body.password);

  const result = await db
    .prepare(
      `INSERT INTO usuarios (email, password_hash, nombre_completo, rol, fecha_nacimiento, consentimiento_publicidad, consentimiento_publicidad_fecha)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    )
    .bind(
      body.email,
      passwordHash,
      body.nombre_completo,
      body.rol,
      body.fecha_nacimiento || null,
      consentValue,
      consentFecha
    )
    .run();

  const userId = result.meta.last_row_id;

  if (body.rol === "negocio") {
    await db
      .prepare(
        `INSERT INTO comercios (usuario_id, nombre) VALUES (?, ?)`
      )
      .bind(userId, body.nombre_completo)
      .run();
  }

  const secret = c.env.JWT_SECRET;
  const accessToken = await createAccessToken(
    { sub: String(userId), rol: body.rol },
    secret
  );
  const refreshToken = await createRefreshToken(
    { sub: String(userId), rol: body.rol },
    secret
  );

  return c.json({
    user: {
      id: userId,
      email: body.email,
      nombre_completo: body.nombre_completo,
      rol: body.rol,
    },
    access_token: accessToken,
    refresh_token: refreshToken,
  }, 201);
});

auth.post("/login", async (c) => {
  const db = c.env.DB;
  const body = await c.req.json<{
    email: string;
    password: string;
  }>();

  const user = await db
    .prepare(
      "SELECT id, email, password_hash, nombre_completo, rol FROM usuarios WHERE email = ?"
    )
    .bind(body.email)
    .first<{
      id: number;
      email: string;
      password_hash: string;
      nombre_completo: string;
      rol: string;
    }>();

  if (!user) {
    return c.json({ error: "Credenciales inválidas" }, 401);
  }

  const valid = await verifyPassword(body.password, user.password_hash);
  if (!valid) {
    return c.json({ error: "Credenciales inválidas" }, 401);
  }

  const secret = c.env.JWT_SECRET;
  const accessToken = await createAccessToken(
    { sub: String(user.id), rol: user.rol },
    secret
  );
  const refreshToken = await createRefreshToken(
    { sub: String(user.id), rol: user.rol },
    secret
  );

  return c.json({
    user: {
      id: user.id,
      email: user.email,
      nombre_completo: user.nombre_completo,
      rol: user.rol,
    },
    access_token: accessToken,
    refresh_token: refreshToken,
  });
});

auth.post("/refresh", async (c) => {
  const body = await c.req.json<{ refresh_token: string }>();
  const secret = c.env.JWT_SECRET;

  const decoded = await verify(body.refresh_token, secret);
  if (!decoded) {
    return c.json({ error: "Refresh token inválido o expirado" }, 401);
  }

  const payload = decoded.payload as unknown as CustomJwtPayload;
  if (payload.type !== "refresh") {
    return c.json({ error: "Token no es un refresh token" }, 401);
  }

  const accessToken = await createAccessToken(
    { sub: payload.sub, rol: payload.rol },
    secret
  );

  return c.json({ access_token: accessToken });
});

auth.patch("/consentimiento", async (c) => {
  const db = c.env.DB;
  const authHeader = c.req.header("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return c.json({ error: "Token requerido" }, 401);
  }

  const token = authHeader.slice(7);
  const secret = c.env.JWT_SECRET;
  const decoded = await verify(token, secret);
  if (!decoded) {
    return c.json({ error: "Token inválido o expirado" }, 401);
  }

  const payload = decoded.payload as unknown as CustomJwtPayload;
  const userId = Number(payload.sub);

  const body = await c.req.json<{
    consentimiento_publicidad: boolean;
  }>();

  const user = await db
    .prepare(
      "SELECT id, fecha_nacimiento, consentimiento_publicidad FROM usuarios WHERE id = ?"
    )
    .bind(userId)
    .first<{
      id: number;
      fecha_nacimiento: string | null;
      consentimiento_publicidad: number | null;
    }>();

  if (!user) {
    return c.json({ error: "Usuario no encontrado" }, 404);
  }

  if (body.consentimiento_publicidad === true) {
    if (!user.fecha_nacimiento) {
      return c.json(
        {
          error:
            "Fecha de nacimiento requerida para otorgar consentimiento publicitario",
        },
        422
      );
    }
    const edad = calcularEdad(user.fecha_nacimiento);
    // Igual que en el registro: una fecha ilegible no se interpreta como
    // "no es menor". Se rechaza.
    if (edad === null) {
      return c.json(
        {
          error: "La fecha de nacimiento no es valida",
        },
        422
      );
    }
    if (edad < 18) {
      return c.json(
        {
          error:
            "Debes ser mayor de 18 años para otorgar consentimiento publicitario",
        },
        422
      );
    }
  }

  const consentValue = body.consentimiento_publicidad ? 1 : null;
  const consentFecha = body.consentimiento_publicidad
    ? new Date().toISOString()
    : null;

  await db
    .prepare(
      `UPDATE usuarios
       SET consentimiento_publicidad = ?, consentimiento_publicidad_fecha = ?
       WHERE id = ?`
    )
    .bind(consentValue, consentFecha, userId)
    .run();

  return c.json({
    consentimiento_publicidad: body.consentimiento_publicidad,
    consentimiento_publicidad_fecha: consentFecha,
  });
});

type ResultadoAuth =
  | { userId: number; error?: undefined }
  | { userId?: undefined; error: string };

/** Verifica el access token y devuelve el id del usuario o el error a responder. */
async function autenticar(c: Context<AppEnv>): Promise<ResultadoAuth> {
  const authHeader = c.req.header("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return { error: "Token requerido" };
  }

  const decoded = await verify(authHeader.slice(7), c.env.JWT_SECRET);
  if (!decoded) {
    return { error: "Token inválido o expirado" };
  }

  const payload = decoded.payload as unknown as CustomJwtPayload;
  return { userId: Number(payload.sub) };
}

auth.put("/fcm-token", async (c) => {
  const db = c.env.DB;
  const auth = await autenticar(c);
  if (auth.userId === undefined) {
    return c.json({ error: auth.error }, 401);
  }

  const body = await c.req.json<{ fcm_token?: string }>();

  const fcmToken = body.fcm_token?.trim() || null;

  await db
    .prepare("UPDATE usuarios SET fcm_token = ? WHERE id = ?")
    .bind(fcmToken, auth.userId)
    .run();

  return c.json({ ok: true });
});

/**
 * Registra la última posición conocida del usuario y notifica las promociones
 * Flash activas que entren en su radio.
 *
 * La notificación se envía como máximo una vez por usuario+promoción: la fila
 * se reclama ANTES de enviar (INSERT OR IGNORE + UNIQUE), así que dos reportes
 * simultáneos no pueden duplicar el push. Prioriza "nunca repetir" sobre
 * "nunca perder", que es la regla de negocio acordada.
 */
auth.put("/ubicacion", async (c) => {
  const db = c.env.DB;
  const auth = await autenticar(c);
  if (auth.userId === undefined) {
    return c.json({ error: auth.error }, 401);
  }
  const userId = auth.userId;

  const body = await c.req.json<{ latitud?: number; longitud?: number }>();
  const latitud = Number(body.latitud);
  const longitud = Number(body.longitud);

  if (!isFinite(latitud) || !isFinite(longitud)) {
    return c.json({ error: "latitud y longitud son requeridos" }, 400);
  }
  if (latitud < -90 || latitud > 90 || longitud < -180 || longitud > 180) {
    return c.json({ error: "Coordenadas fuera de rango" }, 400);
  }

  await db
    .prepare(
      `INSERT INTO ubicaciones_usuarios (usuario_id, latitud, longitud, actualizado_en)
       VALUES (?, ?, ?, CURRENT_TIMESTAMP)
       ON CONFLICT (usuario_id) DO UPDATE SET
         latitud = excluded.latitud,
         longitud = excluded.longitud,
         actualizado_en = excluded.actualizado_en`
    )
    .bind(userId, latitud, longitud)
    .run();

  const nearby = await db
    .prepare(
      `SELECT pf.id, pf.titulo, pf.latitud, pf.longitud, pf.radio_km,
              c.nombre AS comercio_nombre
       FROM promociones_flash pf
       JOIN comercios c ON pf.comercio_id = c.id
       WHERE pf.inicia_en <= datetime('now')
         AND pf.termina_en > datetime('now')
         AND pf.latitud IS NOT NULL
         AND pf.longitud IS NOT NULL`
    )
    .all<{
      id: number;
      titulo: string;
      latitud: number;
      longitud: number;
      radio_km: number | null;
      comercio_nombre: string;
    }>();

  let notificadas = 0;
  for (const promo of nearby.results ?? []) {
    const radio = promo.radio_km ?? 5;
    const distancia = haversineDistance(
      latitud,
      longitud,
      promo.latitud,
      promo.longitud
    );
    if (distancia > radio) continue;

    // Reclamar la combinación usuario+promoción antes de enviar.
    const reclamo = await db
      .prepare(
        `INSERT OR IGNORE INTO flash_notificaciones_enviadas (usuario_id, promocion_id)
         VALUES (?, ?)`
      )
      .bind(userId, promo.id)
      .run();

    const yaNotificado =
      (reclamo.meta.changes ?? 0) === 0;
    if (yaNotificado) continue;

    await notificarAUsuarios(
      c,
      [userId],
      `Promoción cerca de ti: ${promo.titulo}`,
      `${promo.comercio_nombre} tiene una promoción a ${distancia.toFixed(1)} km de ti.`,
      { tipo: "flash_cercania", promocion_id: String(promo.id) }
    );
    notificadas++;
  }

  return c.json({ ok: true, notificadas });
});

export { auth };
