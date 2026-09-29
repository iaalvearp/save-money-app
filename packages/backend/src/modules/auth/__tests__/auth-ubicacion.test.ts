import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "../index";
import {
  generarCredencialesFcmDePrueba,
  interceptarFcm,
  credencialesFcmQueFallan,
  type CredencialesFcm,
} from "../../../test-utils/fcm";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-ubicacion";

let credenciales: CredencialesFcm;

// Quito (Santiago). Se usa una zona urbana pequeña para que los radios de 1 km
// sean deterministas con las distancias de prueba.
const LAT_QUITO = -0.1807;
const LNG_QUITO = -78.4678;

const USUARIO_CON_TOKEN = 1;
const USUARIO_SIN_TOKEN = 2;
const USUARIO_NEGOCIO = 3;

let fcm: ReturnType<typeof interceptarFcm>;

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/auth", auth);
  return app;
}

async function makeToken(sub: number, rol: string): Promise<string> {
  return sign(
    { sub: String(sub), rol, exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
  );
}

async function reportarUbicacion(
  lat: number | string,
  lng: number | string,
  usuarioId = USUARIO_CON_TOKEN
): Promise<Response> {
  const app = buildApp();
  const token = await makeToken(usuarioId, "cliente");
  return app.request(
    "/auth/ubicacion",
    {
      method: "PUT",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ latitud: lat, longitud: lng }),
    },
    { DB: db, JWT_SECRET, ...credenciales }
  );
}

async function crearPromocion(
  lat: number | null,
  lng: number | null,
  radioKm = 1,
  activa = true
): Promise<number> {
  const res = await db
    .prepare(
      `INSERT INTO comercios (usuario_id, nombre, categoria) VALUES (?, ?, ?)`
    )
    .bind(USUARIO_NEGOCIO, `Comercio ${Math.random().toString(36).slice(2, 8)}`, "Gastronomía")
    .run();
  const comercioId = res.meta.last_row_id as number;

  const promo = await db
    .prepare(
      `INSERT INTO promociones_flash
         (comercio_id, titulo, descuento_porcentaje, inicia_en, termina_en, latitud, longitud, radio_km)
       VALUES (?, ?, 20, ?, ?, ?, ?, ?)`
    )
    .bind(
      comercioId,
      "Promo de prueba",
      activa ? "2020-01-01 00:00:00" : "2099-01-01 00:00:00",
      activa ? "2099-01-01 00:00:00" : "2099-01-02 00:00:00",
      lat,
      lng,
      radioKm
    )
    .run();

  return promo.meta.last_row_id as number;
}

beforeAll(async () => {
  credenciales = await generarCredencialesFcmDePrueba();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rol TEXT NOT NULL CHECK (rol IN ('cliente','negocio','organizador','admin')),
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        nombre_completo TEXT NOT NULL,
        fecha_nacimiento TEXT,
        consentimiento_publicidad INTEGER,
        consentimiento_publicidad_fecha TEXT,
        fcm_token TEXT,
        fcm_token_updated_at TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS comercios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
        nombre TEXT NOT NULL,
        categoria TEXT,
        ruc TEXT,
        latitud REAL,
        longitud REAL,
        es_patrocinado INTEGER NOT NULL DEFAULT 0,
        horario TEXT,
        foto_url TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS promociones_flash (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        comercio_id INTEGER NOT NULL REFERENCES comercios(id),
        titulo TEXT NOT NULL,
        descripcion TEXT,
        descuento_porcentaje REAL NOT NULL,
        inicia_en TEXT NOT NULL,
        termina_en TEXT NOT NULL,
        latitud REAL,
        longitud REAL,
        radio_km REAL DEFAULT 5,
        categoria TEXT,
        max_usuarios INTEGER,
        usuarios_notificados INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS ubicaciones_usuarios (
        usuario_id INTEGER PRIMARY KEY REFERENCES usuarios(id),
        latitud REAL NOT NULL,
        longitud REAL NOT NULL,
        actualizado_en TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS flash_notificaciones_enviadas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
        promocion_id INTEGER NOT NULL REFERENCES promociones_flash(id),
        enviado_en TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (usuario_id, promocion_id)
      )`
    )
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token)
       VALUES (?, 'cliente', 'con-token@ubic.test', 'hash', 'Con Token', 'token-cerca')`
    )
    .bind(USUARIO_CON_TOKEN)
    .run();
  await db
    .prepare(
      `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token)
       VALUES (?, 'cliente', 'sin-token@ubic.test', 'hash', 'Sin Token', NULL)`
    )
    .bind(USUARIO_SIN_TOKEN)
    .run();
  await db
    .prepare(
      `INSERT INTO usuarios (id, rol, email, password_hash, nombre_completo, fcm_token)
       VALUES (?, 'negocio', 'negocio@ubic.test', 'hash', 'Negocio', 'token-negocio')`
    )
    .bind(USUARIO_NEGOCIO)
    .run();
});

