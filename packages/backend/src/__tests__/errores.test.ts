import { describe, it, expect, afterEach, vi } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import app from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-errores";

/**
 * Base de datos que revienta en la primera consulta. Sirve para provocar un
 * error inesperado y ver como sale por la respuesta, sin depender de que una
 * consulta concreta falle por sus datos.
 */
const dbQueRevienta = {
  prepare() {
    throw new Error("D1 fallo: no such table: _INTERNAL_SEGREDO");
  },
} as unknown as D1Database;

const bindings = {
  DB: db,
  JWT_SECRET,
  SRI_ENFORCE_VALIDATION: "false",
  FCM_CLIENT_EMAIL: "firebase-adminsdk-x@proyecto.iam.gserviceaccount.com",
  FCM_PRIVATE_KEY: "clave-de-prueba",
};

let errores: ReturnType<typeof vi.spyOn> | undefined;

afterEach(() => {
  errores?.mockRestore();
  errores = undefined;
});

function silenciarErrores() {
  errores = vi.spyOn(console, "error").mockImplementation(() => {});
}

describe("manejador global de errores", () => {
  it("responde JSON cuando una ruta revienta, no texto plano", async () => {
    silenciarErrores();

    const res = await app.request("/comercios", {}, { ...bindings, DB: dbQueRevienta });

    expect(res.status).toBe(500);
    expect(res.headers.get("content-type")).toContain("application/json");

    const body = (await res.json()) as { error: string };
    expect(typeof body.error).toBe("string");
    expect(body.error).toBe("Error interno del servidor");
  });

  it("no filtra el detalle interno del fallo al cliente", async () => {
    silenciarErrores();

    const res = await app.request("/comercios", {}, { ...bindings, DB: dbQueRevienta });
    const texto = await res.text();

    expect(texto).not.toContain("_INTERNAL_SEGREDO");
    expect(texto).not.toContain("no such table");
    expect(texto).not.toContain("Error:");
  });

  it("registra el detalle real en el log del servidor", async () => {
    silenciarErrores();

    await app.request("/comercios", {}, { ...bindings, DB: dbQueRevienta });

    // El diagnostico se conserva para el que mira los logs, aunque no salga.
    expect(errores).toHaveBeenCalled();
    const segundo = (errores as unknown as { mock: { calls: unknown[][] } }).mock
      .calls[0][1] as Error;
    expect(segundo.message).toContain("_INTERNAL_SEGREDO");
  });

  it("responde 404 en JSON para una ruta que no existe", async () => {
    const res = await app.request("/ruta/que/no/existe", {}, bindings);

    expect(res.status).toBe(404);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("Recurso no encontrado");
  });

  it("un token mal formado responde 401 en JSON, no 500", async () => {
    const res = await app.request(
      "/hunt/eventos/1/entradas",
      { headers: { Authorization: "Bearer esto-no-es-un-jwt" } },
      bindings
    );

    expect(res.status).toBe(401);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("Token inválido o expirado");
  });

  it("un token bien formado pero con rol insuficiente responde 403 en JSON", async () => {
    const token = await sign(
      { sub: "1", rol: "cliente", exp: Math.floor(Date.now() / 1000) + 3600 },
      JWT_SECRET
    );

    const res = await app.request(
      "/hunt/eventos/1/entradas",
      { headers: { Authorization: `Bearer ${token}` } },
      bindings
    );

    expect(res.status).toBe(403);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain("permiso");
  });

  it("la ruta de salud sigue respondiendo bien", async () => {
    const res = await app.request("/", {}, bindings);

    expect(res.status).toBe(200);
    const body = (await res.json()) as { status: string };
    expect(body.status).toBe("ok");
  });
});
