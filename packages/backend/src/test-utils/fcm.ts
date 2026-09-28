const TOKEN_URL = "https://oauth2.googleapis.com/token";

export type EnvioFcmCapturado = {
  token: string;
  titulo: string;
  cuerpo: string;
  data?: Record<string, string>;
};

export type CredencialesFcm = {
  FCM_CLIENT_EMAIL: string;
  FCM_PRIVATE_KEY: string;
};

/**
 * Genera una clave privada RSA de prueba y devuelve su cuerpo en base64, ya
 * partido en líneas de 64 caracteres como manda el formato PEM. Se separa de
 * las credenciales para poder probar los distintos formatos en que la clave
 * puede llegar guardada. Nunca se usan secretos reales.
 */
export async function generarClavePrivadaBase64DePrueba(): Promise<string[]> {
  const par = (await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"]
  )) as CryptoKeyPair;

  const pkcs8 = new Uint8Array(
    (await crypto.subtle.exportKey("pkcs8", par.privateKey)) as ArrayBuffer
  );
  let binario = "";
  for (const byte of pkcs8) {
    binario += String.fromCharCode(byte);
  }
  const base64 = btoa(binario);
  return base64.match(/.{1,64}/g) ?? [];
}

/**
 * Genera un par de claves RSA válido para que `enviarNotificacion` pueda firmar
 * de verdad el JWT de OAuth2. No se usan secretos reales.
 */
export async function generarCredencialesFcmDePrueba(): Promise<CredencialesFcm> {
  const lineas = await generarClavePrivadaBase64DePrueba();

  return {
    FCM_CLIENT_EMAIL:
      "firebase-adminsdk-pruebas@save-money-pruebas.iam.gserviceaccount.com",
    FCM_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${lineas.join("\n")}\n-----END PRIVATE KEY-----\n`,
  };
}

/**
 * Credenciales con una clave que no es una clave. Sirve para comprobar que un
 * fallo de Firebase no rompe la acción que dispara la notificación: el texto
 * es base64 válido (para que no dependa de cómo se lea la clave) pero
 * `importKey` lo rechaza, que es exactamente lo que hace `enviarNotificacion`.
 */
export function credencialesFcmQueFallan(): CredencialesFcm {
  return {
    FCM_CLIENT_EMAIL:
      "firebase-adminsdk-pruebas@save-money-pruebas.iam.gserviceaccount.com",
    FCM_PRIVATE_KEY: "aGVsbG8gdGhpcyBub3QgaXMgYSBrZXk=",
  };
}

/**
 * Intercepta las llamadas salientes a FCM y registra los mensajes realmente
 * enviados (token del dispositivo + payload), sin salir a internet.
 * Devuelve los envíos capturados y un `restaurar` para devolver `fetch`.
 */
export function interceptarFcm(): {
  envios: EnvioFcmCapturado[];
  restaurar: () => void;
} {
  const envios: EnvioFcmCapturado[] = [];
  const original = globalThis.fetch;

  globalThis.fetch = (async (
    input: RequestInfo | URL,
    init?: RequestInit
  ): Promise<Response> => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;

    if (url === TOKEN_URL) {
      return new Response(JSON.stringify({ access_token: "access-token-de-prueba" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (url.includes("messages:send")) {
      const cuerpo = JSON.parse(String(init?.body)) as {
        message: {
          token: string;
          notification: { title: string; body: string };
          data?: Record<string, string>;
        };
      };
      envios.push({
        token: cuerpo.message.token,
        titulo: cuerpo.message.notification.title,
        cuerpo: cuerpo.message.notification.body,
        data: cuerpo.message.data,
      });
      return new Response(JSON.stringify({ name: "projects/pruebas/messages/1" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    return original(input, init);
  }) as typeof fetch;

  return {
    envios,
    restaurar: () => {
      globalThis.fetch = original;
    },
  };
}
