// Transport-independent rules. All times are server milliseconds.
export type App = "lazarus" | "defenders";
export type Identity = {
  badge: string;
  user: string;
  app: App;
  ns: "prod" | "demo";
};
export type Observation = { id: string; rssi: number; bridged?: boolean };
type Player = Identity & {
  name: string;
  sid: string;
  x: string | null;
  seen: number;
  observed: number;
  nearby: Observation[];
  ready: boolean;
  room?: string;
};
type Member = {
  badge: string;
  user: string;
  role: "investigator" | "lazarus";
  status: "clean" | "tainted" | "quarantined";
  heat: number;
  infector?: string;
  hop: number;
  credits: number;
  creditAt: number;
  ack: boolean;
  connected: boolean;
  left?: boolean;
};
export type Room = {
  id: string;
  ns: "prod" | "demo";
  phase: "preparing" | "active" | "ended";
  result?: "CAUGHT" | "ESCAPED" | "VOID";
  winner?: string;
  members: Member[];
  start: number;
  end: number;
  last: number;
  ranked: boolean;
  big: boolean;
  pot: number;
  infected: string[];
  threshold: number;
  screenings: Record<string, number>;
  reason?: string;
  endedAt?: number;
};
type Entitlement = {
  id: string;
  user: string;
  app: App;
  campaign: string;
  ns: string;
  amount: number;
  claimed: boolean;
  at: number;
};
export type Payout = {
  key: string;
  to: string;
  amount: number;
  memo: string;
  state: "pending" | "paid";
  attempts: number;
};
export type State = {
  players: Record<string, Player>;
  rooms: Record<string, Room>;
  entitlements: Record<string, Entitlement>;
  ops: Record<string, { fingerprint: string; value: any; at: number }>;
  payouts: Record<string, Payout>;
  scores: Record<
    string,
    {
      n: string;
      s: number;
      wave: number;
      boss: boolean;
      seconds: number;
      day: string;
      user: string;
      ns: string;
    }
  >;
  shares: Record<string, { app: App; kind: string; text: string; ns: string; at: number }>;
  nonces: Record<string, number>;
  lastHour: Record<string, number>;
};
export const emptyState = (): State => ({
  players: {},
  rooms: {},
  entitlements: {},
  ops: {},
  payouts: {},
  scores: {},
  shares: {},
  nonces: {},
  lastHour: {},
});
export class RuleError extends Error {}
export interface Config {
  now: () => number;
  random: () => number;
  welcomeAmount: number;
  quarantineAmount: number;
  pot: number;
  preparationMs: number;
  roundMs: number;
  exposureMs: number;
  latentMs: number;
}
const FRESH = 15000,
  OBS = 6000;
