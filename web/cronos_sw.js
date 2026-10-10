// Service worker Cronos: solo Web Push (tab chiusa).
// Il SW Flutter di default è disabilitato in flutter_bootstrap.js perché
// sostituiva questo worker e le push non venivano gestite.
// v8: chat push con suono OS + postMessage ai client aperti.

self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("message", (event) => {
  if (event?.data?.type === "SKIP_WAITING") {
    self.skipWaiting();
  }
});

try {
  importScripts("./push_session.js?v=28");
} catch (errSession) {
  console.warn("[cronos_sw] push_session.js non caricato:", errSession);
}
try {
  importScripts("./push_handlers.js?v=28");
} catch (err) {
  try {
    importScripts("./push_handlers.js");
  } catch (err2) {
    console.error("[cronos_sw] push_handlers.js non caricato:", err2);
  }
}
