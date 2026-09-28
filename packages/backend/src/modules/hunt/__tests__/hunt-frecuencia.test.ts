import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { hunt } from "../index";
import { contarComprasQueCuentan } from "../frecuencia";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-hunt-frecuencia";

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

/**
 * La hora del reloj de Ecuador, que es la que el backend da por supuesta en
 * las fechas sin zona. La prueba corre en UTC, asi que se resta el desfase para
 * poder construir fechas que signifiquen lo mismo en los dos sitios.
 */
function ahoraEnEcuador(): Date {
  return new Date(Date.now() - 5 * 60 * 60 * 1000);
}

/** Un momento como lo guarda la base, a partir de su fecha de Ecuador. */
function marca(objeto: Date): string {
  return objeto.toISOString().slice(0, 19).replace("T", " ");
}

/** Un momento de aqui a N minutos, escrito como lo guarda la base. */
function enMinutos(minutos: number): string {
  return marca(new Date(ahoraEnEcuador().getTime() + minutos * 60000));
}

/** El mismo momento, escrito como lo manda el SRI, con su zona. */
function comoIso(objeto: Date): string {
  return `${marca(objeto).replace(" ", "T")}-05:00`;
}

/** El mismo momento, escrito como lo escribiria el OCR. */
function comoDiaMesAnio(objeto: Date): string {
  const [a, m, d] = marca(objeto).slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
}

/** El mismo momento, escrito como la compra declarada a mano. */
function comoCorto(objeto: Date): string {
  const [a, m, d] = marca(objeto).slice(0, 10).split("-");
  return `${Number(d)}-${Number(m)}-${a.slice(2)}`;
}

/** Un instante concreto de la prueba, para escribirlo en varios formatos. */
function instante(minutos: number): Date {
  return new Date(ahoraEnEcuador().getTime() + minutos * 60000);
}

beforeAll(async () => {
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
      `CREATE TABLE IF NOT EXISTS eventos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organizador_id INTEGER NOT NULL REFERENCES usuarios(id),
        nombre TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL,
        requiere_entrada INTEGER NOT NULL DEFAULT 0,
        precio_entrada REAL,
        estado TEXT NOT NULL DEFAULT 'programado' CHECK (estado IN ('programado','activo','finalizado')),
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS rondas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        evento_id INTEGER NOT NULL REFERENCES eventos(id),
        nombre TEXT,
        hora_inicio TEXT NOT NULL,
        hora_fin TEXT NOT NULL
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS premios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        evento_id INTEGER NOT NULL REFERENCES eventos(id),
        ronda_id INTEGER REFERENCES rondas(id),
        nombre TEXT NOT NULL,
        stock INTEGER NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('principal','consolacion','frecuencia')),
        criterio_frecuencia INTEGER
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS premios_entregados (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        premio_id INTEGER NOT NULL REFERENCES premios(id),
        usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
        ronda_id INTEGER REFERENCES rondas(id),
        estado TEXT NOT NULL DEFAULT 'entregado' CHECK (estado IN ('entregado','revocado')),
        entregado_en TEXT NOT NULL DEFAULT (datetime('now')),
        reclamado_en TEXT,
        UNIQUE (usuario_id, ronda_id)
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS entradas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        evento_id INTEGER NOT NULL REFERENCES eventos(id),
        cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
        estado TEXT NOT NULL DEFAULT 'pendiente_pago' CHECK (estado IN ('pendiente_pago','pendiente_revision_comprobante','aprobada','rechazada')),
        comprobante_foto TEXT,
        monto REAL,
        revisado_por INTEGER REFERENCES usuarios(id),
        revisado_en TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS eventos_sponsors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        evento_id INTEGER NOT NULL REFERENCES eventos(id),
        comercio_id INTEGER NOT NULL REFERENCES comercios(id),
        estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aprobado','rechazado')),
        invited_at TEXT NOT NULL DEFAULT (datetime('now')),
        responded_at TEXT,
        UNIQUE (evento_id, comercio_id)
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS facturas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_id INTEGER NOT NULL REFERENCES usuarios(id),
        comercio_id INTEGER REFERENCES comercios(id),
        evento_id INTEGER REFERENCES eventos(id),
        nivel_verificacion INTEGER NOT NULL CHECK (nivel_verificacion IN (1,2,3)),
        clave_acceso_49 TEXT UNIQUE,
        numero_factura TEXT,
        ruc_emisor TEXT,
        nombre_comprador_factura TEXT,
        fecha_factura TEXT,
        monto_total REAL,
        descuento_aplicado REAL,
        cupon_id INTEGER,
        foto TEXT,
        estado TEXT NOT NULL DEFAULT 'aprobada' CHECK (estado IN (
          'aprobada',
          'pendiente_revision_nombre',
          'pendiente_verificacion_sri',
          'rechazada'
        )),
        motivo_rechazo TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        sri_estado_bruto TEXT
      )`
    )
    .run();

  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS puntos_evento (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        evento_id INTEGER NOT NULL REFERENCES eventos(id),
        usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
        puntos INTEGER NOT NULL DEFAULT 0,
        UNIQUE (evento_id, usuario_id)
      )`
    )
    .run();

  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("organizador", "org@frec.test", "hash", "Org")
    .run();
  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "cli@frec.test", "hash", "Cliente")
    .run();
  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("cliente", "otro@frec.test", "hash", "Otro Cliente")
    .run();
  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo) VALUES (?, ?, ?, ?)`
    )
    .bind("negocio", "neg@frec.test", "hash", "Negocio")
    .run();

  await db
    .prepare(`INSERT INTO comercios (usuario_id, nombre, categoria) VALUES (?, ?, ?)`)
    .bind(4, "Café Patrocinado", "Gastronomía")
    .run();
  await db
    .prepare(`INSERT INTO comercios (usuario_id, nombre, categoria) VALUES (?, ?, ?)`)
    .bind(4, "Tienda NO Patrocinada", "Tienda")
    .run();
});

