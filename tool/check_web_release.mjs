// Read-only smoke test of the compiled app in a fresh browser. No manual
// FlutterFire registration: the real generated entry point must do that.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { isCatalogHomeReady, waitForChromePage } from "./web_smoke_helpers.mjs";
const url =
  process.argv.find((a) => a.startsWith("https://")) ??
  "https://sightseeing-matching-prototype.web.app";
const localBuild = process.argv.includes("--local-build");
const journeyQueryFile = process.argv.find((a) => a.startsWith("--journey-query="))?.slice("--journey-query=".length);
const journeyQuery = journeyQueryFile ? JSON.parse(fs.readFileSync(journeyQueryFile, "utf8")) : null;
const profile = fs.mkdtempSync(path.join(os.tmpdir(), "tabisaki-web-smoke-"));
const chromePath =
  process.env.CHROME_EXECUTABLE ||
  (process.platform === "darwin"
    ? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    : "google-chrome");
const chrome = spawn(
  chromePath,
  [
    "--headless=new",
    ...(process.env.CHROME_NO_SANDBOX === "true" ? ["--no-sandbox"] : []),
    "--remote-debugging-port=0",
    `--user-data-dir=${profile}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-extensions",
    "--disable-background-networking",
    ...(process.platform === "linux" ? ["--disable-dev-shm-usage"] : []),
    "about:blank",
  ],
  { stdio: ["ignore", "ignore", "pipe"] },
);
let startupError;
let chromeStderr = "";
chrome.stderr.setEncoding("utf8");
chrome.stderr.on("data", (chunk) => {
  chromeStderr = (chromeStderr + chunk).slice(-8000);
});
chrome.on("error", (error) => {
  startupError = error;
});
let socket;
let sequence = 0;
const pending = new Map();
const errors = [];
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(Error(`Browser command timed out: ${method}`));
    }, 25000);
    pending.set(id, { resolve, reject, timer });
    socket.send(JSON.stringify({ id, method, params }));
  });
try {
  const page = await waitForChromePage({
    chrome,
    profile,
    chromePath,
    getStartupError: () => startupError,
    getStderr: () => chromeStderr,
    ...(process.env.CHROME_STARTUP_TIMEOUT_MS
      ? { timeoutMs: Number(process.env.CHROME_STARTUP_TIMEOUT_MS) }
      : {}),
  });
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = reject;
  });
  socket.onmessage = ({ data }) => {
    const m = JSON.parse(data);
    if (m.id) {
      const p = pending.get(m.id);
      if (p) {
        pending.delete(m.id);
        clearTimeout(p.timer);
        m.error
          ? p.reject(Error(JSON.stringify(m.error)))
          : p.resolve(m.result);
      }
      return;
    }
    const p = m.params || {};
    if (m.method === "Runtime.exceptionThrown")
      errors.push(
        p.exceptionDetails.exception?.description || p.exceptionDetails.text,
      );
    if (m.method === "Runtime.consoleAPICalled") {
      const text = p.args.map((a) => a.value ?? a.description ?? "").join(" ");
      if (
        /Firebase initialization failed|cloud_firestore|core\/not-initialized|MissingPluginException/.test(
          text,
        )
      )
        errors.push(text);
    }
    if (m.method === "Fetch.requestPaused") {
      const pathname = decodeURIComponent(new URL(p.request.url).pathname);
      const root = path.resolve("build/web"),
        file = path.resolve(
          root,
          "." + (pathname === "/" ? "/index.html" : pathname),
        );
      if (
        localBuild &&
        file.startsWith(root + path.sep) &&
        fs.existsSync(file) &&
        fs.statSync(file).isFile()
      ) {
        const types = {
          ".html": "text/html; charset=utf-8",
          ".js": "text/javascript; charset=utf-8",
          ".mjs": "text/javascript; charset=utf-8",
          ".json": "application/json",
          ".wasm": "application/wasm",
          ".css": "text/css",
          ".png": "image/png",
          ".svg": "image/svg+xml",
          ".woff2": "font/woff2",
          ".ttf": "font/ttf",
        };
        send("Fetch.fulfillRequest", {
          requestId: p.requestId,
          responseCode: 200,
          responseHeaders: [
            {
              name: "Content-Type",
              value: types[path.extname(file)] ?? "application/octet-stream",
            },
          ],
          body: fs.readFileSync(file).toString("base64"),
        }).catch((e) => errors.push(e.message));
      } else
        send("Fetch.continueRequest", { requestId: p.requestId }).catch((e) =>
          errors.push(e.message),
        );
    }
  };
  await Promise.all([
    send("Runtime.enable"),
    send("Page.enable"),
    send("Network.enable"),
  ]);
  await send("Network.setCacheDisabled", { cacheDisabled: true });
  await send("Network.setBypassServiceWorker", { bypass: true });
  if (localBuild)
    await send("Fetch.enable", {
      patterns: [
        { urlPattern: `${new URL(url).origin}/*`, requestStage: "Request" },
      ],
    });
  await send("Page.navigate", { url });
  let text = "";
  for (let n = 0; n < 50; n++) {
    await pause(1000);
    const result = await send("Runtime.evaluate", {
      expression:
        "document.querySelector('flt-semantics-placeholder')?.click(); document.body.innerText",
      returnByValue: true,
    });
    text = result.result?.value ?? "";
    if (errors.length) throw Error(errors.join("\n"));
    if (text.includes("クラウドの観光地情報を読み込めませんでした"))
      throw Error("The compiled app cannot load the catalog");
    if (isCatalogHomeReady(text)) break;
  }
  if (!isCatalogHomeReady(text))
    throw Error(
      `Catalog-backed home did not become ready: ${text.slice(0, 600)}`,
    );
  const expression = `(async()=>{
   const core=globalThis.firebase_core,ff=globalThis.firebase_firestore,st=globalThis.firebase_storage;
   if(!core||!ff||!st)throw Error('Firebase Web SDK registration is missing');
   const app=core.getApp(),db=ff.getFirestore(app);
   const catalog=await ff.getDocs(ff.query(ff.collection(db,'sightseeing_spot'),ff.limit(1)));
   if(catalog.empty)throw Error('Public catalog is empty');
   const feeds=await ff.getDocs(ff.collection(db,'transport_feeds'));
   const active=feeds.docs.map(d=>({id:d.id,...d.data()})).filter(f=>f.activeVersionId&&f.distribution?.formatVersion===2);
   if(active.length<2)throw Error('Published transport feeds are missing');
   let bytes=0;
   for(const feed of active){const data=await st.getBytes(st.ref(st.getStorage(app),feed.distribution.manifestPath),2*1024*1024);bytes+=data.byteLength;const m=JSON.parse(new TextDecoder().decode(data));if(m.versionId!==feed.activeVersionId)throw Error('Transport manifest version mismatch');const small=await st.getBytes(st.ref(st.getStorage(app),'transport_data/'+feed.id+'/'+feed.activeVersionId+'/catalog.json.gz'),1024*1024);bytes+=small.byteLength;}
   let journeySearch=null;
   ${journeyQuery ? `const fn=globalThis.firebase_functions;if(!fn)throw Error('Functions Web SDK registration is missing');const response=await fn.httpsCallable(fn.getFunctions(app,'asia-northeast1'),'searchTransportJourneys')(${JSON.stringify(journeyQuery)});let journeys=response.data.journeys;if(response.data.journeyPool){const bytes=Uint8Array.from(atob(response.data.journeyPool.data),c=>c.charCodeAt(0));journeys=await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'))).json();}if(!journeys?.length)throw Error('Real Sapporo journey search returned no candidates');journeySearch={count:journeys.length,stats:response.data.stats};` : ''}
   return {projectId:app.options.projectId,catalogRead:true,activeFeeds:active.length,storageBytes:bytes,...(journeySearch?{journeySearch}:{})};
 })()`;
  const result = await send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (result.exceptionDetails)
    throw Error(
      result.exceptionDetails.exception?.description ||
        result.exceptionDetails.text,
    );
  console.log(
    JSON.stringify({
      status: "PASS",
      compiledBuild: localBuild ? "local" : "published",
      catalogHomeReady: true,
      ...result.result.value,
    }),
  );
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (socket?.readyState === 1) {
    try {
      await send("Browser.close");
    } catch (_) {}
    socket.close();
  }
  for (const p of pending.values()) clearTimeout(p.timer);
  chrome.kill();
  // The profile belongs only to this test and contains no personal session.
  await pause(200);
  fs.rmSync(profile, { recursive: true, force: true });
}
