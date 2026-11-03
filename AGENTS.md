# Range badge games

If AGENTS.local.md exists in this directory, read it before anything else.

## Overview

DEF CON reference games live in scripts/. BP26 packages use Solana OS 0.5.5 widgets and signed HTTP, with a transport-independent rules engine in server/src/engine.ts.

## Project-specific rules

- Keep scripts/, media/, and legacy tools/ files unchanged during BP26 work.
- apps/defenders/ holds Solana Defenders for BP26; its headless tests are tests/defenders/run.lua.
- BP26 on-screen copy is printable ASCII and US English. Use !LAMPs.
- Badge callbacks must stay below 200,000 instructions and 64 live widgets. Treat Lua numbers as 32-bit; use relative durations.
- Production authentication and demo identities are separate namespaces. Demo never pays.
- The executor brief forbids commits, pushes, changelogs, and todo entries.

## Long-run / commit config

- **Smoke per batch:** `cd server && bun test`
- **Final pass:** `cd server && bun run typecheck && bun test`; `/opt/homebrew/opt/lua@5.4/bin/lua tools/bp26/harness.lua all` from the root.
- **Docs:** `BP26.md`, `server/README.md`, `docs/bp26/` references.
- **Trunk flow:** direct. Do not create a PR without an explicit request.
- **Out-of-scope paths:** scripts/** media/** apps/defenders/** tests/defenders/**
- **Commit message shape:** imperative subject under 72 characters; human authorship only.
