import { Hono } from "hono";
import { sign, verify } from "@tsndr/cloudflare-worker-jwt";
import type { AppEnv } from "../../index";

const auth = new Hono<AppEnv>();

interface CustomJwtPayload {
  sub?: string;
  rol?: string;
  type?: string;
  iat?: number;
  exp?: number;
}

async function hashPassword(password: string): Promise<string> {
  const encoder = new TextEncoder();
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const saltedPassword = encoder.encode(
    salt.toString() + password
  );
  const hash = await crypto.subtle.digest("SHA-256", saltedPassword);
  const saltHex = Array.from(salt)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const hashHex = Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${saltHex}:${hashHex}`;
}

async function verifyPassword(
  password: string,
  storedHash: string
): Promise<boolean> {
  const encoder = new TextEncoder();
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

  const passwordHash = await hashPassword(body.password);

  const result = await db
    .prepare(
      `INSERT INTO usuarios (email, password_hash, nombre_completo, rol, fecha_nacimiento)
       VALUES (?, ?, ?, ?, ?)`
    )
    .bind(
      body.email,
      passwordHash,
      body.nombre_completo,
      body.rol,
      body.fecha_nacimiento || null
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

export { auth };
