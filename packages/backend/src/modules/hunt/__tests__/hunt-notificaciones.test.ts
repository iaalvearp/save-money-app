import { describe, it, expect, beforeAll, beforeEach, afterEach } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { hunt } from "../index";
import {
  generarCredencialesFcmDePrueba,
  interceptarFcm,
  type CredencialesFcm,
} from "../../../test-utils/fcm";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-hunt-notificaciones";

let credenciales: CredencialesFcm;

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/hunt", hunt);
  return app;
}

async function makeToken(sub: number, rol: string): Promise<string> {
  return sign(
    { sub: String(sub), rol, exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
  );
}

function fecha(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().replace("T", " ").slice(0, 19);
}

/** Ids sembrados: 1 organizador, 2..5 clientes, 6 admin. */
const ORGANIZADOR = 1;
const CLIENTE_APROBADO = 2;
const CLIENTE_PENDIENTE = 3;
const CLIENTE_RECHAZADO = 4;
const CLIENTE_SIN_TOKEN = 5;

let fcm: ReturnType<typeof interceptarFcm>;

beforeAll(async () => {
  credenciales = await generarCredencialesFcmDePrueba();

  await db.prepare(`CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rol TEXT NOT NULL CHECK (rol IN ('cliente','negocio','organizador','admin')),
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    nombre_completo TEXT NOT NULL,
    fecha_nacimiento TEXT,
    consentimiento_publicidad INTEGER,
    consentimiento_publicidad_fecha TEXT,
    fcm_token TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS eventos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    organizador_id INTEGER NOT NULL REFERENCES usuarios(id),
    nombre TEXT NOT NULL,
    fecha_inicio TEXT NOT NULL,
    fecha_fin TEXT NOT NULL,
    requiere_entrada INTEGER NOT NULL DEFAULT 0,
    precio_entrada REAL,
    estado TEXT NOT NULL DEFAULT 'programado' CHECK (estado IN ('programado','activo','finalizado')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS entradas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
    estado TEXT NOT NULL DEFAULT 'pendiente_pago' CHECK (estado IN ('pendiente_pago','pendiente_revision_comprobante','aprobada','rechazada')),
    comprobante_foto TEXT,
    monto REAL,
    revisado_por INTEGER REFERENCES usuarios(id),
    revisado_en TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS rondas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    nombre TEXT,
    hora_inicio TEXT NOT NULL,
    hora_fin TEXT NOT NULL
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS premios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    ronda_id INTEGER REFERENCES rondas(id),
    nombre TEXT NOT NULL,
    stock INTEGER NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('principal','consolacion','frecuencia')),
    criterio_frecuencia INTEGER
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS premios_entregados (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    premio_id INTEGER NOT NULL REFERENCES premios(id),
    usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
    ronda_id INTEGER REFERENCES rondas(id),
    estado TEXT NOT NULL DEFAULT 'entregado' CHECK (estado IN ('entregado','revocado')),
    entregado_en TEXT NOT NULL DEFAULT (datetime('now')),
    reclamado_en TEXT,
    UNIQUE (usuario_id, ronda_id)
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS puntos_evento (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    evento_id INTEGER NOT NULL REFERENCES eventos(id),
    usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
    puntos INTEGER NOT NULL DEFAULT 0,
    UNIQUE (evento_id, usuario_id)
  )`).run();

  await db.prepare(`CREATE TABLE IF NOT EXISTS configuraciones_sistema (
    clave TEXT PRIMARY KEY,
    valor TEXT NOT NULL,
    actualizado_en TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
  )`).run();

  await db.prepare(
    `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token) VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(ORGANIZADOR, "organizador", "organizador@notif.test", "hash", "Org", "token-organizador").run();
  await db.prepare(
    `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token) VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(CLIENTE_APROBADO, "cliente", "aprobado@notif.test", "hash", "Cliente Aprobado", "token-aprobado").run();
  await db.prepare(
    `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token) VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(CLIENTE_PENDIENTE, "cliente", "pendiente@notif.test", "hash", "Cliente Pendiente", "token-pendiente").run();
  await db.prepare(
    `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token) VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(CLIENTE_RECHAZADO, "cliente", "rechazado@notif.test", "hash", "Cliente Rechazado", "token-rechazado").run();
  await db.prepare(
    `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token) VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(CLIENTE_SIN_TOKEN, "cliente", "sintoken@notif.test", "hash", "Cliente Sin Token", null).run();
  await db.prepare(
    `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token) VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(6, "admin", "admin@notif.test", "hash", "Admin", "token-admin").run();
});

/** Crea un evento con una entrada por cliente, en el estado indicado. */
async function crearEventoConEntradas(
  estados: Record<number, string>
): Promise<number> {
  const res = await db
    .prepare(
      `INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin) VALUES (?, ?, ?, ?)`
    )
    .bind(ORGANIZADOR, "Hunt de prueba", fecha(1), fecha(3))
    .run();
  const eventoId = res.meta.last_row_id as number;

  for (const [clienteId, estado] of Object.entries(estados)) {
    await db
      .prepare(`INSERT INTO entradas (evento_id, cliente_id, estado) VALUES (?, ?, ?)`)
      .bind(eventoId, Number(clienteId), estado)
      .run();
  }
  return eventoId;
}

async function iniciarHunt(eventoId: number): Promise<Response> {
  const app = buildApp();
  const token = await makeToken(ORGANIZADOR, "organizador");
  return app.request(
    `/hunt/eventos/${eventoId}/iniciar`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    },
    { DB: db, JWT_SECRET, ...credenciales }
  );
}