/** Ids sembrados. */
const ORGANIZADOR = 1;
const CLIENTE = 2;
const OTRO_CLIENTE = 3;
const COMERCIO_PATROCINADO = 1;
const COMERCIO_NO_PATROCINADO = 2;

/**
 * Monta el escenario: un evento que empieza manana y dura hasta pasado manana,
 * con una ronda por la mitad, y devuelve los ids de lo creado.
 */
async function escenario() {
  // El evento esta abierto ahora, con una ronda mas estrecha tambien abierta.
  // Asi el reclamo no se rechaza por horario y las pruebas dicen algo sobre la
  // frecuencia y no sobre la hora del reloj.
  const eventoRes = await db
    .prepare(
      `INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
       VALUES (?, ?, ?, ?)`
    )
    .bind(ORGANIZADOR, "Evento Frecuencia", enMinutos(-60), enMinutos(60))
    .run();
  const eventoId = eventoRes.meta.last_row_id;

  const rondaRes = await db
    .prepare(
      `INSERT INTO rondas (evento_id, nombre, hora_inicio, hora_fin)
       VALUES (?, ?, ?, ?)`
    )
    .bind(eventoId, "Ronda 1", enMinutos(-30), enMinutos(30))
    .run();

  return { eventoId, rondaId: rondaRes.meta.last_row_id };
}

/** Medianoche de Ecuador del dia que esta a N dias de hoy. */
function medianoche(deDias: number): string {
  const base = ahoraEnEcuador();
  return marca(
    new Date(
      Date.UTC(
        base.getUTCFullYear(),
        base.getUTCMonth(),
        base.getUTCDate() + deDias
      )
    )
  );
}

/**
 * Un evento que cubre dias enteros, para las pruebas donde lo que importa es
 * el dia y no la hora. Hace falta porque una fecha sin hora significa
 * medianoche, que caeria fuera de una ventana de minutos.
 */
async function escenarioAncha(): Promise<number> {
  const res = await db
    .prepare(
      `INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
       VALUES (?, ?, ?, ?)`
    )
    .bind(ORGANIZADOR, "Evento Ancho", medianoche(-3), `${medianoche(3).slice(0, 10)} 23:59:59`)
    .run();
  return res.meta.last_row_id;
}

/** Registra una compra. Sin fecha si no se pasa, para poder probar ese caso. */
async function compra(
  clienteId: number,
  comercioId: number,
  fecha: string | null,
  estado = "aprobada"
) {
  await db
    .prepare(
      `INSERT INTO facturas (cliente_id, comercio_id, nivel_verificacion, fecha_factura, estado)
       VALUES (?, ?, 1, ?, ?)`
    )
    .bind(clienteId, comercioId, fecha, estado)
    .run();
}

/** Registra al comercio como patrocinador del evento. */
async function patrocinar(eventoId: number, estado = "aprobado") {
  await db
    .prepare(
      `INSERT INTO eventos_sponsors (evento_id, comercio_id, estado) VALUES (?, ?, ?)`
    )
    .bind(eventoId, COMERCIO_PATROCINADO, estado)
    .run();
}

/** Crea un premio de frecuencia con su numero de compras. */
async function premioFrecuencia(
  eventoId: number,
  criterio: number,
  rondaId: number | null = null
): Promise<number> {
  const res = await db
    .prepare(
      `INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo, criterio_frecuencia)
       VALUES (?, ?, ?, 10, 'frecuencia', ?)`
    )
    .bind(eventoId, rondaId, "Camiseta", criterio)
    .run();
  return res.meta.last_row_id;
}

