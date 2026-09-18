declare module "cloudflare:test" {
  interface Env {
    DB: D1Database;
  }
  const env: Env;
}
