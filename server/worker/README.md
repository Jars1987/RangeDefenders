# Worker adapter scaffold

Not deployed. `bun run typecheck` in server/ checks this adapter with the engine.
The Worker forwards all API requests to one Durable Object, which owns a durable
snapshot and schedules a one-second alarm. Demo authentication is never enabled.

Before deployment, provision a Cloudflare account, replace PUBLIC_ORIGIN in
wrangler.toml, configure a short HTTPS result origin serving the same /r/ route,
and supply ESCROW_KEY as a Worker secret. WELCOME_AMOUNT defaults to 0 until an
organizer authorizes an award cap. Wrangler is intentionally not installed because
this run does not deploy or invoke it. Serve the sim locally with Bun.

This is a scaffold, not a load-tested production deployment. One object holds the
conference state; split room ownership only if measurements justify it.
