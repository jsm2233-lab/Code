# Street Collector — web app

The same game as the native iOS app in this repo, rebuilt as an installable web
app so it can be used without compiling anything. No build step, no framework,
no dependencies: open `index.html` over HTTPS and it runs.

## The one big difference

**Background collection is impossible on iOS web.** Safari suspends
`watchPosition` the moment you leave the page or lock the screen, and there is
no web equivalent of the Always-location entitlement. The app holds the screen
awake via the Wake Lock API during a trip, so a mounted phone on a drive or a
deliberate walk with the app open works properly — but pocketing the phone
does not. That is a browser limit, not a setting, and the app says so during
onboarding rather than quietly collecting nothing.

Everything else is here: real map matching against OpenStreetMap geometry, the
same 0.7 completion threshold, XP weighted by road class, 60 levels, streaks,
18 badges, per-area completion, the collection book, and GeoJSON export.

## Running it

Geolocation requires a secure context, so `file://` will not work:

```sh
cd web && python3 -m http.server 8000   # then open http://localhost:8000
```

`localhost` counts as secure. For a phone you need real HTTPS —
`.github/workflows/pages.yml` publishes this directory to GitHub Pages on
push to the default branch.

Install it to the home screen from Safari's share sheet ("Add to Home Screen").
That gets the standalone window with no browser chrome, which is what the
`apple-mobile-web-app-capable` meta tag is for; the manifest alone does not do
it on iOS.

## Tests

```sh
node tests/run.mjs        # or: npm test
```

34 tests over the pure logic — geometry, interval merging, the matcher's
stickiness and gap-bridging behaviour, Overpass way splitting, the level curve.
These run in plain Node with `assert`, no framework.

There is also a browser smoke test in `tests/smoke.html`, which loads the real
app against a stub Leaflet (`tests/leaflet-stub.js`) and reports any console
errors into the DOM. Serve the directory and open it, or drive it headless.

## Layout

```
web/
  js/geo.js         planar geometry
  js/intervals.js   merged 0..1 coverage intervals
  js/spatial.js     uniform-grid index
  js/matcher.js     GPS -> street matching
  js/streets.js     tiles, street model, Overpass import
  js/store.js       IndexedDB + localStorage
  js/game.js        XP, levels, streaks, badges
  js/engine.js      orchestrator
  js/mapview.js     Leaflet + neon coverage canvas
  js/ui.js          screens
  js/app.js         composition root
  sw.js             offline shell
```

`geo`, `intervals`, `spatial`, `matcher` and `streets` are pure and have no DOM
dependencies, which is what makes them testable in Node.

## Known limits

- Leaflet loads from cdnjs **without** subresource-integrity hashes, because
  they could not be verified from the build environment and a wrong hash blocks
  the script outright. Vendor Leaflet locally or add verified hashes before
  treating this as production.
- Storage is per-origin and per-browser. Clearing Safari's website data deletes
  your collection. The app calls `navigator.storage.persist()` to reduce the
  chance of eviction, but iOS can still reclaim it. Export to GeoJSON if you
  care about the data.
- Overpass is a donated public service, throttled here to one request every
  1.2s with endpoint rotation.
- Areas are 0.02° tiles, not real neighbourhoods.

Map data © OpenStreetMap contributors, ODbL. Basemap © CARTO.
