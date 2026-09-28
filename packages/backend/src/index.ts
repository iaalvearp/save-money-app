import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { cors } from "hono/cors";
import { auth } from "./modules/auth/index";
import { discover } from "./modules/discover/index";
import { facturas } from "./modules/facturas/index";
import { flash } from "./modules/flash/index";
import { hunt } from "./modules/hunt/index";
import { cupones } from "./modules/cupones/index";
import { notificaciones } from "./modules/notificaciones/index";

type Bindings = {
  DB: D1Database;
  JWT_SECRET: string;
  SRI_ENFORCE_VALIDATION: string;
  FCM_CLIENT_EMAIL: string;
  FCM_PRIVATE_KEY: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.use(
  "*",
  cors({
    origin: "*",
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
  })
);

app.get("/", (c) => {
  return c.json({ status: "ok", message: "save-money-app API en línea" });
});

/**
 * Hono, por defecto, responde a un error inesperado con texto plano y con el
 * detalle interno del fallo. La app solo sabe leer JSON, asi que recibia algo
 * que no podia mostrar y se quedaba sin saber que paso. Aqui todo error sale
 * como {"error": "..."} con un estado HTTP razonable.
 */

/** Saca el estado HTTP del error: el que Hono puso, o 500 si no se sabe. */
function estadoHttpDe(error: unknown): number {
  if (error instanceof HTTPException) {
    return error.status;
  }
  const candidato = error as { status?: unknown; statusCode?: unknown } | null;
  for (const valor of [candidato?.status, candidato?.statusCode]) {
    if (typeof valor === "number" && valor >= 400 && valor <= 599) {
      return valor;
    }
  }
  return 500;
}

/**
 * El mensaje que ve el usuario. Solo se muestra el texto de un error que el
 * codigo lanzo a proposito (HTTPException). Cualquier otra falla dice que paso
 * en general, para no filtrar nombres de tablas, claves ni trazas.
 */
function mensajePublicoDe(error: unknown, status: number): string {
  if (error instanceof HTTPException && error.message.trim() !== "") {
    return error.message;
  }
  if (status === 400) return "Solicitud incorrecta";
  if (status === 401) return "No autenticado";
  if (status === 403) return "No tienes permiso para acceder a este recurso";
  if (status === 404) return "Recurso no encontrado";
  if (status === 409) return "La operación entra en conflicto con el estado actual";
  if (status === 422) return "Los datos enviados no son válidos";
  if (status >= 500) return "Error interno del servidor";
  return "No se pudo completar la solicitud";
}

app.onError((error, c) => {
  const status = estadoHttpDe(error);

  // El detalle real solo se registra en el log del servidor, nunca en la
  // respuesta, para poder diagnosticar sin mostrarlo al cliente.
  if (status >= 500) {
    console.error(`${c.req.method} ${new URL(c.req.url).pathname} falló:`, error);
  }

  return c.json({ error: mensajePublicoDe(error, status) }, status as 400);
});

app.notFound((c) => {
  return c.json({ error: "Recurso no encontrado" }, 404);
});

app.route("/auth", auth);
app.route("/", discover);
app.route("/facturas", facturas);
app.route("/flash", flash);
app.route("/hunt", hunt);
app.route("/cupones", cupones);
app.route("/notificaciones", notificaciones);

export type AppEnv = { Bindings: Bindings };
export default app;
