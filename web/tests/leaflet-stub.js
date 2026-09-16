// Minimal stand-in for Leaflet, used only by tests/smoke.html.
//
// It implements exactly the surface mapview.js touches, so the smoke test can
// exercise the real UI, engine and rendering code in a browser without
// reaching a CDN.

(function () {
  const listeners = new Map();

  const fakeMap = {
    _zoom: 15,
    _centre: { lat: 51.5074, lng: -0.1278 },
    setView(latlng, zoom) {
      this._centre = { lat: latlng[0], lng: latlng[1] };
      if (zoom) this._zoom = zoom;
      return this;
    },
    getZoom() { return this._zoom; },
    getSize() { return { x: 390, y: 700 }; },
    getBounds() {
      const c = this._centre;
      const pad = 0.01;
      return {
        getSouth: () => c.lat - pad, getNorth: () => c.lat + pad,
        getWest: () => c.lng - pad, getEast: () => c.lng + pad,
        pad() { return this; },
      };
    },
    getPanes() { return { overlayPane: document.getElementById("map") }; },
    containerPointToLayerPoint() { return { x: 0, y: 0 }; },
    latLngToContainerPoint(latlng) {
      // A crude equirectangular projection is enough to prove the canvas path
      // runs and draws something.
      return { x: (latlng[1] + 0.13) * 40000, y: (51.52 - latlng[0]) * 40000 };
    },
    invalidateSize() {},
    hasLayer() { return true; },
    on(names, fn) {
      for (const name of names.split(" ")) {
        if (!listeners.has(name)) listeners.set(name, []);
        listeners.get(name).push(fn);
      }
      return this;
    },
    off() { return this; },
    fire(name, payload) {
      for (const fn of listeners.get(name) || []) fn(payload);
    },
  };

  window.L = {
    map: () => fakeMap,
    tileLayer: () => ({ addTo: () => ({}) }),
    marker: () => ({
      addTo: () => ({}),
      setLatLng() { return this; },
      getElement: () => document.createElement("div"),
    }),
    divIcon: () => ({}),
    DomUtil: {
      create(tag, className) {
        const node = document.createElement(tag);
        node.className = className;
        return node;
      },
      setPosition() {},
    },
    Layer: {
      extend(proto) {
        return class {
          addTo(map) {
            Object.assign(this, proto);
            this.onAdd(map);
            return this;
          }
        };
      },
    },
  };
  window.__fakeMap = fakeMap;
})();
