import { verify } from "@tsndr/cloudflare-worker-jwt";
import type { Context, Next } from "hono";

interface AppEnv {
  Bindings: {
    DB: D1Database;
    JWT_SECRET: string;
  };
  Variables: {
    user: { sub: number; rol: string };
  };
}

interface CustomJwtPayload {
  sub?: string;
  rol?: string;
  type?: string;
}

export async function authMiddleware(
  c: Context<AppEnv>,
  next: Next
): Promise<Response | void> {
  const header = c.req.header("Authorization");
  if (!header || !header.startsWith("Bearer ")) {
    return c.json({ error: "Token de autenticación requerido" }, 401);
  }

  const token = header.slice(7);
  const secret = c.env.JWT_SECRET;

  // verify() lanza si el token esta mal formado (no solo si la firma no
  // cuadra). Un token basura es lo mismo que un token invalido, asi que se
  // responde 401 en vez de dejar que reviente la peticion con un 500.
  let decoded: Awaited<ReturnType<typeof verify>> | null | undefined;
  try {
    decoded = await verify(token, secret);
  } catch {
    decoded = null;
  }

  if (!decoded) {
    return c.json({ error: "Token inválido o expirado" }, 401);
  }

  const payload = decoded.payload as unknown as CustomJwtPayload;
  if (payload.type === "refresh") {
    return c.json({ error: "Se requiere access token, no refresh token" }, 401);
  }

  c.set("user", { sub: Number(payload.sub), rol: payload.rol as string });
  await next();
}

export function requireRole(...roles: string[]) {
  return async (c: Context<AppEnv>, next: Next): Promise<Response | void> => {
    const user = c.get("user");
    if (!user) {
      return c.json({ error: "No autenticado" }, 401);
    }
    if (!roles.includes(user.rol)) {
      return c.json({ error: "No tienes permiso para acceder a este recurso" }, 403);
    }
    await next();
  };
}
