// Persistence. IndexedDB for the bulky stores (street tiles, coverage, trips),
// localStorage for the small profile blob.
//
// localStorage alone would not survive a city's worth of tiles, and Safari
// throws once it passes a few megabytes.

const DB_NAME = "street-collector";
const DB_VERSION = 1;

let dbPromise = null;

function openDB() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains("tiles")) db.createObjectStore("tiles");
      if (!db.objectStoreNames.contains("coverage")) db.createObjectStore("coverage");
      if (!db.objectStoreNames.contains("trips")) db.createObjectStore("trips", { keyPath: "id" });
      if (!db.objectStoreNames.contains("meta")) db.createObjectStore("meta");
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  return dbPromise;
}

async function tx(storeName, mode, run) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(storeName, mode);
    const store = transaction.objectStore(storeName);
    const request = run(store);
    transaction.oncomplete = () => resolve(request && request.result);
    transaction.onerror = () => reject(transaction.error);
  });
}

export const db = {
  get: (storeName, key) => tx(storeName, "readonly", (store) => store.get(key)),
  put: (storeName, key, value) =>
    tx(storeName, "readwrite", (store) => (key === undefined ? store.put(value) : store.put(value, key))),
  delete: (storeName, key) => tx(storeName, "readwrite", (store) => store.delete(key)),
  all: (storeName) => tx(storeName, "readonly", (store) => store.getAll()),
  keys: (storeName) => tx(storeName, "readonly", (store) => store.getAllKeys()),
  clear: (storeName) => tx(storeName, "readwrite", (store) => store.clear()),
};

// Small values that are read on every frame live in localStorage, which is
// synchronous and therefore doesn't need awaiting in the render path.
export const prefs = {
  get(key, fallback) {
    try {
      const raw = localStorage.getItem(`sc.${key}`);
      return raw === null ? fallback : JSON.parse(raw);
    } catch {
      return fallback;
    }
  },
  set(key, value) {
    try {
      localStorage.setItem(`sc.${key}`, JSON.stringify(value));
    } catch {
      // Private browsing, or quota. Preferences are not worth failing over.
    }
  },
};

export async function estimateUsage() {
  if (!navigator.storage || !navigator.storage.estimate) return null;
  try {
    return await navigator.storage.estimate();
  } catch {
    return null;
  }
}

/** Asks Safari not to evict the database under storage pressure. */
export async function requestPersistence() {
  if (!navigator.storage || !navigator.storage.persist) return false;
  try {
    return await navigator.storage.persist();
  } catch {
    return false;
  }
}
