import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) => {
  return c.json({ status: "ok", message: "save-money-app API en línea" });
});

export default app;
