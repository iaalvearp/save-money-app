import { describe, it } from "vitest";

async function derivePbkdf2(
  password: string,
  salt: Uint8Array,
  iterations: number
): Promise<ArrayBuffer> {
  const encoder = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    encoder.encode(password),
    "PBKDF2",
    false,
    ["deriveBits"]
  );
  return crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt,
      iterations,
    },
    keyMaterial,
    256
  );
}

describe("PBKDF2 benchmark", () => {
  it("measure all iteration counts sequentially", async () => {
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const password = "test-password-benchmark";
    const counts = [5_000, 10_000, 15_000, 20_000];

    // extensive warmup
    for (let i = 0; i < 10; i++) {
      await derivePbkdf2(password, salt, 1_000);
    }

    for (const count of counts) {
      const times: number[] = [];
      for (let r = 0; r < 10; r++) {
        const start = performance.now();
        await derivePbkdf2(password, salt, count);
        const end = performance.now();
        times.push(end - start);
      }
      times.sort((a, b) => a - b);
      // Take median (middle of sorted)
      const median = times[Math.floor(times.length / 2)];
      // Take p95 (95th percentile)
      const p95 = times[Math.floor(times.length * 0.95)];
      const avg = times.reduce((a, b) => a + b, 0) / times.length;
      console.log(`${count.toLocaleString()} iterations: avg=${avg.toFixed(2)}ms median=${median.toFixed(2)}ms p95=${p95.toFixed(2)}ms min=${times[0].toFixed(2)}ms max=${times[times.length - 1].toFixed(2)}ms`);
    }
  });
});
