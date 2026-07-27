// Minimal service worker — its only job is to exist with a fetch handler,
// which is what Chrome/Android's installability check requires before it'll
// offer "Add to Home Screen" (the manifest alone isn't enough there, unlike
// iOS Safari). No offline caching strategy for the MVP: every request just
// passes straight through to the network.
self.addEventListener("fetch", () => {});
