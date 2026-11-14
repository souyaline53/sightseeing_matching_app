import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { chromeStartupTimeoutMs, isCatalogHomeReady, waitForChromePage } from './web_smoke_helpers.mjs';

function startup(t, overrides = {}) {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'tabisaki-chrome-startup-test-'));
  t.after(() => fs.rmSync(profile, { recursive: true, force: true }));
  return {
    chrome: { exitCode: null, signalCode: null },
    profile,
    chromePath: 'test-chrome',
    timeoutMs: 2000,
    pollMs: 5,
    ...overrides,
  };
}
const page = { type: 'page', webSocketDebuggerUrl: 'ws://127.0.0.1:9222/devtools/page/test' };

test('waits for delayed startup despite D-Bus diagnostics; a port alone is not readiness', async (t) => {
  const options = startup(t, { getStderr: () => 'ERROR:dbus/bus.cc Failed to connect to the bus' });
  let probes = 0;
  const timer = setTimeout(() => fs.writeFileSync(path.join(options.profile, 'DevToolsActivePort'), '9222\n/devtools/browser/test'), 20);
  t.after(() => clearTimeout(timer));
  const result = await waitForChromePage({
    ...options,
    fetchPages: async (port) => {
      assert.equal(port, 9222);
      if (++probes === 1) throw Error('ECONNREFUSED');
      if (probes === 2) return [{ type: 'browser' }, { type: 'page' }];
      return [page];
    },
  });
  assert.equal(result, page);
  assert.equal(probes, 3);
  assert.equal(chromeStartupTimeoutMs, 60_000);
});

test('does not mistake an empty or partially written port file for startup failure', async (t) => {
  const options = startup(t);
  const file = path.join(options.profile, 'DevToolsActivePort');
  fs.writeFileSync(file, '');
  const timer = setTimeout(() => fs.writeFileSync(file, '9222\n'), 20);
  t.after(() => clearTimeout(timer));
  const result = await waitForChromePage({ ...options, fetchPages: async () => [page] });
  assert.equal(result, page);
});

test('can discover DevTools from Chrome stderr before the port file appears', async (t) => {
  const options = startup(t, { getStderr: () => 'DevTools listening on ws://127.0.0.1:9222/devtools/browser/test\n' });
  const result = await waitForChromePage({ ...options, fetchPages: async (port) => {
    assert.equal(port, 9222);
    return [page];
  } });
  assert.equal(result, page);
});

test('reports launch errors immediately with the executable path', async (t) => {
  await assert.rejects(waitForChromePage(startup(t, {
    getStartupError: () => Error('spawn ENOENT'),
  })), /Could not launch Chrome \(test-chrome\): spawn ENOENT/);
});

test('distinguishes an exited browser from a running browser that is not ready', async (t) => {
  await assert.rejects(waitForChromePage(startup(t, {
    chrome: { exitCode: 1, signalCode: null },
    getStderr: () => 'browser crashed',
  })), /Chrome exited before DevTools became ready .*exit=1[\s\S]*browser crashed/);
});

test('timeout retains process state and the last HTTP probe error for diagnosis', async (t) => {
  const options = startup(t, { timeoutMs: 30, getStderr: () => 'D-Bus diagnostic' });
  fs.writeFileSync(path.join(options.profile, 'DevToolsActivePort'), '9222\n');
  await assert.rejects(waitForChromePage({
    ...options,
    fetchPages: async () => { throw Error('HTTP server unavailable'); },
  }), /within 30ms .*exit=null, signal=null[\s\S]*HTTP server unavailable[\s\S]*D-Bus diagnostic/);
});

test('home readiness follows the new catalog-backed home and rejects loading or other pages', () => {
  assert.equal(isCatalogHomeReady('TABISAKI\n興味から旅行を作る\nおすすめの観光地\nもっと見る'), true);
  for (const text of ['', '新しい旅を探す', '興味から旅行を作る', 'おすすめの観光地', 'あなたにおすすめの観光地', 'クラウドの観光地情報を読み込めませんでした。']) {
    assert.equal(isCatalogHomeReady(text), false, text);
  }
});

test('home readiness also accepts the actual Flutter semantics text without heading text', () => {
  assert.equal(isCatalogHomeReady('TABISAKI\nまだ知らない、とっておきへ。 北海道で、 何する？ 自然も、歴史も、グルメも。 興味から旅行を作る 好きなことから、次の行き先へ。\nもっと見る'), true);
});
