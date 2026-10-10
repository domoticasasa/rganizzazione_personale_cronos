/**
 * Rileva un nuovo deploy e forza reload (PWA / cache browser).
 * 1) Preferisce app_revision.json (se presente, es. CI)
 * 2) Altrimenti ETag / Last-Modified di main.dart.js (sempre automatico)
 */
(function () {
  var STORAGE_KEY = "cronos_app_revision";
  var RELOAD_FLAG = "cronos_app_revision_reloading";

  function clearHttpCaches() {
    if (!("caches" in window)) return Promise.resolve();
    return caches.keys().then(function (keys) {
      return Promise.all(
        keys.map(function (k) {
          return caches.delete(k);
        })
      );
    });
  }

  function readStored() {
    try {
      return localStorage.getItem(STORAGE_KEY) || "";
    } catch (_) {
      return "";
    }
  }

  function writeStored(v) {
    try {
      localStorage.setItem(STORAGE_KEY, v);
    } catch (_) {}
  }

  function cleanRevQuery() {
    try {
      var u = new URL(window.location.href);
      if (u.searchParams.has("_cronos_rev")) {
        u.searchParams.delete("_cronos_rev");
        window.history.replaceState(null, "", u.pathname + u.search + u.hash);
      }
      sessionStorage.removeItem(RELOAD_FLAG);
    } catch (_) {}
  }

  function applyRevision(rev) {
    rev = String(rev || "").trim();
    if (!rev) return Promise.resolve(false);
    var prev = readStored();
    if (!prev) {
      writeStored(rev);
      cleanRevQuery();
      return Promise.resolve(false);
    }
    if (prev === rev) {
      cleanRevQuery();
      return Promise.resolve(false);
    }
    writeStored(rev);
    try {
      if (sessionStorage.getItem(RELOAD_FLAG) === rev) {
        return Promise.resolve(false);
      }
      sessionStorage.setItem(RELOAD_FLAG, rev);
    } catch (_) {}
    return clearHttpCaches().then(function () {
      var url = new URL(window.location.href);
      url.searchParams.set("_cronos_rev", rev.slice(0, 48));
      window.location.replace(url.toString());
      return true;
    });
  }

  function revisionFromJson() {
    return fetch("app_revision.json?_=" + Date.now(), {
      cache: "no-store",
      headers: { "Cache-Control": "no-cache" },
    })
      .then(function (res) {
        if (!res.ok) return null;
        return res.json();
      })
      .then(function (data) {
        if (!data) return null;
        return String(data.revision || "").trim() || null;
      })
      .catch(function () {
        return null;
      });
  }

  function revisionFromMainJs() {
    return fetch("main.dart.js?_=" + Date.now(), {
      method: "HEAD",
      cache: "no-store",
      headers: { "Cache-Control": "no-cache" },
    })
      .then(function (res) {
        if (!res.ok) return null;
        var etag = (res.headers.get("etag") || "").replace(/"/g, "").trim();
        var lm = (res.headers.get("last-modified") || "").trim();
        if (etag) return "etag:" + etag;
        if (lm) return "lm:" + lm;
        return null;
      })
      .catch(function () {
        return null;
      });
  }

  window.cronosEnsureLatestBuild = function () {
    return revisionFromJson()
      .then(function (rev) {
        if (rev) return rev;
        return revisionFromMainJs();
      })
      .then(function (rev) {
        return applyRevision(rev);
      })
      .catch(function () {
        return false;
      });
  };
})();
