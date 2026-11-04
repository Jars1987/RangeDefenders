# BP26 game server

From this directory:

```sh
bun install
bun test
bun run typecheck
bun run demo
```

The demo serves the browser sim at http://localhost:8787/ and booth page at
http://localhost:8787/live?ns=demo. If 8787 is occupied it selects the next available
port through 8797 and prints the URL. `PORT` explicitly pins a port and disables
fallback. Production API starts with `bun run start` and uses `bp26.sqlite`.

## Authentication

All /v1 routes require Solana OS Ed25519 badge-http-v1 signed headers. The verifier
fetches the public key from https://solana.com/breakpoint/badge/api/http/key,
checks the raw UTF-8 body hash, method, full public URL, app, badge, user, timestamp
within 60 seconds, and a durable single-use request nonce. Set PUBLIC_ORIGIN to
the exact external HTTPS origin behind a proxy. Forwarded headers are not trusted.
Body fields never select badge/user identity. Cross-app requests are rejected.

DEMO=1 enables separate identities supplied by X-Demo-Badge and X-Demo-User.
Those requests operate only on the demo namespace, never issue paid entitlements,
and never enqueue escrow payments. Requests without demo headers still require
production signatures. /demo/session creates six isolated demo identities and bots;
it is absent when DEMO is off. Public routes: /live, /r/:code, /go/install,
/go/screening. The sim and its assets require DEMO=1.

## Shared routes

- POST /v1/hello: `{app,name,x,v}`. Returns welcome `{amount,eligible}`,
  big_drop_in_s, and optional msg. app is lazarus or defenders.
- POST /v1/welcome/claim: `{app,op}`. Returns amount, once per user/app/campaign.
  The same operation replays its original response; a different op returns zero.
- POST /v1/share: `{app,kind,data}`. kind is install, caught, escaped, or score.
  Win claims are checked against server results, scores against the stored board.
  Returns url for /r/:code, at most 40 bytes. SHORT_ORIGIN may point to a short HTTPS
  host routed to this service. A longer host returns short_origin_required.
- POST /v1/defenders/score: `{score,wave,boss,op}`. Returns best, rank and top five.
  Informal board only; no automatic daily payout. A booth organizer settles finals.
- GET /v1/defenders/top: today's top five and day (UTC YYYY-MM-DD).
- GET /live: current/last Lazarus rooms, hourly Big Drop countdown, Defenders top ten.
- GET /r/:code: result, install link, optional Post on X intent. No generated images.
- GET /go/install?a=lazarus|defenders: store redirect.
- GET /go/screening?a=lazarus|defenders: Range screening redirect with specified UTMs.

Every JSON response includes ok; errors include a stable error code. Every /v1
response is below 3 KB, requests below 2 KB. Calls are serialized with scheduler
updates before the SQLite snapshot is committed.

## Lazarus routes

### POST /v1/lazarus/poll

```json
{"nearby":[{"id":"7K2Q9M","rssi":-52,"bridged":false}]}
```

Call every five seconds. The server timestamps observations; clients cannot submit
exposure durations. Production discards bridged peers, RSSI 0, and emulator peers. Demo may simulate
those observations but can never pay.
At most 20 observations are retained. Responses include online, ready,
big_drop_in_s, nearby `[ {id,n,band,age_s} ]`, awards `[ {id,amount} ]`, and room or
null. Radar lists checked-in peers in the current room. Names are capped at 20 ASCII
characters. Bands are close or near, not distance estimates.

room fields: id, phase (preparing/active/ended), result (CAUGHT/ESCAPED/VOID/null),
reason, role (only the caller's), status (clean/tainted/quarantined), heat (0-100),
credits, ack, ranked, big, pot, count, in_s (relative seconds), drained and threshold
(source progress only), winner (display name). No predecessor or other roles leak
through polls or neutral mesh messages.

### POST /v1/lazarus/action

```json
{"action":"screen","target":"7K2Q9M","op":"a_fresh_stable_random_id"}
```

Actions:

- ready: enter a room or rematch. At least four fresh ready distinct users must be
  connected through reciprocal observations. New players can join preparation up to
  20 members. Four or five is unranked; six or more can earn a pot.
- ack: acknowledge preparation. Lazarus must acknowledge before the 30-second
  countdown ends; otherwise VOID. No screening or exposure during preparation.
- screen: target must be fresh and mutually observed at RSSI >= -78. Investigators
  start with one credit, recover one each 20 seconds, capped at three. Tainted and
  quarantined investigators keep screening. Source screens CLEAN for 12 seconds.
  Adds screen `{result,age_s}` or TAINTED `{clue:{id,name,hop}}`. A TAINTED result
  quarantines that victim and reveals one upstream clue. A first qualifying
  quarantine grants its hunter one entitlement. A caught source ends the round.
- quarantine: self-quarantine, no reward. Stops spreading and protects funds.
- claim: use id from awards to redeem its amount for the client's lamps.award call.
- leave: leave a round; source departure makes it VOID.

Actions require op (4-64 ASCII alphanumerics, underscore or hyphen). Reuse it on
transport timeout; changing the payload returns op_conflict. A disconnected player
must reconcile with a fresh poll before prize actions resume. Error codes include
hello_required, no_round, not_active, not_preparing, disconnected, not_nearby,
no_credits, bad_target, role_denied, bad_entitlement and bad_op.

Reciprocal RSSI >= -68 builds 18 seconds of exposure, draining at half speed apart.
Observations expire after six seconds. A scheduler gap longer than six seconds adds
no exposure. App presence expires at 15 seconds. A missing source makes VOID.
Unique infections >= max(2, ceil(60% of investigators)) makes ESCAPED. The four-minute
timeout without that threshold makes VOID. Source receives its scaled prize only
on ESCAPED; CAUGHT pays the catcher. Quarantine rewards are bounded by one per victim.

## Schedule and rewards

A new room formed during the first 60 seconds of an hourly UTC boundary is that
namespace's Big Drop (one per hour), with triple the configured pot. Existing active
rounds continue. Time relative to the next :00 is returned on hello/poll and /live.

WELCOME_AMOUNT defaults to 0. Enable it only after organizers grant the app an award
cap. ROUND_POT defaults to 100. Demo pots are displayed as zero and never pay.
ESCROW_KEY is read only from the environment. Without it, production payouts remain
pending; no invented mock payment is reported as paid. The SQLite ledger is saved
before a call to /api/escrow/pay with its stable round key, then marked paid only
after success. An uncertain response is safely retried. Tests inject MockEscrow.

Small entitlement claims and OS awards cannot form one atomic transaction. The
badge records its attempt before lamps.award, retries needsX after relaunch, and
avoids duplicate mint attempts after an uncertain callback. An app crash between
claim and award can lose a small reward. Organizers' award caps still apply.

## Browser and adapter checks

```sh
bun sim-smoke.ts
CHROMIUM_PATH=/path/to/chrome bun browser-smoke.ts
```

sim-smoke executes the real browser JavaScript in a DOM with the real Wasmoon VM
against the local demo, completing CAUGHT and ESCAPED. It is not a visual browser.
browser-smoke uses an isolated Chromium profile to play both outcomes, check mobile
overflow, and save screenshots/video under /private/tmp/bp26-browser. This session's
macOS sandbox denies Chromium Mach port registration, so visual checks must run in
an attended browser outside that sandbox. Set BP26_URL if the port differs.

The Worker/Durable Object scaffold is under worker/, typechecks with the same
engine, and is not deployed. Local state is one SQLite snapshot with a durable
operation/nonce/payout ledger. High-volume production room sharding is not included.