beforeEach(async () => {
  fcm = interceptarFcm();
  await db.prepare("DELETE FROM flash_notificaciones_enviadas").run();
  await db.prepare("DELETE FROM ubicaciones_usuarios").run();
  await db.prepare("DELETE FROM promociones_flash").run();
  await db.prepare("DELETE FROM comercios").run();
});

afterEach(() => {
  fcm.restaurar();
});

describe("PUT /auth/ubicacion - Flash por cercanía", () => {
  it("guarda la última posición del usuario", async () => {
    await reportarUbicacion(LAT_QUITO, LNG_QUITO);

    const fila = await db
      .prepare("SELECT latitud, longitud FROM ubicaciones_usuarios WHERE usuario_id = ?")
      .bind(USUARIO_CON_TOKEN)
      .first<{ latitud: number; longitud: number }>();
    expect(fila?.latitud).toBeCloseTo(LAT_QUITO, 5);
    expect(fila?.longitud).toBeCloseTo(LNG_QUITO, 5);
  });

  it("actualiza la posición si el usuario ya había reportado antes", async () => {
    await reportarUbicacion(LAT_QUITO, LNG_QUITO);
    await reportarUbicacion(LAT_QUITO + 0.01, LNG_QUITO + 0.01);

    const filas = await db
      .prepare("SELECT latitud FROM ubicaciones_usuarios WHERE usuario_id = ?")
      .bind(USUARIO_CON_TOKEN)
      .all<{ latitud: number }>();
    expect(filas.results).toHaveLength(1);
    expect(filas.results?.[0].latitud).toBeCloseTo(LAT_QUITO + 0.01, 5);
  });

  it("primera vez: notifica la promoción cercana y guarda el registro", async () => {
    const promoId = await crearPromocion(LAT_QUITO + 0.001, LNG_QUITO, 1);

    const res = await reportarUbicacion(LAT_QUITO, LNG_QUITO);

    expect(res.status).toBe(200);
    expect(((await res.json()) as { notificadas: number }).notificadas).toBe(1);

    expect(fcm.envios).toHaveLength(1);
    expect(fcm.envios[0].token).toBe("token-cerca");
    expect(fcm.envios[0].titulo).toContain("Promo de prueba");
    expect(fcm.envios[0].data).toMatchObject({
      tipo: "flash_cercania",
      promocion_id: String(promoId),
    });

    const registro = await db
      .prepare(
        "SELECT usuario_id, promocion_id FROM flash_notificaciones_enviadas WHERE usuario_id = ?"
      )
      .bind(USUARIO_CON_TOKEN)
      .first<{ usuario_id: number; promocion_id: number }>();
    expect(registro?.usuario_id).toBe(USUARIO_CON_TOKEN);
    expect(registro?.promocion_id).toBe(promoId);
  });

  it("segunda vez para la misma combinación: NO vuelve a notificar", async () => {
    await crearPromocion(LAT_QUITO + 0.001, LNG_QUITO, 1);

    await reportarUbicacion(LAT_QUITO, LNG_QUITO);
    expect(fcm.envios).toHaveLength(1);

    // El usuario sale del radio y vuelve a entrar varias veces.
    fcm.envios.length = 0;
    await reportarUbicacion(LAT_QUITO + 0.5, LNG_QUITO);
    await reportarUbicacion(LAT_QUITO, LNG_QUITO);
    await reportarUbicacion(LAT_QUITO, LNG_QUITO);

    expect(fcm.envios).toHaveLength(0);
    const total = await db
      .prepare("SELECT COUNT(*) AS n FROM flash_notificaciones_enviadas")
      .first<{ n: number }>();
    expect(total?.n).toBe(1);
  });

  it("sí notifica de nuevo si es otra promoción distinta", async () => {
    await crearPromocion(LAT_QUITO + 0.001, LNG_QUITO, 1);
    await crearPromocion(LAT_QUITO - 0.001, LNG_QUITO, 1);

    await reportarUbicacion(LAT_QUITO, LNG_QUITO);
    expect(fcm.envios).toHaveLength(2);
  });

  it("no notifica promociones fuera del radio configurado", async () => {
    // ~2.2 km de distancia con un radio de 1 km.
    await crearPromocion(LAT_QUITO + 0.02, LNG_QUITO, 1);

    const res = await reportarUbicacion(LAT_QUITO, LNG_QUITO);

    expect(((await res.json()) as { notificadas: number }).notificadas).toBe(0);
    expect(fcm.envios).toHaveLength(0);
  });

  it("respeta el radio propio de cada promoción", async () => {
    // Misma distancia, radios distintos: solo entra la que tiene radio amplio.
    await crearPromocion(LAT_QUITO + 0.02, LNG_QUITO, 1);
    await crearPromocion(LAT_QUITO + 0.02, LNG_QUITO, 5);

    const res = await reportarUbicacion(LAT_QUITO, LNG_QUITO);

    expect(((await res.json()) as { notificadas: number }).notificadas).toBe(1);
    expect(fcm.envios).toHaveLength(1);
  });

  it("ignora promociones que no están activas", async () => {
    await crearPromocion(LAT_QUITO + 0.001, LNG_QUITO, 1, false);

    const res = await reportarUbicacion(LAT_QUITO, LNG_QUITO);

    expect(((await res.json()) as { notificadas: number }).notificadas).toBe(0);
    expect(fcm.envios).toHaveLength(0);
  });

  it("ignora promociones sin coordenadas", async () => {
    await crearPromocion(null, null, 1);

    const res = await reportarUbicacion(LAT_QUITO, LNG_QUITO);

    expect(((await res.json()) as { notificadas: number }).notificadas).toBe(0);
    expect(fcm.envios).toHaveLength(0);
  });

  it("registra la notificación aunque el usuario no tenga token FCM, y no repite", async () => {
    await crearPromocion(LAT_QUITO + 0.001, LNG_QUITO, 1);

    const res = await reportarUbicacion(LAT_QUITO, LNG_QUITO, USUARIO_SIN_TOKEN);

    expect(res.status).toBe(200);
    expect(fcm.envios).toHaveLength(0);

    const registro = await db
      .prepare("SELECT COUNT(*) AS n FROM flash_notificaciones_enviadas WHERE usuario_id = ?")
      .bind(USUARIO_SIN_TOKEN)
      .first<{ n: number }>();
    expect(registro?.n).toBe(1);
  });

  it("rechaza coordenadas inválidas o fuera de rango", async () => {
    const noNumerico = await reportarUbicacion("abc", LNG_QUITO);
    expect(noNumerico.status).toBe(400);

    const fueraDeRango = await reportarUbicacion(120, LNG_QUITO);
    expect(fueraDeRango.status).toBe(400);

    expect(fcm.envios).toHaveLength(0);
  });

  it("requiere autenticación", async () => {
    const app = buildApp();
    const res = await app.request(
      "/auth/ubicacion",
      {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ latitud: LAT_QUITO, longitud: LNG_QUITO }),
      },
      { DB: db, JWT_SECRET, ...credenciales }
    );

    expect(res.status).toBe(401);
    expect(fcm.envios).toHaveLength(0);
  });
});

