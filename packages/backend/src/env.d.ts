declare module "hono/types" {
  interface ContextVariableMap {
    user: { sub: number; rol: string };
  }
}
