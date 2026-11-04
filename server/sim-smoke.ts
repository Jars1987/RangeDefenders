// Runs the actual browser script with a DOM and the real Wasmoon VM.
// This checks behavior; use browser-smoke.ts for layout, screenshots, and video.
import { parseHTML } from "linkedom";
import { LuaFactory } from "wasmoon";
import { runInNewContext } from "node:vm";
const origin = process.env.BP26_URL ?? "http://localhost:8787";
class LocalFactory extends LuaFactory {
  constructor(_?: string) {
    super(import.meta.dir + "/node_modules/wasmoon/dist/glue.wasm");
  }
}
const source = await Bun.file("../sim/app.js").text();
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function until(fn: () => boolean, label: string, timeout = 15000) {
  const start = Date.now();
  while (!fn()) {
    if (Date.now() - start > timeout) throw Error("Timeout: " + label);
    await wait(100);
  }
}
async function play(kind: "caught" | "escaped") {
  const { window, document } = parseHTML(await (await fetch(origin)).text()),
    intervals: ReturnType<typeof setInterval>[] = [],
    errors: string[] = [],
    localTimers: ReturnType<typeof setTimeout>[] = [];
  const env: any = {
    window,
    document,
    console: { ...console, error: (e: any) => errors.push(String(e)) },
    crypto,
    URL,
    wasmoon: { LuaFactory: LocalFactory },
    location: { origin, reload() {} },
    setInterval: (fn: any, ms: number) => {
      const t = setInterval(fn, ms);
      intervals.push(t);
      return t;
    },
    setTimeout: (fn: any, ms: number) => {
      const t = setTimeout(fn, ms);
      localTimers.push(t);
      return t;
    },
    fetch: (path: any, opts: any) => fetch(new URL(path, origin), opts),
  };
  runInNewContext(source, env);
  try {
    await until(() => !!(window as any).bp26, "VM starts");
    const badge = () => document.querySelector("#badge")?.textContent ?? "";
    await until(
      () => badge().includes("Demo - no rewards"),
      "server hello completes",
    ).catch((e) => {
      console.log(
        "badge:",
        badge(),
        "errors:",
        errors,
        "connection:",
        document.querySelector("#connection")?.textContent,
      );
      throw e;
    });
    (window as any).bp26.key("select");
    await until(() => badge().includes("Screen nearby."), "joins room");
    await until(() => badge().includes("CLEAN"), "active round", 150000);
    if (kind === "caught") {
      await wait(12200);
      (window as any).bp26.key("select");
      await until(() => badge().includes("CAUGHT"), "CAUGHT");
      (window as any).bp26.key("right");
      await until(() => !!document.querySelector(".qr img"), "result QR");
      const a = document.querySelector(".qr a")!;
      const result = await fetch(new URL(a.getAttribute("href")!, origin));
      if (!result.ok) throw Error("result page failed");
      (window as any).bp26.key("back");
      const loss=document.querySelector("#network") as any;
      loss.checked=true; loss.dispatchEvent(new window.Event("change"));
      (window as any).bp26.key("back");
      await until(()=>badge().includes("Offline"),"offline title");
      (window as any).bp26.key("right");
      await until(()=>!!document.querySelector(".qr a"),"f10 offline short-origin QR");
      if(document.querySelector(".qr a")!.getAttribute("href")!==origin+"/go/install?a=lazarus")
        throw Error("f10 configured QR origin was not rewritten");
    } else await until(() => badge().includes("ESCAPED"), "ESCAPED", 150000);
    if ((window as any).bp26.widgets > 64)
      throw Error("Widget budget exceeded");
    if (errors.length) throw Error(errors.join("\n"));
    console.log(
      `PASS sim real JS + DOM + Wasmoon + local server: ${kind.toUpperCase()}`,
    );
  } finally {
    intervals.forEach(clearInterval);
    localTimers.forEach(clearTimeout);
  }
}
await play("caught");
await play("escaped");