/**
 * Reportar la ubicacion guarda la posicion y lanza los avisos de Flash. Si el
 * push falla, la posicion ya quedo guardada: eso es lo que fija esta prueba.
 */
describe("PUT /auth/ubicacion - un push de Flash caido", () => {
  it("guarda la posicion y responde 200 aunque no se pueda notificar", async () => {
    const promoId = await crearPromocion(LAT_QUITO + 0.001, LNG_QUITO, 1);

    const app = buildApp();
    const token = await makeToken(USUARIO_CON_TOKEN, "cliente");
    const errores = vi.spyOn(console, "error").mockImplementation(() => {});

    const res = await app.request(
      "/auth/ubicacion",
      {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ latitud: LAT_QUITO, longitud: LNG_QUITO }),
      },
      { DB: db, JWT_SECRET, ...credencialesFcmQueFallan() }
    );
    errores.mockRestore();

    expect(res.status).toBe(200);
    expect(((await res.json()) as { ok: boolean; notificadas: number }).notificadas).toBe(0);

    const fila = await db
      .prepare("SELECT latitud FROM ubicaciones_usuarios WHERE usuario_id = ?")
      .bind(USUARIO_CON_TOKEN)
      .first<{ latitud: number }>();
    expect(fila?.latitud).toBeCloseTo(LAT_QUITO, 5);

    // La promocion se marco como notificada antes de intentar el envio: sin el
    // aviso no se reintenta en el siguiente reporte de ubicacion.
    const marcas = await db
      .prepare("SELECT usuario_id FROM flash_notificaciones_enviadas WHERE promocion_id = ?")
      .bind(promoId)
      .all<{ usuario_id: number }>();
    expect(marcas.results).toHaveLength(1);
  });
});
