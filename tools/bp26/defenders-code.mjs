import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function codeFor(score, badgeId, day, wave) {
  const text = `${score}|${badgeId ?? 'anon'}|${day ?? 0}|${wave}|sd1`;
  let hash = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(text)) {
    hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
  }
  let code = '';
  for (let i = 0; i < 6; i++) {
    code = alphabet[hash & 31] + code;
    hash >>>= 5;
  }
  return code;
}

function test() {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const vectors = JSON.parse(readFileSync(new URL('../../tests/defenders/code-vectors.json', import.meta.url)));
  for (const v of vectors) {
    assert.equal(codeFor(v.score, v.badgeId, v.day, v.wave), v.code);
  }
  const lua = spawnSync(process.env.LUA ?? '/opt/homebrew/opt/lua@5.4/bin/lua',
    ['tests/defenders/codes.lua'], { cwd: root, encoding: 'utf8' });
  assert.equal(lua.status, 0, lua.stderr || lua.error?.message);
  assert.deepEqual(lua.stdout.trim().split(/\r?\n/), vectors.map(v => v.code));
  console.log(`PASS ${vectors.length}/${vectors.length} fixed vectors agree in JS and Lua`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (!args.length || (args.length === 1 && args[0] === '--test')) test();
  else if (args.length === 4 && [args[0], args[2], args[3]].every(v => /^\d+$/.test(v) && Number(v) <= 2147483647)) {
    console.log(codeFor(Number(args[0]), args[1], Number(args[2]), Number(args[3])));
  } else {
    console.error('Usage: node tools/bp26/defenders-code.mjs <score> <badgeId> <day> <wave> | --test');
    process.exitCode = 1;
  }
}
