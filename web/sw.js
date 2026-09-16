// Offline shell. Street data and coverage live in IndexedDB, so with the shell
// cached the app opens and shows your collection with no network at all —
// which matters, because "no signal" is a normal condition mid-trip.

const CACHE = "street-collector-v1";
const SHELL = [
  "./",
  "./index.html",
  "./app.css",
  "./manifest.webmanifest",
  "./js/app.js",
  "./js/ui.js",
  "./js/engine.js",
  "./js/game.js",
  "./js/mapview.js",
  "./js/matcher.js",
  "./js/spatial.js",
  "./js/intervals.js",
  "./js/streets.js",
  "./js/store.js",
  "./js/geo.js",
  "./icons/icon-192.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  // Never cache Overpass: a stale street graph is worse than none, and the
  // engine already keeps its own tile cache in IndexedDB.
  if (url.hostname.includes("overpass")) return;

  // Map tiles and the Leaflet bundle: cache-first. Tiles never change, and
  // re-fetching them on a patchy connection is what makes a map feel broken;
  // Leaflet has to be cached or the app cannot open offline at all.
  if (url.hostname.includes("basemaps.cartocdn.com") || url.hostname.includes("cdnjs.cloudflare.com")) {
    event.respondWith(
      caches.open(`${CACHE}-tiles`).then(async (cache) => {
        const hit = await cache.match(request);
        if (hit) return hit;
        try {
          const response = await fetch(request);
          if (response.ok) cache.put(request, response.clone());
          return response;
        } catch {
          return hit || Response.error();
        }
      })
    );
    return;
  }

  // Everything else: network-first, falling back to the cached shell.
  event.respondWith(
    fetch(request)
      .then((response) => {
        if (response.ok && url.origin === self.location.origin) {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(request, copy));
        }
        return response;
      })
      .catch(() => caches.match(request).then((hit) => hit || caches.match("./index.html")))
  );
});
