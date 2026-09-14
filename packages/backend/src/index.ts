import { Hono } from "hono";

const app = new Hono();

app.get("/", (c) => {
  return c.json({ status: "ok", message: "Money Tiger API en línea" });
});

export default app;
