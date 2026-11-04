import { describe, test, expect } from "bun:test";
import { Engine, emptyState, type Identity } from "../src/engine";
import { Demo } from "../src/demo";
import { API } from "../src/api";
import { Verifier, signedText } from "../src/auth";
import { SQLiteStore } from "../src/storage";
import { mkdtemp, mkdir, copyFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GameRoom } from "../worker/index";
import { MockEscrow } from "../src/escrow";
function setup(n = 6, ns: "prod" | "demo" = "prod") {
  let now = 1800000001000,
    seq = 0;
  const e = new Engine(emptyState(), {
    now: () => now,
    random: () => 0,
    welcomeAmount: 25,
  });
  const ids: Identity[] = Array.from({ length: n }, (_, j) => ({
    badge: `B${j}`,
    user: `U${j}`,
    app: "lazarus",
    ns,
  }));
  const nearby = (j: number) =>
    ids.filter((_, k) => k !== j).map((i) => ({ id: i.badge, rssi: -50 }));
  for (const i of ids) e.hello(i, { name: `@${i.badge}`, x: `@${i.badge}` });
  function poll() {
    ids.forEach((i, j) => e.poll(i, { nearby: nearby(j) }));
  }
  function action(j: number, action: string, target?: string, op?: string) {
    return e.action(ids[j], { action, target, op: op ?? `op_${seq++}` });
  }
  function advance(ms: number, refresh = true) {
    for (let t = 0; t < ms; t += 1000) {
      now += Math.min(1000, ms - t);
      if (refresh) poll();
      else e.tick();
    }
  }
  function start() {
    poll();
    ids.forEach((_, j) => action(j, "ready"));
    poll();
    action(0, "ack");
    advance(30000);
    return Object.values(e.state.rooms)[0];
  }
  return {
    e,
    ids,
    poll,
    action,
    advance,
    start,
    set: (t: number) => (now = t),
    now: () => now,
    nearby,
  };
}
describe("round rules", () => {
  test("6 ready peers make a ranked room and secret role views", () => {
    const f = setup(),
      r = f.start();
    expect(r.ranked).toBe(true);
    expect(r.phase).toBe("active");
    expect(f.e.view(f.ids[1]).room?.role).toBe("investigator");
    expect(JSON.stringify(f.e.view(f.ids[1]))).not.toContain("infector");
  });
  test("4 players are unranked; 3 stay in lobby", () => {
    expect(setup(4).start().ranked).toBe(false);
    const f = setup(3);
    f.poll();
    f.ids.forEach((_, j) => f.action(j, "ready"));
    expect(Object.keys(f.e.state.rooms)).toHaveLength(0);
  });
  test("one account cannot fill a room with multiple badges", () => {
    const f = setup();
    f.ids.forEach((i) => (i.user = "same"));
    f.ids.forEach((i) => f.e.hello(i, { name: "one" }));
    f.poll();
    f.ids.forEach((_, j) => f.action(j, "ready"));
    expect(Object.keys(f.e.state.rooms)).toHaveLength(0);
  });
  test("prepare needs secret role acknowledgement", () => {
    const f = setup();
    f.poll();
    f.ids.forEach((_, j) => f.action(j, "ready"));
    f.advance(30000);
    expect(Object.values(f.e.state.rooms)[0].result).toBe("VOID");
  });
  test("screening is blocked before start", () => {
    const f = setup();
    f.poll();
    f.ids.forEach((_, j) => f.action(j, "ready"));
    expect(() => f.action(1, "screen", "B0")).toThrow("not_active");
  });
  test("latent source is clean; credits refill to 3", () => {
    const f = setup();
    f.e.config.exposureMs = 100000;
    f.start();
    expect(f.action(1, "screen", "B0").screen.result).toBe("CLEAN");
    expect(f.action(1, "screen", "B0").screen.result).toBe("CLEAN");
    expect(() => f.action(1, "screen", "B0")).toThrow("no_credits");
    f.advance(20000);
    expect(f.e.view(f.ids[1]).room?.credits).toBe(1);
  });
  test("catch ends round and queues one pot payout", () => {
    const f = setup();
    f.start();
    f.advance(12000);
    const a = f.action(1, "screen", "B0", "same_op");
    expect(a.screen.result).toBe("CAUGHT");
    expect(f.action(1, "screen", "B0", "same_op")).toEqual(a);
    expect(Object.values(f.e.state.payouts)).toHaveLength(1);
  });
  test("operation id cannot be reused for another target", () => {
    const f = setup();
    f.start();
    f.action(1, "screen", "B2", "same_op");
    expect(() => f.action(1, "screen", "B3", "same_op")).toThrow("op_conflict");
  });
  test("reciprocal exposure takes 18 seconds and escape has unique threshold", () => {
    const f = setup(),
      r = f.start();
    f.advance(17000);
    expect(r.infected).toHaveLength(0);
    f.advance(1000);
    expect(r.result).toBeUndefined();
    f.advance(102000);
    expect(r.result).toBe("ESCAPED");
    expect(new Set(r.infected).size).toBe(r.infected.length);
  });
  test("no reciprocal observation gives no infection", () => {
    const f = setup(),
      r = f.start();
    for (let j = 1; j < 6; j++) f.e.player(f.ids[j]).nearby = [];
    f.advance(10000, false);
    expect(r.infected).toHaveLength(0);
  });
  test("scheduler gaps never backfill exposure", () => {
    const f = setup(),
      r = f.start();
    f.set(f.now() + 14000);
    f.poll();
    expect(r.infected).toHaveLength(0);
    expect(r.members[1].heat).toBe(0);
  });
  test("source disconnect voids round after freshness deadline", () => {
    const f = setup(),
      r = f.start();
    f.advance(15000, false);
    expect(r.result).toBe("VOID");
    expect(Object.values(f.e.state.payouts)).toHaveLength(0);
  });
  test("stale returning hunter cannot screen before reconciliation", () => {
    const f = setup();
    f.start();
    f.e.player(f.ids[1]).seen = f.now() - 16000;
    expect(() => f.action(1, "screen", "B0")).toThrow("disconnected");
  });
  test("weak, bridged and emulator peers cannot form production rooms", () => {
    const f = setup();
    f.ids.forEach((i, j) =>
      f.e.poll(i, {
        nearby: f.nearby(j).map((o) => ({ ...o, bridged: true })),
      }),
    );
    f.ids.forEach((_, j) => f.action(j, "ready"));
    expect(Object.values(f.e.state.rooms)).toHaveLength(0);
    const i = { ...f.ids[0], badge: "e123" };
    f.e.hello(i, { name: "emu" });
    f.e.poll(i, {
      nearby: [
        { id: "e456", rssi: -50 },
        { id: "B0", rssi: 0 },
      ],
    });
    expect(f.e.player(i).nearby).toHaveLength(0);
  });
  test("demo namespace accepts bridged emulator observations without prizes", () => {
    const f = setup(6, "demo");
    f.e.poll(f.ids[0], { nearby: [{ id: "e123", rssi: 0, bridged: true }] });
    expect(f.e.player(f.ids[0]).nearby).toEqual([{ id: "e123", rssi: -50 }]);
  });
  test("zero infections at timeout is VOID", () => {
    const f = setup(),
      r = f.start();
    r.end = f.now() + 1000;
    f.advance(1000);
    expect(r.result).toBe("VOID");
  });
  test("demo rounds never pay or issue mint entitlements", () => {
    const f = setup(6, "demo");
    const r = f.start();
    f.advance(12000);
    f.action(1, "screen", "B0");
    expect(r.result).toBe("CAUGHT");
    expect(Object.keys(f.e.state.payouts)).toHaveLength(0);
    expect(f.e.welcome(f.ids[0], { op: "demo_claim" }).amount).toBe(0);
  });
  test("welcome once per user/app, stable op retries survive badge swap", () => {
    const f = setup();
    expect(f.e.welcome(f.ids[0], { op: "welcome1" }).amount).toBe(25);
    expect(
      f.e.welcome({ ...f.ids[0], badge: "new" }, { op: "welcome2" }).amount,
    ).toBe(0);
    expect(f.e.welcome(f.ids[0], { op: "welcome1" }).amount).toBe(25);
    expect(
      f.e.welcome({ ...f.ids[0], app: "defenders" }, { op: "welcome3" }).amount,
    ).toBe(25);
  });
  test("Big Drop only at hour boundary, pot is larger", () => {
    const f = setup();
    f.set(1800000000000);
    const r = f.start();
    expect(r.big).toBe(true);
    expect(r.pot).toBe(300);
    expect(f.e.bigIn()).toBeGreaterThan(0);
  });
  test("upstream quarantine clue and one reward per victim", () => {
    const f = setup(),
      r = f.start();
    const victim = r.members[2];
    victim.status = "tainted";
    victim.infector = "B0";
    victim.hop = 1;
    const a = f.action(1, "screen", "B2");
    expect(a.screen.clue).toEqual({ id: "B0", name: "@B0", sid: f.e.player(f.ids[0]).sid, hop: 1 });
    expect(String(victim.status)).toBe("quarantined");
    expect(f.e.view(f.ids[1]).awards).toHaveLength(1);
    expect(f.action(3, "screen", "B2").screen.result).toBe("QUARANTINED");
    expect(f.e.view(f.ids[3]).awards).toHaveLength(0);
  });
  test("self quarantine pays nothing and keeps hunting", () => {
    const f = setup(),
      r = f.start();
    r.members[1].status = "tainted";
    f.action(1, "quarantine");
    expect(String(r.members[1].status)).toBe("quarantined");
    expect(f.e.view(f.ids[1]).awards).toHaveLength(0);
    expect(f.action(1, "screen", "B2").screen.result).toBe("CLEAN");
  });
  test("leaving the lobby cancels readiness", () => {
    const f = setup(1);
    f.action(0, "ready");
    f.action(0, "leave");
    expect(f.e.player(f.ids[0]).ready).toBe(false);
  });
  test("switching apps counts as source departure", () => {
    const f = setup(),
      r = f.start();
    f.e.hello({ ...f.ids[0], app: "defenders" }, { name: "source" });
    f.e.tick();
    expect(r.result).toBe("VOID");
  });
  test("all responses fit badge limit at 20 peers", () => {
    const f = setup(20);
    f.start();
    expect(JSON.stringify(f.e.view(f.ids[0])).length).toBeLessThan(3072);
  });
});
describe("authentication and adapters", () => {
  test("Ed25519 binds raw body, public URL, identity, time and nonce", async () => {
    const now = Date.now(),
      state = emptyState(),
      pair = (await crypto.subtle.generateKey("Ed25519", true, [
        "sign",
        "verify",
      ])) as CryptoKeyPair;
    const v = new Verifier(state, {
      now: () => now,
      publicOrigin: "https://game.test",
    });
    v.keys.set("test", pair.publicKey);
    const headers = {
      "x-badge-app": "range-lazarus",
      "x-badge-id": "B1",
      "x-badge-user": "U1",
      "x-badge-time": String(now),
      "x-badge-request": "nonce_12345",
      "x-badge-key": "test",
    };
    const unsigned = new Request("http://localhost:8787/v1/hello", {
      method: "POST",
      headers,
      body: '{"app":"lazarus"}',
    });
    const signature = Buffer.from(
      await crypto.subtle.sign(
        "Ed25519",
        pair.privateKey,
        new TextEncoder().encode(
          await signedText(unsigned, '{"app":"lazarus"}', "https://game.test"),
        ),
      ),
    ).toString("base64");
    const signed = new Request(unsigned, {
      headers: { ...headers, "x-badge-signature": signature },
    });
    expect(await v.verify(signed, "tampered")).toBeNull();
    expect(
      await v.verify(
        new Request("http://localhost/other", {
          method: "POST",
          headers: signed.headers,
        }),
        "{}",
      ),
    ).toBeNull();
    expect((await v.verify(signed, '{"app":"lazarus"}'))?.user).toBe("U1");
    expect(await v.verify(signed, '{"app":"lazarus"}')).toBeNull();
    const stale = new Request(signed, {
      headers: {
        ...headers,
        "x-badge-time": String(now - 61000),
        "x-badge-signature": signature,
      },
    });
    expect(await v.verify(stale, '{"app":"lazarus"}')).toBeNull();
  });
  test("concurrent replay allows one request", async () => {
    const s = emptyState(),
      now = Date.now(),
      p = (await crypto.subtle.generateKey("Ed25519", true, [
        "sign",
        "verify",
      ])) as CryptoKeyPair,
      v = new Verifier(s);
    v.keys.set("t", p.publicKey);
    const h = {
      "x-badge-app": "range-defenders",
      "x-badge-id": "B",
      "x-badge-user": "U",
      "x-badge-time": String(now),
      "x-badge-request": "concurrent_1",
      "x-badge-key": "t",
    };
    const r = new Request("https://g.test/v1/hello", {
      method: "POST",
      headers: h,
    });
    h["x-badge-signature" as keyof typeof h] = Buffer.from(
      await crypto.subtle.sign(
        "Ed25519",
        p.privateKey,
        new TextEncoder().encode(await signedText(r, "")),
      ),
    ).toString("base64");
    const req = new Request(r, { headers: h });
    expect(
      (await Promise.all([v.verify(req, ""), v.verify(req, "")])).filter(
        Boolean,
      ),
    ).toHaveLength(1);
  });
  test("SQLite persists rooms, operations, entitlements and payout retry ledger", async () => {
    const f = setup();
    f.start();
    f.advance(12000);
    f.action(1, "screen", "B0");
    const s = new SQLiteStore(":memory:");
    s.save(f.e.state);
    const restored = s.load();
    expect(restored.payouts).toEqual(f.e.state.payouts);
    expect(restored.ops).toEqual(f.e.state.ops);
    s.close();
  });
  test("idempotent escrow survives lost response and restart", async () => {
    const f = setup();
    f.start();
    f.advance(12000);
    f.action(1, "screen", "B0");
    const store = new SQLiteStore(":memory:"),
      mock = new MockEscrow();
    let fail = true;
    const api = new API(f.e, store, new Verifier(f.e.state), {
      escrow: {
        async pay(p) {
          await mock.pay(p);
          if (fail) {
            fail = false;
            throw Error("lost");
          }
        },
      },
    });
    await api.flush();
    expect(Object.values(f.e.state.payouts)[0].state).toBe("pending");
    const e2 = new Engine(store.load()),
      api2 = new API(e2, store, new Verifier(e2.state), { escrow: mock });
    await api2.flush();
    expect(mock.paid.size).toBe(1);
    expect(Object.values(e2.state.payouts)[0].state).toBe("paid");
    store.close();
  });
  test("production rejects demo header; demo never disables signed route verification", async () => {
    const f = setup(),
      s = new SQLiteStore(":memory:"),
      api = new API(f.e, s, new Verifier(f.e.state));
    const make = (h: any) =>
      new Request("http://localhost/v1/hello", {
        method: "POST",
        headers: h,
        body: '{"app":"lazarus"}',
      });
    expect((await api.handle(make({ "x-demo-badge": "B" }))).status).toBe(403);
    api.options.demo = true;
    expect((await api.handle(make({}))).status).toBe(401);
    expect((await api.handle(make({ "x-demo-badge": "B" }))).status).toBe(200);
    s.close();
  });
  test("shared score/top/share/redirect/live contract", async () => {
    const s = new SQLiteStore(":memory:"),
      e = new Engine(),
      api = new API(e, s, new Verifier(e.state), { demo: true });
    async function call(path: string, b?: any) {
      return api.handle(
        new Request("http://localhost:8787" + path, {
          method: b ? "POST" : "GET",
          headers: { "x-demo-badge": "B", "x-demo-user": "U" },
          body: b ? JSON.stringify(b) : undefined,
        }),
      );
    }
    await call("/v1/hello", {
      app: "defenders",
      name: "Hunter",
      x: null,
      v: "1.0.0",
    });
    const score = await (
      await call("/v1/defenders/score", {
        score: 120,
        seconds: 10,
        wave: 2,
        boss: false,
        op: "score_1",
      })
    ).json();
    expect(score.best).toBe(120);
    expect(score.rank).toBe(1);
    expect((await (await call("/v1/defenders/top")).json()).top).toHaveLength(
      1,
    );
    const share = await (
      await call("/v1/share", { app: "defenders", kind: "score", data: {} })
    ).json();
    expect(share.url.length).toBeLessThanOrEqual(40);
    expect((await api.handle(new Request(share.url))).status).toBe(200);
    expect(
      (await call("/go/install?a=defenders")).headers.get("location"),
    ).toEndWith("range-defenders");
    expect(
      (await call("/go/screening?a=defenders")).headers.get("location"),
    ).toContain("badge-defenders");
    expect(await (await call("/live")).text()).toContain("Range");
    s.close();
  });
});

