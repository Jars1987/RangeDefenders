import { Engine, type Identity } from "./engine";
type Position = { x: number; y: number };
type Session = {
  id: string;
  players: Identity[];
  positions: Position[];
  seen: number;
  seq: number;
};
export class Demo {
  sessions = new Map<string, Session>();
  constructor(public e: Engine) {}
  async handle(req: Request) {
    const b = await req.json(),
      id = b.session;
    if (typeof id !== "string" || !/^[a-z0-9]{6,12}$/.test(id))
      return Response.json(
        { ok: false, error: "bad_session" },
        { status: 400 },
      );
    let s = this.sessions.get(id);
    if (!s) {
      if (this.sessions.size >= 50)
        return Response.json(
          { ok: false, error: "demo_full" },
          { status: 429 },
        );
      const players: Identity[] = Array.from({ length: 6 }, (_, n) => ({
        badge: `s${id}_${n}`,
        user: `s${id}_u${n}`,
        app: "lazarus",
        ns: "demo",
      }));
      s = {
        id,
        players,
        positions: [
          { x: 45, y: 55 },
          { x: 60, y: 25 },
          { x: 30, y: 27 },
          { x: 76, y: 54 },
          { x: 23, y: 75 },
          { x: 64, y: 79 },
        ],
        seen: Date.now(),
        seq: 0,
      };
      this.sessions.set(id, s);
      players.forEach((i, n) =>
        this.e.hello(i, {
          name:
            n === 0
              ? "@you"
              : ["", "@relay", "@mixer", "@vault", "@broker", "@wallet"][n],
          x: null,
        }),
      );
    }
    s.seen = Date.now();
    if (Array.isArray(b.positions) && b.positions.length === 6)
      s.positions = b.positions.map((p: any) => ({
        x: Math.max(0, Math.min(100, Number(p.x) || 0)),
        y: Math.max(0, Math.min(100, Number(p.y) || 0)),
      }));
    return Response.json({
      ok: true,
      players: s.players.map((i, n) => ({
        id: i.badge,
        n: n === 0 ? "You" : this.e.player(i).name,
        status: n === 0 ? "you" : (this.e.current(i).m?.status ?? "ready"),
        x: s!.positions[n].x,
        y: s!.positions[n].y,
      })),
      nearby: this.nearby(s, 0),
    });
  }
  nearby(s: Session, j: number) {
    return s.players.flatMap((p, k) => {
      if (j === k) return [];
      const a = s.positions[j],
        b = s.positions[k],
        d = Math.hypot(a.x - b.x, a.y - b.y);
      return d < 85
        ? [
            {
              id: p.badge,
              name: this.e.player(p).name,
              rssi: d < 48 ? -52 : -74,
              kind: "badge",
              bridged: false,
            },
          ]
        : [];
    });
  }
  tick() {
    for (const [id, s] of this.sessions) {
      if (Date.now() - s.seen > 30000) {
        this.sessions.delete(id);
        continue;
      }
      // Bots use the same poll/action rules as a badge. They never choose a victim to screen.
      const human = this.e.player(s.players[0]),
        rematch = human.ready && !human.room;
      for (let n = 1; n < 6; n++) {
        const i = s.players[n];
        this.e.poll(i, { nearby: this.nearby(s, n) });
        const { p, r, m } = this.e.current(i);
        if (!p.ready && (!r || (r.phase === "ended" && rematch)))
          this.e.action(i, { action: "ready", op: `bot_${s.seq++}` });
        if (r?.phase === "preparing" && m?.role === "lazarus" && !m.ack)
          this.e.action(i, { action: "ack", op: `bot_${s.seq++}` });
      }
    }
  }
}
