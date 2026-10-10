// Compatibilità: vecchie registrazioni /push-sw.js.
try {
  importScripts("./push_handlers.js");
} catch (err) {
  console.error("[push-sw] push_handlers.js non caricato:", err);
}
