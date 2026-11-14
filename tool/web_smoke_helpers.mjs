import fs from 'node:fs';
import path from 'node:path';

export const chromeStartupTimeoutMs = 60_000;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function isCatalogHomeReady(text) {
  // Flutter can expose headings as accessibility labels rather than innerText.
  // These two actions are visible only on the catalog-backed landing page.
  return text.includes('興味から旅行を作る') && text.includes('もっと見る');
}

function debugPort(profile, stderr) {
  try {
    const value = fs.readFileSync(path.join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0].trim();
    const port = Number(value);
    if (/^\d+$/.test(value) && port > 0 && port <= 65535) return port;
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  // Chrome also announces its DevTools endpoint on stderr. The profile file
  // and the HTTP server are not guaranteed to become ready at the same time.
  const endpoint = stderr.match(/DevTools listening on (ws:\/\/\S+)/)?.[1];
  if (endpoint) {
    const port = Number(new URL(endpoint).port);
    if (port > 0 && port <= 65535) return port;
  }
}

async function readPages(port, timeoutMs) {
  const response = await fetch(`http://127.0.0.1:${port}/json/list`, {
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw Error(`DevTools HTTP ${response.status}`);
  return response.json();
}

export async function waitForChromePage({
  chrome,
  profile,
  chromePath,
  getStartupError = () => undefined,
  getStderr = () => '',
  timeoutMs = chromeStartupTimeoutMs,
  pollMs = 200,
  fetchPages = readPages,
}) {
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw Error('CHROME_STARTUP_TIMEOUT_MS must be a positive number');
  }
  const deadline = performance.now() + timeoutMs;
  let lastProbeError;
  while (performance.now() < deadline) {
    const error = getStartupError();
    if (error) throw Error(`Could not launch Chrome (${chromePath}): ${error.message}`, { cause: error });
    if (chrome.exitCode !== null || chrome.signalCode !== null) {
      throw Error(`Chrome exited before DevTools became ready (${chromePath}, exit=${chrome.exitCode}, signal=${chrome.signalCode})\n${getStderr().trim()}`);
    }
    const port = debugPort(profile, getStderr());
    if (port) {
      try {
        const pages = await fetchPages(port, Math.max(1, Math.ceil(Math.min(1000, deadline - performance.now()))));
        const page = Array.isArray(pages) && pages.find((page) => page.type === 'page' && page.webSocketDebuggerUrl);
        if (page) return page;
      } catch (error) {
        // A port file can exist before Chrome accepts HTTP connections.
        lastProbeError = error;
      }
    }
    await pause(Math.max(0, Math.min(pollMs, deadline - performance.now())));
  }
  throw Error(`Chrome DevTools did not become ready within ${timeoutMs}ms (${chromePath}, exit=${chrome.exitCode}, signal=${chrome.signalCode})${lastProbeError ? `\nLast DevTools probe: ${lastProbeError.message}` : ''}\n${getStderr().trim()}`);
}
