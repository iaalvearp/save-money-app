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
 * Genera un par de claves RSA válido para que `enviarNotificacion` pueda firmar
 * de verdad el JWT de OAuth2. No se usan secretos reales.
 */
export async function generarCredencialesFcmDePrueba(): Promise<CredencialesFcm> {
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
  const lineas = base64.match(/.{1,64}/g) ?? [];

  return {
    FCM_CLIENT_EMAIL:
      "firebase-adminsdk-pruebas@save-money-pruebas.iam.gserviceaccount.com",
    FCM_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${lineas.join("\n")}\n-----END PRIVATE KEY-----\n`,
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
