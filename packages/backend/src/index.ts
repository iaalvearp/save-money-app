import { Hono } from "hono";
import { auth } from "./modules/auth/index";
import { discover } from "./modules/discover/index";

type Bindings = {
  DB: D1Database;
  JWT_SECRET: string;
};

const app = new Hono<{ Bindings: Bindings }>();

app.get("/", (c) => {
  return c.json({ status: "ok", message: "save-money-app API en línea" });
});

app.route("/auth", auth);
app.route("/", discover);

export type AppEnv = { Bindings: Bindings };
export default app;
