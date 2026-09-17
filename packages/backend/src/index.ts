import { Hono } from "hono";
import { auth } from "./modules/auth/index";
import { discover } from "./modules/discover/index";
import { facturas } from "./modules/facturas/index";

type Bindings = {
  DB: D1Database;
  JWT_SECRET: string;
  SRI_ENFORCE_VALIDATION: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.get("/", (c) => {
  return c.json({ status: "ok", message: "save-money-app API en línea" });
});

app.route("/auth", auth);
app.route("/", discover);
app.route("/facturas", facturas);

export type AppEnv = { Bindings: Bindings };
export default app;
