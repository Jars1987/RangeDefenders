// Scaffold only. Provision the Durable Object and set PUBLIC_ORIGIN before deployment.
import type {
  DurableObjectNamespace,
  DurableObjectState,
} from "@cloudflare/workers-types";
import { Engine, emptyState, type State } from "../src/engine";
import { Verifier } from "../src/auth";
import { API } from "../src/api";
import { HttpEscrow } from "../src/escrow";
interface Env {
  GAME: DurableObjectNamespace;
  PUBLIC_ORIGIN: string;
  SHORT_ORIGIN?: string;
  ESCROW_KEY?: string;
  WELCOME_AMOUNT?: string;
}
export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const id = env.GAME.idFromName("bp26-production");
    return env.GAME.get(id).fetch(req as never) as unknown as Promise<Response>;
  },
};
export class GameRoom {
  api!: API;
  ready: Promise<void>;
  constructor(
    private state: DurableObjectState,
    private env: Env,
  ) {
    this.ready = state.blockConcurrencyWhile(async () => {
      const data = (await state.storage.get<State>("snapshot")) ?? emptyState();
      const store = {
        load: () => data,
        save: async (s: State) => {
          await state.storage.put("snapshot", s);
        },
      };
      const e = new Engine(data, {
        welcomeAmount: Number(env.WELCOME_AMOUNT ?? 0),
      });
      this.api = new API(
        e,
        store,
        new Verifier(data, { publicOrigin: env.PUBLIC_ORIGIN }),
        {
          publicOrigin: env.PUBLIC_ORIGIN,
          shortOrigin: env.SHORT_ORIGIN,
          escrow: env.ESCROW_KEY ? new HttpEscrow(env.ESCROW_KEY) : undefined,
        },
      );
      if (!(await state.storage.getAlarm()))
        await state.storage.setAlarm(Date.now() + 1000);
    });
  }
  async fetch(req: Request) {
    await this.ready;
    return this.api.handle(req);
  }
  async alarm() {
    await this.ready;
    await this.api.advance();
    await this.state.storage.setAlarm(Date.now() + 1000);
  }
}