beforeEach(async () => {
  fcm = interceptarFcm();
  // Comienza en el valor por defecto de la migración 0012.
  await db
    .prepare(
      `INSERT INTO configuraciones_sistema (clave, valor, actualizado_en)
       VALUES ('hunt_inicio_notificar_a', 'aprobados', CURRENT_TIMESTAMP)
       ON CONFLICT (clave) DO UPDATE SET valor = 'aprobados', actualizado_en = CURRENT_TIMESTAMP`
    )
    .run();
});

afterEach(() => {
  fcm.restaurar();
});

describe("POST /hunt/eventos/:id/iniciar - audiencia configurable", () => {
  it("con 'aprobados' notifica solo a quienes tienen entrada aprobada", async () => {
    const eventoId = await crearEventoConEntradas({
      [CLIENTE_APROBADO]: "aprobada",
      [CLIENTE_PENDIENTE]: "pendiente_revision_comprobante",
      [CLIENTE_RECHAZADO]: "rechazada",
    });

    const res = await iniciarHunt(eventoId);

    expect(res.status).toBe(200);
    const body = (await res.json()) as { audiencia: string; notificados: number };
    expect(body.audiencia).toBe("aprobados");
    expect(body.notificados).toBe(1);
    expect(fcm.envios).toHaveLength(1);
    expect(fcm.envios[0].token).toBe("token-aprobado");
    expect(fcm.envios[0].titulo).toContain("Hunt de prueba");
    expect(fcm.envios[0].data).toMatchObject({
      tipo: "hunt_inicio",
      evento_id: String(eventoId),
    });
  });

  it("con 'todos' notifica a todos los registrados, aprobados o no", async () => {
    const eventoId = await crearEventoConEntradas({
      [CLIENTE_APROBADO]: "aprobada",
      [CLIENTE_PENDIENTE]: "pendiente_revision_comprobante",
      [CLIENTE_RECHAZADO]: "rechazada",
    });
    await db
      .prepare(`UPDATE configuraciones_sistema SET valor = 'todos' WHERE clave = 'hunt_inicio_notificar_a'`)
      .run();

    const res = await iniciarHunt(eventoId);

    const body = (await res.json()) as { audiencia: string; notificados: number };
    expect(body.audiencia).toBe("todos");
    // 3 registrados con token; el cuarto (sin token FCM) se omite.
    expect(body.notificados).toBe(3);
    expect(fcm.envios.map((e) => e.token).sort()).toEqual([
      "token-aprobado",
      "token-pendiente",
      "token-rechazado",
    ]);
  });

  it("cambiar el valor en la base de datos cambia el comportamiento sin tocar código", async () => {
    const eventoId = await crearEventoConEntradas({
      [CLIENTE_APROBADO]: "aprobada",
      [CLIENTE_PENDIENTE]: "pendiente_revision_comprobante",
    });

    const conAprobados = await iniciarHunt(eventoId);
    expect(((await conAprobados.json()) as { notificados: number }).notificados).toBe(1);
    expect(fcm.envios).toHaveLength(1);

    // Solo se cambia el dato en la base, el código permanece igual.
    await db
      .prepare(`UPDATE configuraciones_sistema SET valor = 'todos' WHERE clave = 'hunt_inicio_notificar_a'`)
      .run();
    fcm.envios.length = 0;

    const conTodos = await iniciarHunt(eventoId);
    expect(((await conTodos.json()) as { notificados: number }).notificados).toBe(2);
    expect(fcm.envios).toHaveLength(2);
  });

  it("omite a los usuarios sin token FCM registrado", async () => {
    const eventoId = await crearEventoConEntradas({
      [CLIENTE_SIN_TOKEN]: "aprobada",
    });

    const res = await iniciarHunt(eventoId);

    expect(res.status).toBe(200);
    expect(((await res.json()) as { notificados: number }).notificados).toBe(0);
    expect(fcm.envios).toHaveLength(0);
  });

  it("marca el evento como activo", async () => {
    const eventoId = await crearEventoConEntradas({});

    await iniciarHunt(eventoId);

    const evento = await db
      .prepare("SELECT estado FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first<{ estado: string }>();
    expect(evento?.estado).toBe("activo");
  });

  it("no permite iniciar un evento de otro organizador", async () => {
    const eventoId = await crearEventoConEntradas({});
    const app = buildApp();
    const token = await makeToken(2, "organizador");

    const res = await app.request(
      `/hunt/eventos/${eventoId}/iniciar`,
      { method: "POST", headers: { Authorization: `Bearer ${token}` } },
      { DB: db, JWT_SECRET, ...credenciales }
    );

    expect(res.status).toBe(403);
    expect(fcm.envios).toHaveLength(0);
  });

  it("devuelve 404 si el evento no existe", async () => {
    const res = await iniciarHunt(999999);

    expect(res.status).toBe(404);
    expect(fcm.envios).toHaveLength(0);
  });
});
