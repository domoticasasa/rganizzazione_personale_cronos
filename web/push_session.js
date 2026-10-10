// Sessione notifiche Web Push (finestra + Service Worker).
// Indipendente dal Passkey: serve a tenere viva la PushSubscription a app chiusa
// (pushsubscriptionchange, re-upsert endpoint). Non è uno sblocco privacy.
(function (root) {
  var DB_NAME = "cronos-push-session";
  var DB_VERSION = 1;
  var STORE = "kv";
  var KEY = "session";

  function openDb() {
    return new Promise(function (resolve, reject) {
      try {
        if (typeof indexedDB === "undefined") {
          reject(new Error("indexedDB unavailable"));
          return;
        }
        var req = indexedDB.open(DB_NAME, DB_VERSION);
        req.onupgradeneeded = function () {
          var db = req.result;
          if (!db.objectStoreNames.contains(STORE)) {
            db.createObjectStore(STORE);
          }
        };
        req.onsuccess = function () {
          resolve(req.result);
        };
        req.onerror = function () {
          reject(req.error || new Error("idb open failed"));
        };
      } catch (e) {
        reject(e);
      }
    });
  }

  function idbOp(mode, fn) {
    return openDb().then(function (db) {
      return new Promise(function (resolve, reject) {
        var tx = db.transaction(STORE, mode);
        var store = tx.objectStore(STORE);
        var req;
        try {
          req = fn(store);
        } catch (e) {
          reject(e);
          return;
        }
        req.onsuccess = function () {
          resolve(req.result);
        };
        req.onerror = function () {
          reject(req.error);
        };
        tx.oncomplete = function () {
          try {
            db.close();
          } catch (_) {}
        };
      });
    });
  }

  function sanitize(raw) {
    if (!raw || typeof raw !== "object") return null;
    var functionUrl = String(raw.functionUrl || "").trim();
    var accessToken = String(raw.accessToken || "").trim();
    var vapidPublicKey = String(raw.vapidPublicKey || "").trim();
    if (!functionUrl || !accessToken || !vapidPublicKey) return null;
    return {
      functionUrl: functionUrl,
      accessToken: accessToken,
      vapidPublicKey: vapidPublicKey,
      authUserId: String(raw.authUserId || "").trim(),
      refreshToken: String(raw.refreshToken || "").trim(),
      supabaseUrl: String(raw.supabaseUrl || "").trim(),
      anonKey: String(raw.anonKey || "").trim(),
      savedAt: Number(raw.savedAt || Date.now()) || Date.now(),
    };
  }

  async function save(raw) {
    var session = sanitize(raw);
    if (!session) return false;
    try {
      await idbOp("readwrite", function (store) {
        return store.put(session, KEY);
      });
      return true;
    } catch (e) {
      console.warn("cronosPushSession.save", e);
      return false;
    }
  }

  async function load() {
    try {
      var row = await idbOp("readonly", function (store) {
        return store.get(KEY);
      });
      return sanitize(row);
    } catch (e) {
      console.warn("cronosPushSession.load", e);
      return null;
    }
  }

  async function clear() {
    try {
      await idbOp("readwrite", function (store) {
        return store.delete(KEY);
      });
    } catch (_) {}
  }

  root.cronosPushSession = {
    save: save,
    load: load,
    clear: clear,
    sanitize: sanitize,
  };
})(typeof self !== "undefined" ? self : window);
