import { Hono } from "hono";
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

app.route("/auth", auth);
app.route("/", discover);
app.route("/facturas", facturas);
app.route("/flash", flash);
app.route("/hunt", hunt);
app.route("/cupones", cupones);
app.route("/notificaciones", notificaciones);

export type AppEnv = { Bindings: Bindings };
export default app;