/** Cuenta directamente, sin pasar por la API. */
function contar(clienteId: number, premio: {
  evento_id: number;
  ronda_id: number | null;
  criterio_frecuencia: number | null;
}) {
  return contarComprasQueCuentan(db, clienteId, {
    id: 1,
    tipo: "frecuencia",
    ...premio,
  });
}

describe("contar compras que cuentan", () => {
  it("cuenta las compras aprobadas en un comercio patrocinador", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-10));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 2,
    });

    expect(conteo.compras).toBe(2);
    expect(conteo.cumple).toBe(true);
  });

  it("no cuenta compras en un comercio que no patrocina el evento", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_NO_PATROCINADO, enMinutos(-20));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 1,
    });

    expect(conteo.compras).toBe(0);
  });

  it("no cuenta compras de un patrocinador que no ha aprobado", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId, "pendiente");
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 1,
    });

    expect(conteo.compras).toBe(0);
  });

  it("no cuenta compras que no estan aprobadas", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(
      CLIENTE,
      COMERCIO_PATROCINADO,
      enMinutos(-20),
      "rechazada"
    );
    await compra(
      CLIENTE,
      COMERCIO_PATROCINADO,
      enMinutos(-15),
      "pendiente_revision_nombre"
    );

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 2,
    });

    expect(conteo.compras).toBe(0);
  });

  it("solo cuenta las compras de quien pregunta", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));
    await compra(OTRO_CLIENTE, COMERCIO_PATROCINADO, enMinutos(-15));
    await compra(OTRO_CLIENTE, COMERCIO_PATROCINADO, enMinutos(-10));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 5,
    });

    expect(conteo.compras).toBe(1);
    expect(conteo.cumple).toBe(false);
  });

  it("lee igual las cuatro formas de escribir la fecha", async () => {
    const eventoId = await escenarioAncha();
    await patrocinar(eventoId);

    // Los cuatro formatos que llegan de verdad. Todos son el mismo momento
    // aproximado, asi que la ventana es ancha a proposito: lo que se prueba es
    // que se lean bien, no que la fecha caiga dentro.
    const referencia = instante(-20);
    await compra(CLIENTE, COMERCIO_PATROCINADO, comoIso(referencia));
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-19));
    await compra(CLIENTE, COMERCIO_PATROCINADO, comoDiaMesAnio(instante(0)));
    await compra(CLIENTE, COMERCIO_PATROCINADO, comoCorto(instante(0)));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 4,
    });

    // Comparadas como texto, estas cuatro fechas estan en desorden unas
    // respecto a otras y el conteo daria un numero distinto.
    expect(conteo.compras).toBe(4);
    expect(conteo.cumple).toBe(true);
  });

  it("una compra de antes del evento no cuenta aunque su texto parezca mayor", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);

    // El evento abrio hace una hora. Esta compra es de hace dos horas, o sea
    // de antes, pero el formato corto la escribe como un dia de dos digitos
    // frente a una fecha de cuatro: como texto, el dia corto parece posterior.
    await compra(CLIENTE, COMERCIO_PATROCINADO, comoCorto(instante(-120)));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 1,
    });

    expect(conteo.compras).toBe(0);
  });

  it("una compra sin fecha no cuenta, pero no rompe el conteo", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, null);
    await compra(CLIENTE, COMERCIO_PATROCINADO, "");
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 1,
    });

    expect(conteo.compras).toBe(1);
    // Se informa de las que no se pudieron leer, para que no sean invisibles.
    expect(conteo.sin_fecha_legible).toBe(2);
  });

  it("usa las horas de la ronda cuando el premio es de una ronda", async () => {
    const { eventoId, rondaId } = await escenario();
    await patrocinar(eventoId);

    // Dentro del evento pero antes de que abra la ronda.
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-45));
    // Dentro de la ronda.
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-10));
    // Dentro del evento pero despues de que cierre la ronda.
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(45));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: rondaId,
      criterio_frecuencia: 1,
    });

    // La ventana es la ronda, no el evento entero.
    expect(conteo.compras).toBe(1);
    expect(conteo.ventana).toContain("Ronda 1");
  });

  it("usa el evento entero cuando el premio no es de una ronda", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-50));
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(50));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 2,
    });

    expect(conteo.compras).toBe(2);
    expect(conteo.ventana).toContain("evento");
  });

  it("devuelve cero si la ventana del premio no se puede leer", async () => {
    const eventoRes = await db
      .prepare(
        `INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
         VALUES (?, ?, ?, ?)`
      )
      .bind(ORGANIZADOR, "Evento Roto", "no es fecha", "tampoco")
      .run();
    const eventoId = eventoRes.meta.last_row_id;
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));

    const conteo = await contar(CLIENTE, {
      evento_id: eventoId,
      ronda_id: null,
      criterio_frecuencia: 1,
    });

    // Antes de contar no se puede decir nada. Un numero inventado haria que
    // alguien perdiera un premio que si cumple.
    expect(conteo.compras).toBe(0);
    expect(conteo.cumple).toBe(false);
    expect(conteo.ventana).toBe("");
  });
});

