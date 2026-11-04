import type { Payout } from "./engine";
export interface Escrow {
  pay(p: Payout): Promise<void>;
}
export class MockEscrow implements Escrow {
  paid = new Map<string, Payout>();
  async pay(p: Payout) {
    if (!this.paid.has(p.key)) this.paid.set(p.key, { ...p });
  }
}
export class HttpEscrow implements Escrow {
  constructor(
    private key: string,
    private origin = "https://solana.com/breakpoint/badge",
  ) {}
  async pay(p: Payout) {
    const r = await fetch(`${this.origin}/api/escrow/pay`, {
      signal: AbortSignal.timeout(4000),
      method: "POST",
      headers: {
        authorization: `Bearer ${this.key}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        to: p.to,
        amount: p.amount,
        memo: p.memo,
        key: p.key,
      }),
    });
    const b = await r.json();
    if (!r.ok || b.ok === false) throw Error("escrow_failed");
  }
}
