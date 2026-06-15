// Rolls dice notation client-side: cache plan (IndexedDB) -> /parse on miss ->
// FlowDice.evaluate with a crypto-backed RNG. No dependencies.

const DB_NAME = "flowdice";
const STORE = "plans";

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function cacheGet(notation) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const r = db.transaction(STORE, "readonly").objectStore(STORE).get(notation);
    r.onsuccess = () => resolve(r.result || null);
    r.onerror = () => reject(r.error);
  });
}

async function cachePut(notation, entry) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const r = db.transaction(STORE, "readwrite").objectStore(STORE).put(entry, notation);
    r.onsuccess = () => resolve();
    r.onerror = () => reject(r.error);
  });
}

// Unbiased inclusive integer in [min, max] via rejection sampling (matches Ruby SecureRandom).
function secureInt(min, max) {
  const range = max - min + 1;
  const maxValid = Math.floor(0xffffffff / range) * range;
  const buf = new Uint32Array(1);
  let x;
  do { crypto.getRandomValues(buf); x = buf[0]; } while (x >= maxValid);
  return min + (x % range);
}

const secureRng = { int: (min, max) => secureInt(min, max) };

async function parse(notation) {
  const resp = await fetch("/parse", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ notation }),
  });
  const body = await resp.json();
  if (!resp.ok) throw new Error(body.error || "parse failed");
  return { plan: body.plan, explanation: body.explanation };
}

// Roll a notation. Returns { result, explanation }. Cached plans roll offline.
export async function rollNotation(notation) {
  let entry = await cacheGet(notation);
  if (!entry) {
    entry = await parse(notation);
    await cachePut(notation, entry);
  }
  const json = window.FlowDice.evaluate(JSON.stringify(entry.plan), notation, secureRng);
  return { result: JSON.parse(json), explanation: entry.explanation };
}