describe("demo bots", () => {
  test("demo source is repeatable and bots join an immediate rematch", async () => {
    let now = Date.now();
    const e = new Engine(emptyState(), { now: () => now }),
      d = new Demo(e);
    const response = await d.handle(
      new Request("http://local/demo/session", {
        method: "POST",
        body: JSON.stringify({ session: "abcdef12" }),
      }),
    );
    expect(response.ok).toBe(true);
    const s = d.sessions.get("abcdef12")!,
      human = s.players[0];
    d.tick();
    e.poll(human, { nearby: d.nearby(s, 0) });
    e.action(human, { action: "ready", op: "first_ready" });
    d.tick();
    const r = e.current(human).r!;
    expect(r.members.find((m) => m.role === "lazarus")?.badge).toBe(
      "sabcdef12_1",
    );
    e.finish(
      r,
      "CAUGHT",
      r.members.find((m) => m.badge === human.badge),
    );
    e.action(human, { action: "ready", op: "rematch_ready" });
    d.tick();
    expect(e.current(human).r?.id).not.toBe(r.id);
    expect(e.current(human).r?.members).toHaveLength(6);
    expect(e.current(human).r?.phase).toBe("preparing");
  });
});


describe("independent review regressions", () => {
  test("f2_big_drop_latch", () => {
    const f = setup();
    f.set(1800000000000);
    f.poll();
    for (let j = 0; j < 4; j++) f.action(j, "ready");
    const r = Object.values(f.e.state.rooms)[0];
    expect(r.ranked).toBe(false);
    expect(r.big).toBe(false);
    expect(f.e.state.lastHour.prod).toBeUndefined();
    f.action(4, "ready"); f.action(5, "ready");
    expect(r.big).toBe(true); expect(r.pot).toBe(300);
    expect(f.e.state.lastHour.prod).toBe(Math.floor(f.now()/3600000));
    const late = setup(); late.set(1800000059000); late.poll();
    for (let j = 0; j < 4; j++) late.action(j, "ready");
    late.set(1800000060000); late.poll(); late.action(4, "ready"); late.action(5, "ready");
    expect(Object.values(late.e.state.rooms)[0].big).toBe(false);
  });
  test("f3_prep_freezes_missing_investigator", () => {
    const f = setup(); f.poll(); f.ids.forEach((_,j) => f.action(j,"ready")); f.action(0,"ack");
    for (let t=0;t<30;t++) {
      f.set(f.now()+1000);
      f.ids.slice(0,5).forEach((i,j) => f.e.poll(i,{nearby:f.nearby(j)}));
    }
    const r = Object.values(f.e.state.rooms)[0];
    expect(r.phase).toBe("active"); expect(r.members[5].connected).toBe(false);
    expect(() => f.action(5,"screen","B0")).toThrow("disconnected");
    f.e.poll(f.ids[5],{nearby:f.nearby(5)}); f.e.tick();
    expect(r.members[5].connected).toBe(true);
  });
  test("f4_p2_escape_waits_120_seconds", () => {
    const f=setup(), r=f.start();
    expect(r.members[1].credits).toBe(2);
    f.advance(119000); expect(r.phase).toBe("active"); expect(r.infected.length).toBeGreaterThanOrEqual(r.threshold);
    f.advance(1000); expect(r.result).toBe("ESCAPED");
    const short=setup(), q=short.start(); q.end=q.start+45000;
    short.advance(45000); expect(q.result).toBe("ESCAPED");
    const few=setup(), v=few.start(); v.infected=["B1"]; few.e.config.exposureMs=999999;
    v.end=v.start+1000; few.advance(1000); expect(v.result).toBe("VOID");
  });
  test("f6_claim_after_rematch_and_leave", () => {
    const f=setup(), r=f.start();
    const award=f.e.entitlement(f.ids[1],"quarantine:test",5);
    f.e.finish(r,"VOID"); f.action(1,"ready");
    const body={action:"claim", id:award.id, op:"claim_later"};
    expect(f.e.action(f.ids[1],body).amount).toBe(5);
    expect(f.e.action(f.ids[1],body).amount).toBe(5);
    expect(f.e.action(f.ids[1],{...body,op:"claim_again"}).amount).toBe(0);
    expect(() => f.e.action(f.ids[2],{...body,op:"claim_theft"})).toThrow("bad_entitlement");
  });
  test("f7_repeat_quarantine_preserves_status_and_credit", () => {
    const f=setup(), r=f.start(); r.members[2].status="tainted"; r.members[2].infector="B0";
    f.action(1,"screen","B2");
    const credits=r.members[3].credits;
    expect(f.action(3,"screen","B2").screen.result).toBe("QUARANTINED");
    expect(r.members[3].credits).toBe(credits); expect(f.e.view(f.ids[3]).awards).toHaveLength(0);
  });
  test("f8_key_timeout_preserves_cache_and_retries", async () => {
    const state=emptyState(), now=Date.now();
    const pair=await crypto.subtle.generateKey("Ed25519",true,["sign","verify"]) as CryptoKeyPair;
    let attempts=0;
    const v=new Verifier(state,{now:()=>now, fetchKey:async signal => {
      attempts++; expect(signal).toBeInstanceOf(AbortSignal);
      if(attempts===1) return new Promise(() => {});
      return {id:"new",key:Buffer.from(await crypto.subtle.exportKey("raw",pair.publicKey)).toString("base64")};
    }});
    v.keys.set("old",pair.publicKey);
    const req=new Request("https://g.test/v1/hello",{headers:{"x-badge-app":"range-lazarus","x-badge-id":"B","x-badge-user":"U","x-badge-time":String(now),"x-badge-request":"timeout_nonce","x-badge-key":"new"}});
    const api=new API(new Engine(state),{load:()=>state,save:()=>{}},v);
    const t=performance.now(); expect((await api.handle(req)).status).toBe(401);
    expect(performance.now()-t).toBeLessThan(2500); expect(v.lastFetch).toBe(-Infinity); expect(v.keys.has("old")).toBe(true);
    await v.verify(req,""); expect(attempts).toBe(2); expect(v.keys.has("new")).toBe(true);
    expect((await api.handle(new Request("https://g.test/live"))).status).toBe(200);
  });
  test("f10_set_server_updates_both_packages", async () => {
    const root=await mkdtemp(join(tmpdir(),"bp26-server-"));
    try {
      await mkdir(join(root,"tools/bp26"),{recursive:true});
      await copyFile("../tools/bp26/set-server.sh",join(root,"tools/bp26/set-server.sh"));
      for(const app of ["lazarus","defenders"]) {
        await mkdir(join(root,"apps",app),{recursive:true});
        for(const file of ["main.lua","app.json"]) await copyFile("../apps/"+app+"/"+file,join(root,"apps",app,file));
      }
      const run=(...args:string[])=>Bun.spawn(["sh",join(root,"tools/bp26/set-server.sh"),...args],{stdout:"pipe",stderr:"pipe"});
      expect(await run("https://long.production.test","https://r.test").exited).toBe(0);
      for(const app of ["lazarus","defenders"]) {
        const main=await Bun.file(join(root,"apps",app,"main.lua")).text();
        expect(main).toContain('local SERVER = "https://long.production.test"');
        expect(main).toContain('local SHORT_ORIGIN = "https://r.test"');
        expect((await Bun.file(join(root,"apps",app,"app.json")).json()).hosts).toEqual(["long.production.test","r.test"]);
      }
      expect(await run("https://r.test","https://r.test").exited).toBe(0);
      expect((await Bun.file(join(root,"apps/lazarus/app.json")).json()).hosts).toEqual(["r.test"]);
      const before=await Bun.file(join(root,"apps/lazarus/main.lua")).text();
      expect(await run("http://bad.test","https://r.test").exited).not.toBe(0);
      expect(await run("https://good.test","https://far-too-long-for-a-result-qr.example").exited).not.toBe(0);
      expect(await Bun.file(join(root,"apps/lazarus/main.lua")).text()).toBe(before);
    } finally { await rm(root,{recursive:true,force:true}); }
  });
  test("f13_screen_uses_hunter_observation_only", () => {
    const f=setup(); f.start(); f.advance(12000);
    f.e.player(f.ids[0]).nearby=[];
    expect(f.action(1,"screen","B0").screen.result).toBe("CAUGHT");
    const stale=setup(); stale.start(); stale.set(stale.now()+7000);
    expect(() => stale.action(1,"screen","B0")).toThrow("not_nearby");
  });
  test("f14_clean_age_is_per_target", () => {
    const f=setup(); f.e.config.exposureMs=999999; f.start(); f.advance(5000);
    expect(f.action(1,"screen","B2").screen.age_s).toBe(5);
    f.advance(4000);
    const peers=f.e.view(f.ids[1]).nearby;
    expect(peers.find(p=>p.id==="B2")?.age_s).toBe(4);
    expect(peers.find(p=>p.id==="B3")?.age_s).toBe(9);
    expect(f.action(1,"screen","B2").screen.age_s).toBe(4);
  });
  test("f15_prune_transient_state_keep_reward_tombstones", () => {
    const f=setup(), r=f.start(); f.e.finish(r,"VOID");
    const welcome=f.e.welcome(f.ids[1],{op:"welcome_old"}); expect(welcome.amount).toBe(25);
    const claimed=f.e.entitlement(f.ids[1],"quarantine:old",5); claimed.claimed=true;
    const pending=f.e.entitlement(f.ids[1],"quarantine:pending",5);
    f.e.state.shares.old={app:"lazarus",kind:"install",text:"test",ns:"prod",at:f.now()};
    const idle={...f.ids[1],badge:"idle",user:"idle"}; f.e.hello(idle,{name:"idle"});
    f.set(f.now()+3600001); f.e.tick();
    expect(f.e.peer("prod","idle")).toBeUndefined();
    expect(f.e.peer("prod","B0")?.name).toBe("@B0");
    f.set(f.now()+86400001); f.e.tick();
    expect(Object.keys(f.e.state.rooms)).toHaveLength(0); expect(Object.keys(f.e.state.players)).toHaveLength(0);
    expect(Object.keys(f.e.state.ops)).toHaveLength(0); expect(Object.keys(f.e.state.shares)).toHaveLength(0);
    expect(f.e.state.entitlements[claimed.id]).toBeUndefined(); expect(f.e.state.entitlements[pending.id]).toBeDefined();
    expect(f.e.welcome(f.ids[1],{op:"welcome_new"}).amount).toBe(0);
  });
  test("f16_demo_rejects_signed_production_and_escrow_startup", async () => {
    const state=emptyState(), e=new Engine(state), v=new Verifier(state);
    let verified=false; v.verify=async()=>{verified=true;return {ns:"prod",app:"lazarus",badge:"B",user:"U"}};
    const api=new API(e,{load:()=>state,save:()=>{}},v,{demo:true});
    for(const extra of [{},{"x-demo-badge":"B"}] as Record<string,string>[]) {
      const response=await api.handle(new Request("https://g.test/v1/hello",{method:"POST",headers:{"x-badge-app":"range-lazarus",...extra},body:'{"app":"lazarus"}'}));
      expect(response.status).toBe(403);
    }
    expect(verified).toBe(false); expect(Object.keys(state.players)).toHaveLength(0);
    const proc=Bun.spawn([process.execPath,"src/index.ts"],{env:{...process.env,DEMO:"1",ESCROW_KEY:""},stdout:"pipe",stderr:"pipe"});
    const object=new GameRoom({blockConcurrencyWhile:(fn:()=>Promise<void>)=>fn()} as never,{DEMO:"1",ESCROW_KEY:""} as never);
    await expect(object.ready).rejects.toThrow("DEMO cannot use ESCROW_KEY");
    expect(await proc.exited).not.toBe(0); expect(await new Response(proc.stderr).text()).toContain("DEMO cannot use ESCROW_KEY");
  });
  test("f18_score_caps_and_live_filter", async () => {
    const state=emptyState(), e=new Engine(state), i:Identity={badge:"B",user:"U",ns:"prod",app:"defenders"};
    e.hello(i,{name:"Valid"});
    for(const b of [{score:601,wave:1,seconds:100},{score:161,wave:99,seconds:1},{score:100,wave:1,seconds:0},{score:9999999,wave:999,seconds:999}])
      expect(()=>e.score(i,{...b,boss:false,op:"invalid_"+b.score})).toThrow("bad_score");
    const good={score:600,wave:1,seconds:30,boss:false,op:"valid_score"};
    expect(e.score(i,good).best).toBe(600); expect(e.score(i,good).best).toBe(600);
    expect(()=>e.score(i,{...good,seconds:31})).toThrow("op_conflict");
    const day=new Date(e.now()).toISOString().slice(0,10);
    state.scores.cheat={n:"CHEATER",s:9999999,wave:1,seconds:1,boss:false,day,user:"cheat",ns:"prod"};
    const api=new API(e,{load:()=>state,save:()=>{}},new Verifier(state));
    const html=await (await api.handle(new Request("https://g.test/live"))).text();
    expect(html).toContain("Valid"); expect(html).not.toContain("CHEATER");
    const key=`prod:${day}:U`;
    state.scores[key]={...state.scores.cheat,user:"U"};
    expect(e.score(i,{...good,op:"replace_bad_score"}).best).toBe(600);
  });
  test("p1_distinct_short_ids", async () => {
    const e=new Engine(), d=new Demo(e);
    await d.handle(new Request("http://local/demo/session",{method:"POST",body:JSON.stringify({session:"50f32abc"})}));
    d.tick(); const session=d.sessions.get("50f32abc")!, human=session.players[0];
    e.poll(human,{nearby:d.nearby(session,0)});
    const peers=e.view(human).nearby;
    expect(peers).toHaveLength(5); expect(new Set(peers.map(p=>p.sid)).size).toBe(5);
    expect(peers.every(p=>p.sid.length===4)).toBe(true);
    const old=peers[0].sid; e.hello(session.players[1],{name:"Renamed"});
    expect(e.player(session.players[1]).sid).toBe(old);
  });
});
