import type { App, Identity, State } from "./engine";
const enc = new TextEncoder();
export async function signedText(
  req: Request,
  body: string,
  publicOrigin?: string,
) {
  const hash = new Uint8Array(
    await crypto.subtle.digest("SHA-256", enc.encode(body)),
  );
  const url = new URL(req.url);
  const target = publicOrigin
    ? publicOrigin + url.pathname + url.search
    : req.url;
  const h = (n: string) => req.headers.get(`x-badge-${n}`) ?? "";
  return [
    "badge-http-v1",
    req.method,
    target,
    [...hash].map((b) => b.toString(16).padStart(2, "0")).join(""),
    h("app"),
    h("id"),
    h("user"),
    h("time"),
    h("request"),
  ].join("\n");
}
export class Verifier {
  keys = new Map<string, CryptoKey>();
  lastFetch = -Infinity;
  constructor(
    public state: State,
    public options: {
      now?: () => number;
      publicOrigin?: string;
      fetchKey?: (signal: AbortSignal) => Promise<{ id: string; key: string }>;
    } = {},
  ) {}
  async verify(req: Request, body: string): Promise<Identity | null> {
    const h = (n: string) => req.headers.get(`x-badge-${n}`) ?? "",
      now = (this.options.now ?? Date.now)(),
      time = Number(h("time")),
      nonce = h("request");
    if (
      !["range-lazarus", "range-defenders"].includes(h("app")) ||
      !Number.isFinite(time) ||
      Math.abs(now - time) >= 60000 ||
      !/^[a-zA-Z0-9_-]{8,80}$/.test(nonce) ||
      this.state.nonces[nonce] !== undefined ||
      !h("id") ||
      h("id").length > 32 ||
      !h("user") ||
      h("user").length > 80
    )
      return null;
    let key = this.keys.get(h("key"));
    if (!key && now - this.lastFetch > 60000) {
      const signal = AbortSignal.timeout(2000);
      try {
        const fetchKey = this.options.fetchKey ?? (async (signal: AbortSignal) => {
          const r = await fetch("https://solana.com/breakpoint/badge/api/http/key", { signal });
          if (!r.ok) throw Error("key_unavailable");
          return r.json();
        });
        const k = await Promise.race([
          fetchKey(signal),
          new Promise<never>((_, reject) => signal.addEventListener("abort", () => reject(Error("key_timeout")), { once: true })),
        ]);
        const imported = await crypto.subtle.importKey("raw", Uint8Array.from(atob(k.key), c => c.charCodeAt(0)), "Ed25519", false, ["verify"]);
        this.keys.set(k.id, imported);
        this.lastFetch = now;
      } catch { return null; }
      key = this.keys.get(h("key"));
    }
    if (!key) return null;
    try {
      const sig = Uint8Array.from(atob(h("signature")), (c) => c.charCodeAt(0));
      if (
        !(await crypto.subtle.verify(
          "Ed25519",
          key,
          sig,
          enc.encode(await signedText(req, body, this.options.publicOrigin)),
        ))
      )
        return null;
    } catch {
      return null;
    }
    // Check again after async crypto: concurrent replay must not pass twice.
    if (this.state.nonces[nonce] !== undefined) return null;
    this.state.nonces[nonce] = time;
    return {
      ns: "prod",
      badge: h("id"),
      user: h("user"),
      app: h("app").slice(6) as App,
    };
  }
}