export class Engine {
  config: Config;
  constructor(
    public state: State = emptyState(),
    config: Partial<Config> = {},
  ) {
    this.config = {
      now: Date.now,
      random: () => crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296,
      welcomeAmount: 0,
      quarantineAmount: 5,
      pot: 100,
      preparationMs: 30000,
      roundMs: 240000,
      exposureMs: 18000,
      latentMs: 12000,
      ...config,
    };
  }
  now() {
    return this.config.now();
  }
  key(i: Identity) {
    return `${i.ns}:${i.badge}`;
  }
  player(i: Identity) {
    const p = this.state.players[this.key(i)];
    if (!p || p.user !== i.user) throw new RuleError("hello_required");
    return p;
  }
  fresh(p: Player | undefined) {
    return !!p && this.now() - p.seen < FRESH;
  }
  peer(ns: string, id: string) {
    return this.state.players[`${ns}:${id}`];
  }
  bigIn() {
    return Math.ceil((3600000 - (this.now() % 3600000)) / 1000);
  }
  op(i: Identity, op: unknown, payload: unknown, run: () => any) {
    if (typeof op !== "string" || !/^[a-zA-Z0-9_-]{4,64}$/.test(op))
      throw new RuleError("bad_op");
    const key = `${i.ns}:${i.user}:${i.app}:${op}`,
      fingerprint = JSON.stringify(payload),
      old = this.state.ops[key];
    if (old) {
      if (old.fingerprint !== fingerprint) throw new RuleError("op_conflict");
      return old.value;
    }
    const value = run();
    this.state.ops[key] = { fingerprint, value, at: this.now() };
    return value;
  }
  entitlement(i: Identity, campaign: string, amount: number) {
    const id = `${i.ns}:${i.user}:${i.app}:${campaign}`;
    return (this.state.entitlements[id] ??= {
      id,
      user: i.user,
      app: i.app,
      campaign,
      ns: i.ns,
      amount: i.ns === "demo" ? 0 : amount,
      claimed: false,
      at: this.now(),
    });
  }
  shortId(i: Identity) {
    let hash = 2166136261;
    for (const c of i.badge) hash = Math.imul(hash ^ c.charCodeAt(0), 16777619) >>> 0;
    const used = new Set(Object.values(this.state.players).filter(p => p.ns === i.ns && p.badge !== i.badge).map(p => p.sid));
    for (let n = hash % 1679616; ; n = (n + 1) % 1679616) {
      const id = n.toString(36).padStart(4, "0").toUpperCase();
      if (!used.has(id)) return id;
    }
  }
  promote(r: Room) {
    const now = this.now(), hour = Math.floor(now / 3600000);
    r.ranked = r.members.length >= 6;
    if (r.ranked && now % 3600000 < 60000 && this.state.lastHour[r.ns] !== hour) {
      r.big = true;
      this.state.lastHour[r.ns] = hour;
    }
    r.pot = r.ranked ? this.config.pot * (r.big ? 3 : 1) : 0;
  }
  hello(i: Identity, b: any) {
    const k = this.key(i),
      old = this.state.players[k];
    if (old && old.user !== i.user && old.room)
      throw new RuleError("badge_in_use");
    this.state.players[k] = {
      ...old,
      ...i,
      name: ascii(b.name, 20) || i.badge,
      sid: old?.sid ?? this.shortId(i),
      x: typeof b.x === "string" ? ascii(b.x, 20) : null,
      seen: this.now(),
      observed: old?.observed ?? 0,
      nearby: old?.nearby ?? [],
      ready: old?.ready ?? false,
    };
    const e = this.entitlement(i, "welcome", this.config.welcomeAmount);
    return {
      welcome: { amount: e.amount, eligible: !e.claimed && e.amount > 0 },
      big_drop_in_s: this.bigIn(),
      msg: i.ns === "demo" ? "Demo - no rewards" : null,
    };
  }
  welcome(i: Identity, b: any) {
    return this.op(i, b.op, ["welcome"], () => {
      const e = this.entitlement(i, "welcome", this.config.welcomeAmount);
      const amount = e.claimed ? 0 : e.amount;
      e.claimed = true;
      return { amount };
    });
  }
  observations(i: Identity, observations: unknown) {
    const p = this.player(i);
    this.tick();
    p.seen = this.now();
    const peers = Array.isArray(observations) ? observations : [];
    p.nearby = peers
      .slice(0, 20)
      .filter(
        (o: any) =>
          o &&
          typeof o.id === "string" &&
          o.id !== i.badge &&
          o.id.length <= 32 &&
          Number.isInteger(o.rssi) &&
          o.rssi >= -100 &&
          (i.ns === "demo"
            ? o.rssi <= 0
            : o.rssi < 0 && !o.bridged && !o.id.startsWith("e")),
      )
      .map((o: any) => ({
        id: o.id,
        rssi: i.ns === "demo" && o.rssi === 0 ? -50 : o.rssi,
      }));
    p.observed = this.now();
  }
  mutual(a: Player, b: Player, threshold = -68) {
    return (
      this.fresh(a) &&
      this.fresh(b) &&
      this.now() - a.observed <= OBS &&
      this.now() - b.observed <= OBS &&
      a.nearby.some((o) => o.id === b.badge && o.rssi >= threshold) &&
      b.nearby.some((o) => o.id === a.badge && o.rssi >= threshold)
    );
  }
  form(ns: "prod" | "demo") {
    const candidates = Object.values(this.state.players).filter(
      (p) =>
        p.ns === ns &&
        p.app === "lazarus" &&
        p.ready &&
        !p.room &&
        this.fresh(p) &&
        (ns === "demo" || !p.badge.startsWith("e")),
    );
    // Players arriving during preparation can join the same reciprocal room.
    for (const p of candidates) {
      const r = Object.values(this.state.rooms).find(
        (r) =>
          r.ns === ns &&
          r.phase === "preparing" &&
          this.now() < r.start &&
          r.members.length < 20 &&
          !r.members.some((m) => m.user === p.user) &&
          r.members.some((m) => this.mutual(p, this.peer(ns, m.badge)!)),
      );
      if (r) {
        r.members.push({
          badge: p.badge,
          user: p.user,
          role: "investigator",
          status: "clean",
          heat: 0,
          hop: 0,
          credits: 2,
          creditAt: r.start + 20000,
          ack: false,
          connected: true,
        });
        p.room = r.id;
        p.ready = false;
        this.promote(r);
        r.threshold = Math.max(2, Math.ceil((r.members.length - 1) * 0.6));
      }
    }
    const visited = new Set<string>(
      candidates.filter((p) => p.room).map((p) => p.badge),
    );
    for (const seed of candidates) {
      if (visited.has(seed.badge)) continue;
      const group: Player[] = [],
        queue = [seed],
        users = new Set<string>();
      visited.add(seed.badge);
      while (queue.length && group.length < 20) {
        const p = queue.shift()!;
        if (users.has(p.user)) continue;
        users.add(p.user);
        group.push(p);
        for (const q of candidates)
          if (!visited.has(q.badge) && this.mutual(p, q)) {
            visited.add(q.badge);
            queue.push(q);
          }
      }
      if (group.length < 4) continue;
      const now = this.now();
      const id = crypto.randomUUID().replaceAll("-", "").slice(0, 12),
        demoSource = group.findIndex((p) => p.badge.endsWith("_1")),
        source =
          ns === "demo" && demoSource >= 0
            ? demoSource
            : Math.floor(this.config.random() * group.length),
        ranked = group.length >= 6;
      const room: Room = {
        id,
        ns,
        phase: "preparing",
        members: group.map((p, n) => ({
          badge: p.badge,
          user: p.user,
          role: n === source ? "lazarus" : "investigator",
          status: "clean",
          heat: 0,
          hop: 0,
          credits: 2,
          creditAt: now + this.config.preparationMs + 20000,
          ack: false,
          connected: true,
        })),
        start: now + this.config.preparationMs,
        end: now + this.config.preparationMs + this.config.roundMs,
        last: now,
        ranked,
        big: false,
        pot: 0,
        infected: [],
        threshold: Math.max(2, Math.ceil((group.length - 1) * 0.6)),
        screenings: {},
      };
      this.promote(room);
      this.state.rooms[id] = room;
      for (const p of group) {
        p.room = id;
        p.ready = false;
      }
    }
  }
  finish(r: Room, result: Room["result"], winner?: Member, reason?: string) {
    if (r.phase === "ended") return;
    r.phase = "ended";
    r.endedAt = this.now();
    r.result = result;
    r.winner = winner?.badge;
    r.reason = reason;
    if (r.ns === "prod" && r.ranked && winner && result !== "VOID") {
      const amount =
        result === "ESCAPED"
          ? Math.floor((r.pot * r.infected.length) / (r.members.length - 1))
          : r.pot;
      const key = `lazarus:${r.id}:${result}`;
      this.state.payouts[key] ??= {
        key,
        to: winner.user,
        amount,
        memo: `Lazarus ${result} ${r.id}`,
        state: "pending",
        attempts: 0,
      };
    }
  }
  tick() {
    const now = this.now();
    this.prune();
    for (const [key, time] of Object.entries(this.state.nonces))
      if (now - time > 60000) delete this.state.nonces[key];
    for (const r of Object.values(this.state.rooms)) {
      if (r.phase === "ended") continue;
      const source = r.members.find((m) => m.role === "lazarus")!;
      for (const m of r.members)
        m.connected =
          !m.left &&
          this.fresh(this.peer(r.ns, m.badge)) &&
          this.peer(r.ns, m.badge)?.app === "lazarus";
      if (!source.connected) {
        this.finish(r, "VOID", undefined, "Lazarus disconnected");
        continue;
      }
      if (r.phase === "preparing") {
        if (now >= r.start) {
          if (!source.ack) {
            this.finish(r, "VOID", undefined, "Preparation incomplete");
            continue;
          }
          r.phase = "active";
          r.last = now;
        }
        continue;
      }
      const elapsed = now - r.last;
      r.last = now;
      // A delayed scheduler never invents exposure for an unobserved interval.
      const dt = elapsed > 0 && elapsed <= OBS ? elapsed : 0;
      for (const m of r.members) {
        if (!m.connected) continue;
        if (now >= m.creditAt) {
          const gained = Math.floor((now - m.creditAt) / 20000) + 1;
          m.credits = Math.min(3, m.credits + gained);
          m.creditAt += gained * 20000;
        }
        if (m.role === "lazarus" || m.status !== "clean") continue;
        const p = this.peer(r.ns, m.badge)!;
        const infector = r.members.find(
          (q) =>
            q.connected &&
            q.badge !== m.badge &&
            (q.role === "lazarus" || q.status === "tainted") &&
            q.status !== "quarantined" &&
            this.mutual(p, this.peer(r.ns, q.badge)!),
        );
        m.heat = Math.max(
          0,
          Math.min(
            this.config.exposureMs,
            m.heat + (infector ? dt : -dt * 0.5),
          ),
        );
        if (m.heat >= this.config.exposureMs && infector) {
          m.status = "tainted";
          m.infector = infector.badge;
          m.hop = infector.hop + 1;
          if (!r.infected.includes(m.badge)) r.infected.push(m.badge);
        }
      }
      if (r.infected.length >= r.threshold && (now >= r.end || now - r.start >= 120000)) this.finish(r, "ESCAPED", source);
      else if (now >= r.end)
        this.finish(
          r,
          "VOID",
          undefined,
          r.infected.length ? "Not enough wallets drained" : "Nobody infected",
        );
    }
  }
  prune() {
    const now = this.now(), day = 86400000;
    for (const [id, r] of Object.entries(this.state.rooms))
      if (r.phase === "ended" && now - (r.endedAt ?? r.end) > day) {
        for (const p of Object.values(this.state.players)) if (p.room === id) delete p.room;
        delete this.state.rooms[id];
      }
    for (const [id, p] of Object.entries(this.state.players))
      if (now - p.seen > 3600000 && (!p.room || !this.state.rooms[p.room])) delete this.state.players[id];
    for (const [id, op] of Object.entries(this.state.ops)) if (now - op.at > day) delete this.state.ops[id];
    for (const [id, s] of Object.entries(this.state.shares)) if (now - (s.at ?? 0) > day) delete this.state.shares[id];
    // Welcome tombstones prevent repeat awards; unclaimed entitlements remain payable.
    for (const [id, e] of Object.entries(this.state.entitlements))
      if (e.campaign !== "welcome" && e.claimed && now - (e.at ?? 0) > day) delete this.state.entitlements[id];
    const today = new Date(now).toISOString().slice(0, 10);
    for (const [id, s] of Object.entries(this.state.scores)) if (s.day !== today) delete this.state.scores[id];
  }
  current(i: Identity) {
    const p = this.player(i);
    const r = p.room ? this.state.rooms[p.room] : undefined;
    return { p, r, m: r?.members.find((m) => m.badge === i.badge) };
  }
  poll(i: Identity, b: any) {
    this.observations(i, b.nearby);
    this.form(i.ns);
    return this.view(i);
  }
  action(i: Identity, b: any) {
    this.tick();
    const before = this.current(i);
    const wasFresh = this.fresh(before.p);
    before.p.seen = this.now();
    return this.op(i, b.op, [b.action, b.target ?? null, b.id ?? null], () => {
      if (b.action === "claim") {
        const e = this.state.entitlements[b.id];
        if (!e || e.user !== i.user || e.ns !== i.ns || e.app !== i.app)
          throw new RuleError("bad_entitlement");
        const amount = e.claimed ? 0 : e.amount;
        e.claimed = true;
        return { amount };
      }
      if (b.action === "ready") {
        if (before.r && before.r.phase !== "ended")
          throw new RuleError("already_playing");
        if (before.r) {
          delete before.p.room;
        }
        before.p.ready = true;
        this.form(i.ns);
        return this.view(i);
      }
      const { p, r, m } = this.current(i);
      if (b.action === "leave" && !r) {
        p.ready = false;
        return this.view(i);
      }
      if (!r || !m) throw new RuleError("no_round");
      if (b.action === "leave") {
        p.ready = false;
        p.seen = this.now() - FRESH;
        m.connected = false;
        m.left = true;
        if (m.role === "lazarus")
          this.finish(r, "VOID", undefined, "Lazarus left");
        const result = this.view(i);
        delete p.room;
        return result;
      }
      if (!wasFresh || !m.connected) throw new RuleError("disconnected");
      if (b.action === "ack") {
        if (r.phase !== "preparing") throw new RuleError("not_preparing");
        m.ack = true;
        return this.view(i);
      }
      if (b.action === "quarantine") {
        if (r.phase !== "active") throw new RuleError("not_active");
        if (m.role === "lazarus" || m.status !== "tainted")
          throw new RuleError("not_tainted");
        m.status = "quarantined";
        return this.view(i);
      }
      if (r.phase !== "active") throw new RuleError("not_active");
      if (b.action !== "screen") throw new RuleError("bad_action");
      const target = r.members.find((t) => t.badge === b.target);
      if (!target || target === m) throw new RuleError("bad_target");
      if (m.role === "lazarus") throw new RuleError("role_denied");
      const tp = this.peer(i.ns, target.badge)!;
      if (!target.connected || !this.fresh(tp) || this.now() - p.observed > OBS ||
          !p.nearby.some(o => o.id === tp.badge && o.rssi >= -78))
        throw new RuleError("not_nearby");
      if (target.status === "quarantined")
        return { ...this.view(i), screen: { result: "QUARANTINED" } };
      if (m.credits < 1) throw new RuleError("no_credits");
      m.credits--;
      let screen: any = { result: "CLEAN", age_s: Math.floor((this.now() - (r.screenings[`${m.badge}:${target.badge}`] ?? r.start)) / 1000) };
      if (
        target.role === "lazarus" &&
        this.now() - r.start >= this.config.latentMs
      ) {
        screen = { result: "CAUGHT" };
        this.finish(r, "CAUGHT", m);
      } else if (target.status === "tainted") {
        target.status = "quarantined";
        const upstream = this.peer(i.ns, target.infector!)!;
        screen = {
          result: "TAINTED",
          clue: {
            id: target.infector,
            name: upstream?.name ?? target.infector,
            sid: upstream?.sid,
            hop: target.hop,
          },
        };
        if (r.ranked && r.ns === "prod")
          this.entitlement(
            i,
            `quarantine:${r.id}:${target.badge}`,
            this.config.quarantineAmount,
          );
      }
      r.screenings[`${m.badge}:${target.badge}`] = this.now();
      return { ...this.view(i), screen };
    });
  }
  view(i: Identity) {
    const { p, r, m } = this.current(i);
    const nearby = p.nearby
      .map((o) => this.peer(i.ns, o.id))
      .filter(
        (q): q is Player =>
          !!q &&
          q.app === "lazarus" &&
          this.fresh(q) &&
          (!r || r.members.some((m) => m.badge === q.badge)),
      )
      .slice(0, 20)
      .map((q) => ({
        id: q.badge,
        sid: q.sid,
        n: q.name,
        band:
          p.nearby.find((o) => o.id === q.badge)!.rssi >= -68
            ? "close"
            : "near",
        age_s: r
          ? Math.floor(
              (this.now() -
                (r.screenings[`${p.badge}:${q.badge}`] ?? r.start)) /
                1000,
            )
          : 0,
      }));
    const awards = Object.values(this.state.entitlements)
      .filter(
        (e) =>
          e.user === i.user &&
          e.ns === i.ns &&
          e.app === i.app &&
          !e.claimed &&
          e.campaign !== "welcome",
      )
      .slice(0, 2)
      .map((e) => ({ id: e.id, amount: e.amount }));
    return {
      online: true,
      big_drop_in_s: this.bigIn(),
      ready: p.ready,
      nearby,
      awards,
      room:
        r && m
          ? {
              id: r.id,
              phase: r.phase,
              result: r.result ?? null,
              reason: r.reason ?? null,
              role: m.role,
              status: m.status,
              heat: Math.floor((m.heat / this.config.exposureMs) * 100),
              credits: m.credits,
              ack: m.ack,
              ranked: r.ranked,
              big: r.big,
              pot: i.ns === "demo" ? 0 : r.pot,
              count: r.members.length,
              in_s: Math.max(
                0,
                Math.ceil(
                  ((r.phase === "preparing" ? r.start : r.end) - this.now()) /
                    1000,
                ),
              ),
              drained: m.role === "lazarus" ? r.infected.length : 0,
              threshold: r.threshold,
              winner: r.winner ? this.peer(i.ns, r.winner)?.name : null,
            }
          : null,
    };
  }
  score(i: Identity, b: any) {
    return this.op(i, b.op, ["score", b.score, b.wave, b.boss, b.seconds], () => {
      if (
        !Number.isInteger(b.score) ||
        b.score < 0 ||
        b.score > scoreCap(b.wave, b.seconds, b.boss) ||
        !Number.isInteger(b.seconds) || b.seconds < 1 || b.seconds > 86400 ||
        !Number.isInteger(b.wave) ||
        b.wave < 1 ||
        b.wave > 999 ||
        typeof b.boss !== "boolean"
      )
        throw new RuleError("bad_score");
      const p = this.player(i),
        day = new Date(this.now()).toISOString().slice(0, 10),
        key = `${i.ns}:${day}:${i.user}`,
        old = this.state.scores[key];
      if (!old || !Number.isInteger(old.seconds) || old.s > scoreCap(old.wave, old.seconds, old.boss) || old.s < b.score)
        this.state.scores[key] = {
          n: p.name,
          s: b.score,
          wave: b.wave,
          boss: b.boss,
          seconds: b.seconds,
          day,
          user: i.user,
          ns: i.ns,
        };
      const top = this.top(i.ns, 1000);
      return {
        best: this.state.scores[key].s,
        rank: top.findIndex((s) => s.user === i.user) + 1,
        top: top.slice(0, 5).map((s) => ({ n: s.n, s: s.s })),
      };
    });
  }
  top(ns: string, limit = 5) {
    const day = new Date(this.now()).toISOString().slice(0, 10);
    return Object.values(this.state.scores)
      .filter((s) => s.ns === ns && s.day === day && Number.isInteger(s.seconds) && s.s <= scoreCap(s.wave, s.seconds, s.boss))
      .sort((a, b) => b.s - a.s || a.user.localeCompare(b.user))
      .slice(0, limit);
  }
}
export function ascii(v: unknown, max: number) {
  return typeof v === "string"
    ? v.replace(/[^\x20-\x7e]/g, "").slice(0, max)
    : "";
}

// 24 enemies total 600 points per wave. Bosses first arrive at 12 s.
// Autofire is at most four shots/s, with at most 40 points per shot.
export function scoreCap(wave: number, seconds: number, boss: boolean) {
  return Math.min(wave * 600 + (boss ? Math.floor(seconds / 12) * 300 : 0), seconds * 160);
}
