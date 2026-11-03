import { Engine, RuleError, ascii, type App, type Identity } from "./engine";
import { Verifier } from "./auth";
import type { Store } from "./storage";
import type { Escrow } from "./escrow";
import { live, resultPage } from "./pages";
export class API {
  queue: Promise<unknown> = Promise.resolve();
  constructor(
    public engine: Engine,
    public store: Store,
    public verifier: Verifier,
    public options: {
      demo?: boolean;
      publicOrigin?: string;
      shortOrigin?: string;
      escrow?: Escrow;
    } = {},
  ) {}
  handle(req: Request): Promise<Response> {
    const response = this.queue.then(() => this.route(req));
    this.queue = response.catch(() => {});
    return response;
  }
  async flush() {
    await this.store.save(this.engine.state);
    if (!this.options.escrow) return;
    for (const p of Object.values(this.engine.state.payouts))
      if (p.state === "pending") {
        p.attempts++;
        await this.store.save(this.engine.state);
        try {
          await this.options.escrow.pay(p);
          p.state = "paid";
        } catch {
          /* Keep pending; escrow key makes retry safe. */
        }
        await this.store.save(this.engine.state);
      }
  }
  async advance() {
    const run = this.queue.then(async () => {
      this.engine.tick();
      await this.flush();
    });
    this.queue = run.catch(() => {});
    await run;
  }
  async route(req: Request): Promise<Response> {
    const url = new URL(req.url),
      path = url.pathname,
      e = this.engine;
    const json = (b: any, status = 200) => {
      const text = JSON.stringify(b);
      if (text.length >= 3072)
        return Response.json(
          { ok: false, error: "response_too_large" },
          { status: 500 },
        );
      return new Response(text, {
        status,
        headers: {
          "content-type": "application/json",
          "cache-control": "no-store",
        },
      });
    };
    try {
      e.tick();
      if (req.method === "GET" && path === "/live")
        return new Response(
          live(
            e,
            this.options.demo && url.searchParams.get("ns") === "demo"
              ? "demo"
              : "prod",
          ),
          {
            headers: {
              "content-type": "text/html",
              "cache-control": "no-store",
            },
          },
        );
      if (req.method === "GET" && path.startsWith("/r/")) {
        const s = e.state.shares[path.slice(3)];
        return s
          ? new Response(resultPage(s), {
              headers: { "content-type": "text/html" },
            })
          : json({ ok: false, error: "not_found" }, 404);
      }
      if (req.method === "GET" && path.startsWith("/go/")) {
        const app =
          url.searchParams.get("a") === "defenders" ? "defenders" : "lazarus";
        if (path === "/go/install")
          return Response.redirect(
            `https://solana.com/breakpoint/badge/apps/app?id=range-${app}`,
            302,
          );
        if (path === "/go/screening")
          return Response.redirect(
            `https://www.range.org/product/transaction-screening?utm_source=event-breakpoint&utm_medium=qr&utm_campaign=always-on&utm_content=badge-${app}`,
            302,
          );
      }
      if (!path.startsWith("/v1/"))
        return json({ ok: false, error: "not_found" }, 404);
      if (!["POST", "GET"].includes(req.method))
        return json({ ok: false, error: "method_not_allowed" }, 405);
      const body = await req.text();
      if (new TextEncoder().encode(body).length > 2048)
        return json({ ok: false, error: "body_too_large" }, 413);
      let b: any = {};
      try {
        b = body ? JSON.parse(body) : {};
        if (!b || typeof b !== "object" || Array.isArray(b)) throw 0;
      } catch {
        return json({ ok: false, error: "bad_json" }, 400);
      }
      let i: Identity | null = null;
      if (req.headers.has("x-demo-badge")) {
        if (!this.options.demo)
          return json({ ok: false, error: "demo_disabled" }, 403);
        const badge = req.headers.get("x-demo-badge")!,
          user = req.headers.get("x-demo-user") ?? badge;
        if (
          !/^[a-zA-Z0-9_-]{1,32}$/.test(badge) ||
          !/^[a-zA-Z0-9_-]{1,80}$/.test(user)
        )
          return json({ ok: false, error: "bad_identity" }, 400);
        i = {
          badge,
          user,
          ns: "demo",
          app:
            path.includes("/defenders/") || b.app === "defenders"
              ? "defenders"
              : "lazarus",
        };
      } else i = await this.verifier.verify(req, body);
      if (!i) return json({ ok: false, error: "unauthorized" }, 401);
      if (
        (b.app && b.app !== i.app) ||
        (path.includes("/defenders/") && i.app !== "defenders") ||
        (path.includes("/lazarus/") && i.app !== "lazarus")
      )
        return json({ ok: false, error: "wrong_app" }, 403);
      let answer: any;
      if (req.method === "GET" && path === "/v1/defenders/top")
        answer = {
          top: e.top(i.ns).map((s) => ({ n: s.n, s: s.s })),
          day: new Date(e.now()).toISOString().slice(0, 10),
        };
      else if (req.method !== "POST")
        return json({ ok: false, error: "method_not_allowed" }, 405);
      else
        switch (path) {
          case "/v1/hello":
            if (!["lazarus", "defenders"].includes(b.app))
              throw new RuleError("bad_app");
            answer = e.hello(i, b);
            break;
          case "/v1/welcome/claim":
            answer = e.welcome(i, b);
            break;
          case "/v1/lazarus/poll":
            answer = e.poll(i, b);
            break;
          case "/v1/lazarus/action":
            answer = e.action(i, b);
            break;
          case "/v1/defenders/score":
            answer = e.score(i, b);
            break;
          case "/v1/share": {
            if (!["caught", "escaped", "score", "install"].includes(b.kind))
              throw new RuleError("bad_kind");
            let text =
              "Install " +
              (i.app === "lazarus"
                ? "Lazarus In The Room"
                : "Solana Defenders");
            if (b.kind === "caught" || b.kind === "escaped") {
              const { r } = e.current(i);
              if (
                !r ||
                r.phase !== "ended" ||
                r.result !== b.kind.toUpperCase() ||
                r.winner !== i.badge
              )
                throw new RuleError("result_unverified");
              text = `${e.player(i).x ?? e.player(i).name}: Lazarus ${r.result}`;
            } else if (b.kind === "score") {
              const score = e.top(i.ns, 1000).find((s) => s.user === i!.user);
              if (!score) throw new RuleError("score_required");
              text = `${score.n}: ${score.s} in Solana Defenders`;
            }
            let code: string;
            do {
              code = crypto.randomUUID().replaceAll("-", "").slice(0, 6);
            } while (e.state.shares[code]);
            const origin =
              this.options.shortOrigin ??
              this.options.publicOrigin ??
              url.origin;
            const link = `${origin}/r/${code}`;
            if (link.length > 40) throw new RuleError("short_origin_required");
            e.state.shares[code] = {
              app: i.app,
              kind: b.kind,
              text: ascii(text, 100),
              ns: i.ns,
            };
            answer = { url: link };
            break;
          }
          default:
            return json({ ok: false, error: "not_found" }, 404);
        }
      await this.flush();
      return json({ ok: true, ...answer });
    } catch (error) {
      await this.store.save(e.state);
      return json(
        {
          ok: false,
          error: error instanceof RuleError ? error.message : "server_error",
        },
        error instanceof RuleError ? 400 : 503,
      );
    }
  }
}