describe("GET /hunt/eventos/:eventoId/premios/:premioId/progreso", () => {
  it("dice cuantas compras faltan", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));
    const premioId = await premioFrecuencia(eventoId, 3);

    const res = await buildApp().request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/progreso`,
      {
        headers: { Authorization: `Bearer ${await makeToken(CLIENTE, "cliente")}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
    const cuerpo = (await res.json()) as {
      compras: number;
      criterio: number;
      faltan: number;
      cumple: boolean;
    };
    expect(cuerpo.compras).toBe(1);
    expect(cuerpo.criterio).toBe(3);
    expect(cuerpo.faltan).toBe(2);
    expect(cuerpo.cumple).toBe(false);
  });

  it("se puede ver el progreso sin tener entrada aprobada", async () => {
    // Ver el progreso es solo informacion. Exigir entrada para verlo dejaria a
    // la gente sin saber cuantas compras le faltan.
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));
    const premioId = await premioFrecuencia(eventoId, 1);

    const res = await buildApp().request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/progreso`,
      {
        headers: { Authorization: `Bearer ${await makeToken(CLIENTE, "cliente")}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(200);
  });

  it("avisa si el premio no tiene criterio configurado", async () => {
    const { eventoId } = await escenario();
    const res = await db
      .prepare(
        `INSERT INTO premios (evento_id, nombre, stock, tipo) VALUES (?, ?, 5, 'frecuencia')`
      )
      .bind(eventoId, "Sin criterio")
      .run();

    const progreso = await buildApp().request(
      `/hunt/eventos/${eventoId}/premios/${res.meta.last_row_id}/progreso`,
      {
        headers: { Authorization: `Bearer ${await makeToken(CLIENTE, "cliente")}` },
      },
      { DB: db, JWT_SECRET }
    );

    // Un cero a secas haria pensar que no ha comprado nada.
    expect(progreso.status).toBe(422);
  });

  it("da 404 si el premio no pertenece al evento", async () => {
    const { eventoId } = await escenario();
    const otro = await escenario();
    const premioId = await premioFrecuencia(eventoId, 1);

    const res = await buildApp().request(
      `/hunt/eventos/${otro.eventoId}/premios/${premioId}/progreso`,
      {
        headers: { Authorization: `Bearer ${await makeToken(CLIENTE, "cliente")}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(404);
  });
});

describe("reclamar un premio de frecuencia", () => {
  it("rechaza el reclamo si faltan compras y dice cuantas", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));
    const premioId = await premioFrecuencia(eventoId, 3);

    const res = await buildApp().request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${await makeToken(CLIENTE, "cliente")}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
    const cuerpo = (await res.json()) as { faltan: number };
    // El mensaje dice cuantas le faltan, no solo que no puede.
    expect(cuerpo.faltan).toBe(2);
  });

  it("deja reclamar cuando ya cumple el criterio", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));
    await compra(CLIENTE, COMERCIO_PATROCINADO, enMinutos(-10));
    const premioId = await premioFrecuencia(eventoId, 2);

    const res = await buildApp().request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${await makeToken(CLIENTE, "cliente")}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(201);
  });

  it("no deja reclamar con compras de otro cliente", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    await compra(OTRO_CLIENTE, COMERCIO_PATROCINADO, enMinutos(-20));
    await compra(OTRO_CLIENTE, COMERCIO_PATROCINADO, enMinutos(-10));
    const premioId = await premioFrecuencia(eventoId, 2);

    const res = await buildApp().request(
      `/hunt/eventos/${eventoId}/premios/${premioId}/reclamar`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${await makeToken(CLIENTE, "cliente")}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(res.status).toBe(422);
  });

  it("un premio que no es de frecuencia se reclama sin mirar compras", async () => {
    const { eventoId } = await escenario();
    await patrocinar(eventoId);
    const res = await db
      .prepare(
        `INSERT INTO premios (evento_id, nombre, stock, tipo) VALUES (?, ?, 5, 'consolacion')`
      )
      .bind(eventoId, "Consolación")
      .run();

    const reclamo = await buildApp().request(
      `/hunt/eventos/${eventoId}/premios/${res.meta.last_row_id}/reclamar`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${await makeToken(CLIENTE, "cliente")}` },
      },
      { DB: db, JWT_SECRET }
    );

    expect(reclamo.status).toBe(201);
  });
});
