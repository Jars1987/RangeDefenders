import { Engine } from "./engine";
import { SQLiteStore } from "./storage";
import { Verifier } from "./auth";
import { API } from "./api";
import { HttpEscrow } from "./escrow";
import { Demo } from "./demo";
import { resolve } from "node:path";
import QRCode from "qrcode";
const root = resolve(import.meta.dir, "../.."),
  demo = process.env.DEMO === "1";
if (demo && process.env.ESCROW_KEY !== undefined) throw Error("DEMO cannot use ESCROW_KEY");
const store = new SQLiteStore(
  process.env.DB_PATH ?? (demo ? "demo.sqlite" : "bp26.sqlite"),
);
const e = new Engine(store.load(), {
  welcomeAmount: Number(process.env.WELCOME_AMOUNT ?? 0),
  pot: Number(process.env.ROUND_POT ?? 100),
});
const api = new API(
  e,
  store,
  new Verifier(e.state, { publicOrigin: process.env.PUBLIC_ORIGIN }),
  {
    demo,
    publicOrigin: process.env.PUBLIC_ORIGIN,
    shortOrigin: process.env.SHORT_ORIGIN,
    escrow: process.env.ESCROW_KEY
      ? new HttpEscrow(process.env.ESCROW_KEY)
      : undefined,
  },
);
const bot = new Demo(e);
const files: Record<string, string> = {
  "/": "sim/index.html",
  "/sim/": "sim/index.html",
  "/sim/app.js": "sim/app.js",
  "/sim/style.css": "sim/style.css",
  "/sim/shim.lua": "sim/shim.lua",
  "/sim/json.lua": "tools/bp26/json.lua",
  "/sim/main.lua": "apps/lazarus/main.lua",
  "/sim/wasmoon.js": "server/node_modules/wasmoon/dist/index.js",
  "/sim/glue.wasm": "server/node_modules/wasmoon/dist/glue.wasm",
};
let port = Number(process.env.PORT ?? 8787),
  server;
while (!server) {
  try {
    server = Bun.serve({
      port,
      hostname: process.env.HOST ?? "0.0.0.0",
      async fetch(req) {
        const path = new URL(req.url).pathname;
        if (demo && path === "/sim/qr") {
          const text = new URL(req.url).searchParams.get("text") ?? "";
          if (text.length > 256)
            return new Response("Too long", { status: 400 });
          return new Response(
            await QRCode.toString(text, { type: "svg", margin: 4 }),
            { headers: { "content-type": "image/svg+xml" } },
          );
        }
        if (files[path]) {
          if (!demo && path.startsWith("/sim"))
            return Response.json(
              { ok: false, error: "demo_disabled" },
              { status: 403 },
            );
          return new Response(Bun.file(resolve(root, files[path])), {
            headers: {
              "cache-control": "no-cache",
              ...(path.endsWith(".lua")
                ? { "content-type": "text/plain" }
                : {}),
            },
          });
        }
        if (path === "/demo/session") {
          if (!demo)
            return Response.json(
              { ok: false, error: "demo_disabled" },
              { status: 403 },
            );
          if (req.method !== "POST")
            return Response.json(
              { ok: false, error: "method_not_allowed" },
              { status: 405 },
            );
          if (Number(req.headers.get("content-length")) > 4096)
            return Response.json(
              { ok: false, error: "body_too_large" },
              { status: 413 },
            );
          const result = api.queue.then(() => bot.handle(req));
          api.queue = result.catch(() => {});
          try {
            return await result;
          } catch {
            return Response.json(
              { ok: false, error: "bad_request" },
              { status: 400 },
            );
          }
        }
        return api.handle(req);
      },
    });
  } catch (err) {
    if ((err as any).code !== "EADDRINUSE" || process.env.PORT || port >= 8797)
      throw err;
    port++;
  }
}
setInterval(() => {
  const run = api.queue.then(async () => {
    if (demo) bot.tick();
    e.tick();
    await api.flush();
  });
  api.queue = run.catch((err) => console.error("scheduler:", err.message));
}, 1000);
console.log(
  `${demo ? "BP26 demo" : "BP26 server"}: http://localhost:${port}${demo ? "/" : "/live"}`,
);
