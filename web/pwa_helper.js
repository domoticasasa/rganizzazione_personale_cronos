(() => {
  let deferredInstallPrompt = null;
  let pushRegistration = null;
  const IOS_HINT_DISMISSED_KEY = "cronos_ios_install_hint_dismissed";
  const VAPID_LS_KEY = "cronos_vapid_public_key";
  const PUSH_SW_VERSION_KEY = "cronos_push_sw_ver";
  const PUSH_SW_VERSION = "28";
  const PUSH_REGISTERED_KEY = "cronos_web_push_registered";
  /** Auth user id (Supabase) a cui è legato l'endpoint di QUESTO browser. */
  const PUSH_BOUND_AUTH_KEY = "cronos_web_push_bound_auth";
  const SUPABASE_URL = "https://bjdimalvbdablzoctrsf.supabase.co";
  const SUPABASE_ANON_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqZGltYWx2YmRhYmx6b2N0cnNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5MzczNTcsImV4cCI6MjA4NzUxMzM1N30.Lm4GHd1CWdSMMI87Wx2eBrHcmqFtMXO31hO7Q3BsYyc";
  const AUTH_STORAGE_KEY = "sb-bjdimalvbdablzoctrsf-auth-token";

  /** Solo host di produzione (e localhost) possono registrare Web Push.
   *  Le preview Cloudflare (*.pages.dev) creavano endpoint separati → N toast per 1 messaggio. */
  function isCanonicalPushHost() {
    try {
      const h = String(location.hostname || "").toLowerCase();
      if (!h) return false;
      if (h === "localhost" || h === "127.0.0.1") return true;
      if (h === "www.gestopro360.it") return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  function currentPageOrigin() {
    try {
      return String(location.origin || "").trim();
    } catch (_) {
      return "";
    }
  }

  /** Su preview / host non canonici: togli push locale e disattiva l'endpoint su Supabase. */
  async function revokePushOnNonCanonicalHost(functionUrl, accessToken) {
    try {
      const json = await unsubscribeWebPush();
      try {
        localStorage.removeItem(PUSH_REGISTERED_KEY);
        localStorage.removeItem(PUSH_BOUND_AUTH_KEY);
      } catch (_) {}
      if (!json || !json.endpoint || !functionUrl || !accessToken) return;
      await fetch(functionUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + accessToken,
        },
        body: JSON.stringify({
          action: "unsubscribe",
          subscription: { endpoint: json.endpoint },
        }),
      });
    } catch (e) {
      console.warn("revokePushOnNonCanonicalHost", e);
    }
  }

  function resolveSwUrl() {
    try {
      // Query version forza aggiornamento del SW (cache browser).
      return new URL(
        "cronos_sw.js?v=" + encodeURIComponent(PUSH_SW_VERSION),
        document.baseURI || window.location.href
      ).href;
    } catch (_) {
      return "cronos_sw.js?v=" + encodeURIComponent(PUSH_SW_VERSION);
    }
  }

  function resolveSwScope() {
    try {
      return new URL(".", document.baseURI || window.location.href).href;
    } catch (_) {
      return "/";
    }
  }

  function needsForcePushRefresh() {
    try {
      return localStorage.getItem(PUSH_SW_VERSION_KEY) !== PUSH_SW_VERSION;
    } catch (_) {
      return true;
    }
  }

  function clearRegisteredIfVapidOrSwChanged(vapidPublicKey) {
    try {
      const prevVapid = localStorage.getItem(VAPID_LS_KEY) || "";
      const swChanged = localStorage.getItem(PUSH_SW_VERSION_KEY) !== PUSH_SW_VERSION;
      if ((prevVapid && prevVapid !== vapidPublicKey) || swChanged) {
        localStorage.removeItem(PUSH_REGISTERED_KEY);
        localStorage.removeItem(PUSH_BOUND_AUTH_KEY);
      }
    } catch (_) {}
  }

  function markPushSwVersion() {
    try {
      localStorage.setItem(PUSH_SW_VERSION_KEY, PUSH_SW_VERSION);
    } catch (_) {}
  }

  function markPushRegistered(authUserId) {
    try {
      localStorage.setItem(PUSH_REGISTERED_KEY, "1");
      if (authUserId) {
        localStorage.setItem(PUSH_BOUND_AUTH_KEY, String(authUserId));
      }
    } catch (_) {}
  }

  function clearPushRegisteredFlags() {
    try {
      localStorage.removeItem(PUSH_REGISTERED_KEY);
      localStorage.removeItem(PUSH_BOUND_AUTH_KEY);
    } catch (_) {}
  }

  function boundAuthUserId() {
    try {
      return localStorage.getItem(PUSH_BOUND_AUTH_KEY) || "";
    } catch (_) {
      return "";
    }
  }

  function isPushRegistered() {
    try {
      if (localStorage.getItem(PUSH_REGISTERED_KEY) !== "1") return false;
      const boot = window.cronosPushBootstrap || null;
      const expected = boot && boot.authUserId ? String(boot.authUserId) : "";
      const bound = boundAuthUserId();
      // Stesso browser, altro account: non considerare "già registrato".
      if (expected && bound && bound !== expected) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  function parseStoredAuthJson(raw) {
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw);
      const sess = parsed.currentSession || parsed.session || parsed;
      const accessToken = String(sess.access_token || "").trim();
      if (!accessToken) return null;
      const user = sess.user || parsed.user || {};
      return {
        accessToken,
        refreshToken: String(sess.refresh_token || "").trim(),
        authUserId: String(user.id || "").trim(),
      };
    } catch (_) {
      return null;
    }
  }

  function readStoredSupabaseSession() {
    try {
      const direct = parseStoredAuthJson(localStorage.getItem(AUTH_STORAGE_KEY));
      if (direct) return direct;
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i) || "";
        if (k.indexOf("sb-") !== 0) continue;
        if (k.indexOf("auth-token") < 0) continue;
        if (k.indexOf("code-verifier") >= 0) continue;
        const parsed = parseStoredAuthJson(localStorage.getItem(k));
        if (parsed) return parsed;
      }
    } catch (_) {}
    return null;
  }

  function persistNotificationSession(bootOverride) {
    try {
      const boot = bootOverride || window.cronosPushBootstrap || null;
      const api = window.cronosPushSession;
      if (!api || typeof api.save !== "function") return Promise.resolve(false);
      if (!boot) return Promise.resolve(false);
      return api.save({
        functionUrl: boot.functionUrl,
        accessToken: boot.accessToken,
        vapidPublicKey: boot.vapidPublicKey,
        authUserId: boot.authUserId || "",
        refreshToken: boot.refreshToken || "",
        supabaseUrl: boot.supabaseUrl || SUPABASE_URL,
        anonKey: boot.anonKey || SUPABASE_ANON_KEY,
        savedAt: Date.now(),
      });
    } catch (_) {
      return Promise.resolve(false);
    }
  }

  /** Sessione push dal JWT già in localStorage: non aspetta Flutter né Passkey. */
  function hydratePushBootstrapFromStorage() {
    try {
      if (!isCanonicalPushHost()) return false;
      const existing = window.cronosPushBootstrap || null;
      const sess = readStoredSupabaseSession();
      const vapid = window.CRONOS_VAPID_PUBLIC_KEY || "";
      if (!sess || !vapid) {
        if (existing && existing.accessToken && existing.vapidPublicKey) {
          persistNotificationSession(existing);
          return true;
        }
        return false;
      }
      window.cronosPushBootstrap = {
        functionUrl: SUPABASE_URL + "/functions/v1/web-push-subscribe",
        accessToken: sess.accessToken,
        vapidPublicKey: vapid,
        authUserId: sess.authUserId || (existing && existing.authUserId) || "",
        refreshToken: sess.refreshToken || "",
        supabaseUrl: SUPABASE_URL,
        anonKey: SUPABASE_ANON_KEY,
      };
      persistNotificationSession(window.cronosPushBootstrap);
      return true;
    } catch (_) {
      return false;
    }
  }

  let _autoPushInFlight = false;
  let _autoPushFailed = false;

  function isIos() {
    const ua = window.navigator.userAgent.toLowerCase();
    return /iphone|ipad|ipod/.test(ua);
  }

  function isAndroid() {
    return /android/i.test(window.navigator.userAgent || "");
  }

  function isWindowsDesktop() {
    try {
      const ua = String(window.navigator.userAgent || "");
      return /Windows/i.test(ua) && !/Android/i.test(ua);
    } catch (_) {
      return false;
    }
  }

  function isMobileOs() {
    return isIos() || isAndroid();
  }

  function isInStandaloneMode() {
    try {
      if (window.navigator.standalone === true) return true;
      const modes = ["standalone", "fullscreen", "minimal-ui"];
      for (const m of modes) {
        if (window.matchMedia("(display-mode: " + m + ")").matches) return true;
      }
    } catch (_) {}
    return false;
  }

  /** Solo PWA installata su telefono (non scheda Chrome) + www su PC. */
  function isPushSurfaceAllowed() {
    if (!isCanonicalPushHost()) return false;
    if (isMobileOs() && !isInStandaloneMode()) return false;
    return true;
  }

  function ensureContainer() {
    let el = document.getElementById("pwa-tools");
    if (el) return el;
    el = document.createElement("div");
    el.id = "pwa-tools";
    el.style.position = "fixed";
    el.style.right = "12px";
    el.style.bottom = "12px";
    el.style.zIndex = "9999";
    el.style.display = "flex";
    el.style.flexDirection = "column";
    el.style.gap = "8px";
    document.body.appendChild(el);
    return el;
  }

  function mkButton(text, onClick) {
    const btn = document.createElement("button");
    btn.textContent = text;
    btn.style.border = "none";
    btn.style.borderRadius = "10px";
    btn.style.padding = "10px 12px";
    btn.style.background = "#2F6FED";
    btn.style.color = "#fff";
    btn.style.fontWeight = "600";
    btn.style.cursor = "pointer";
    btn.style.boxShadow = "0 2px 8px rgba(0,0,0,.2)";
    btn.addEventListener("click", onClick);
    return btn;
  }

  function createIosInstallOverlay() {
    const old = document.getElementById("cronos-ios-install-overlay");
    if (old) old.remove();

    const backdrop = document.createElement("div");
    backdrop.id = "cronos-ios-install-overlay";
    backdrop.style.position = "fixed";
    backdrop.style.inset = "0";
    backdrop.style.zIndex = "10000";
    backdrop.style.background = "rgba(0,0,0,.45)";
    backdrop.style.display = "flex";
    backdrop.style.alignItems = "center";
    backdrop.style.justifyContent = "center";
    backdrop.style.padding = "16px";

    const card = document.createElement("div");
    card.style.maxWidth = "420px";
    card.style.width = "100%";
    card.style.background = "#111827";
    card.style.color = "#fff";
    card.style.borderRadius = "16px";
    card.style.padding = "16px";
    card.style.boxShadow = "0 8px 28px rgba(0,0,0,.35)";

    const title = document.createElement("div");
    title.textContent = "Installa Cronos Gestopro su iPhone";
    title.style.fontSize = "18px";
    title.style.fontWeight = "700";
    title.style.marginBottom = "10px";

    const steps = document.createElement("div");
    steps.style.fontSize = "15px";
    steps.style.lineHeight = "1.45";
    steps.innerHTML =
      "1) Tocca <b>Condividi</b> in basso in Safari.<br>" +
      "2) Scorri e scegli <b>Aggiungi a Home</b> (o <b>Aggiungi a schermata Home</b>).<br>" +
      "3) Tocca <b>Aggiungi</b> in alto a destra.<br><br>" +
      "Nota: su iPhone Apple non permette installazione automatica completa.";

    const actions = document.createElement("div");
    actions.style.display = "flex";
    actions.style.gap = "8px";
    actions.style.marginTop = "14px";
    actions.style.flexWrap = "wrap";

    const mkAction = (text, onClick, primary) => {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = text;
      b.style.border = "none";
      b.style.borderRadius = "10px";
      b.style.padding = "10px 12px";
      b.style.fontWeight = "600";
      b.style.cursor = "pointer";
      b.style.background = primary ? "#2F6FED" : "#374151";
      b.style.color = "#fff";
      b.addEventListener("click", onClick);
      return b;
    };

    const openShare = mkAction("Apri Condividi", async () => {
      try {
        if (navigator.share) {
          await navigator.share({
            title: document.title || "Cronos",
            text: "Apri questa app da Home",
            url: window.location.href
          });
        } else {
          alert("Apri manualmente il menu Condividi di Safari.");
        }
      } catch (_) {
        // user cancelled share; keep overlay open
      }
    }, true);

    const close = mkAction("Chiudi", () => backdrop.remove(), false);
    const dontShow = mkAction("Non mostrare più", () => {
      try {
        localStorage.setItem(IOS_HINT_DISMISSED_KEY, "1");
      } catch (_) {}
      backdrop.remove();
      renderTools();
    }, false);

    actions.appendChild(openShare);
    actions.appendChild(close);
    actions.appendChild(dontShow);
    card.appendChild(title);
    card.appendChild(steps);
    card.appendChild(actions);
    backdrop.appendChild(card);
    document.body.appendChild(backdrop);
  }

  function showIosInstallHint() {
    createIosInstallOverlay();
  }

  async function askInstall() {
    if (!deferredInstallPrompt) return;
    deferredInstallPrompt.prompt();
    await deferredInstallPrompt.userChoice;
    deferredInstallPrompt = null;
    renderTools();
  }

  let splashAudio = null;
  function prepareSplashAudio() {
    if (!splashAudio) {
      splashAudio = new Audio("assets/assets/gestopro_splash_intro.mp3");
      splashAudio.addEventListener("error", () => {
        if (!splashAudio.__cronosFallbackTried) {
          splashAudio.__cronosFallbackTried = true;
          splashAudio.src = "assets/gestopro_splash_intro.mp3";
        }
      }, { once: true });
      splashAudio.preload = "auto";
      splashAudio.volume = 1.0;
    }
    return splashAudio;
  }

  async function playSplashIntro() {
    const a = prepareSplashAudio();
    try {
      a.currentTime = 0;
      a.volume = 1.0;
      await a.play();
      return true;
    } catch (e) {
      console.warn("playSplashIntro", e);
      return false;
    }
  }

  let notifAudio = null;
  function prepareNotifAudio() {
    if (!notifAudio) {
      notifAudio = new Audio("assets/assets/notification.mp3");
      notifAudio.addEventListener("error", () => {
        if (!notifAudio.__cronosFallbackTried) {
          notifAudio.__cronosFallbackTried = true;
          notifAudio.src = "assets/notification.mp3";
        }
      }, { once: true });
      notifAudio.preload = "auto";
    }
    return notifAudio;
  }

  async function unlockNotificationSound() {
    const a = prepareNotifAudio();
    try {
      a.volume = 0.01;
      await a.play();
      a.pause();
      a.currentTime = 0;
      a.volume = 1.0;
      return true;
    } catch (_) {
      return false;
    }
  }

  async function playNotificationSound() {
    const a = prepareNotifAudio();
    try {
      a.currentTime = 0;
      await a.play();
    } catch (e) {
      console.warn("playNotificationSound", e);
    }
  }

  function notifyPermissionChange() {
    try {
      window.dispatchEvent(new Event("cronos-notification-permission"));
    } catch (_) {}
  }

  async function askNotificationPermission() {
    if (!("Notification" in window)) {
      alert("Notifiche browser non supportate su questo dispositivo.");
      return;
    }
    // iOS: Web Push solo dalla PWA installata in Home Screen (Safari 16.4+).
    if (isIos() && !isInStandaloneMode()) {
      alert(
        "Su iPhone/iPad: Condividi → Aggiungi a Home, apri Cronos dall'icona Home, poi Abilita notifiche. Dalla scheda Safari le push a app chiusa non funzionano."
      );
      renderTools();
      return;
    }
    if (!("PushManager" in window) && isIos()) {
      alert(
        "Questo iOS non supporta Web Push (serve iOS 16.4+ e app aperta da Home)."
      );
      return;
    }
    const res = await Notification.requestPermission();
    if (res === "granted") {
      await unlockNotificationSound();
      // Su mobile `new Notification` è instabile: preferisci SW.showNotification.
      try {
        const reg = await ensurePushServiceWorker();
        if (reg) {
          await reg.showNotification("Cronos", {
            body: "Notifiche browser abilitate.",
            tag: "cronos-perm-ok",
            icon: new URL("icons/Icon-192.png", resolveSwScope()).href,
          });
        } else if (typeof Notification === "function") {
          new Notification("Cronos", {
            body: "Notifiche browser abilitate.",
            silent: false,
          });
        }
      } catch (_) {}
      try {
        const boot = window.cronosPushBootstrap || null;
        if (boot && boot.functionUrl && boot.accessToken && boot.vapidPublicKey) {
          const ok = await registerWebPushWithSupabase(
            boot.functionUrl,
            boot.accessToken,
            boot.vapidPublicKey,
            true,
            boot.authUserId || ""
          );
          if (!ok) {
            alert(
              isIos() && !isInStandaloneMode()
                ? "Su iPhone apri Cronos dall'icona Home e riprova «Abilita notifiche»."
                : "Permesso OK, ma push non registrata. Tocca «Registra push (tab chiusa)»."
            );
          } else {
            renderTools();
          }
        }
      } catch (_) {}
    } else {
      alert("Permesso notifiche non concesso.");
    }
    renderTools();
    notifyPermissionChange();
  }

  function urlB64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
    const rawData = atob(base64);
    const outputArray = new Uint8Array(rawData.length);
    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  }

  function swScriptUrl(reg) {
    return (
      reg?.active?.scriptURL ||
      reg?.waiting?.scriptURL ||
      reg?.installing?.scriptURL ||
      ""
    );
  }

  function isCronosSwUrl(url) {
    return /cronos_sw\.js/i.test(String(url || ""));
  }

  async function ensurePushServiceWorker() {
    if (!("serviceWorker" in navigator)) return null;
    // Non riusare ciecamente la cache in-memory: può puntare a un SW vecchio.
    try {
      const existing = await navigator.serviceWorker.getRegistration(resolveSwScope());
      if (existing && isCronosSwUrl(swScriptUrl(existing))) {
        pushRegistration = existing;
      }
    } catch (_) {}

    // Unregister SW Flutter / altri SW sullo stesso scope (uccidono la PushSubscription).
    try {
      const regs = await navigator.serviceWorker.getRegistrations();
      for (const reg of regs) {
        const url = swScriptUrl(reg);
        if (!url) continue;
        if (isCronosSwUrl(url)) continue;
        // flutter_service_worker.js (e eventuali push-sw.js legacy) vanno via.
        if (
          /flutter_service_worker\.js/i.test(url) ||
          /push-sw\.js/i.test(url) ||
          !/cronos_sw\.js/i.test(url)
        ) {
          try {
            await reg.unregister();
          } catch (_) {}
        }
      }
    } catch (_) {}

    pushRegistration = await navigator.serviceWorker.register(resolveSwUrl(), {
      scope: resolveSwScope(),
      updateViaCache: "none",
    });
    try {
      await pushRegistration.update();
    } catch (_) {}
    await navigator.serviceWorker.ready;
    // Assicura che il SW sia active (non solo installing).
    if (pushRegistration.installing) {
      await new Promise((resolve) => {
        const worker = pushRegistration.installing;
        worker.addEventListener("statechange", () => {
          if (worker.state === "activated" || worker.state === "redundant") {
            resolve();
          }
        });
      });
    }
    if (pushRegistration.waiting) {
      try {
        pushRegistration.waiting.postMessage({ type: "SKIP_WAITING" });
      } catch (_) {}
    }
    return pushRegistration;
  }

  async function subscribeWebPushIfPermitted(vapidPublicKey, forceRefresh) {
    try {
      if (!("PushManager" in window) || !("Notification" in window)) {
        if (isIos() && !isInStandaloneMode()) {
          console.warn(
            "iOS: Web Push solo dall'app installata in Home (Condividi → Aggiungi a Home).",
          );
        }
        return null;
      }
      // iPhone/iPad/Android: Push solo dalla PWA installata (non dalla scheda Chrome).
      if (isMobileOs() && !isInStandaloneMode()) {
        console.warn(
          "Mobile: apri Cronos dall'icona Home per le notifiche a app chiusa.",
        );
        return null;
      }
      if (Notification.permission !== "granted") return null;

      const hidden =
        typeof document !== "undefined" && document.hidden === true;

      const reg = await ensurePushServiceWorker();
      if (!reg || !reg.pushManager) return null;

      // Se la VAPID pubblica è cambiata, la subscription vecchia non riceve più push.
      let vapidChanged = false;
      try {
        const prev = localStorage.getItem(VAPID_LS_KEY) || "";
        if (prev && prev !== vapidPublicKey) {
          vapidChanged = true;
          forceRefresh = true;
          try {
            clearPushRegisteredFlags();
          } catch (_) {}
        }
        localStorage.setItem(VAPID_LS_KEY, vapidPublicKey);
      } catch (_) {}

      let sub = await reg.pushManager.getSubscription();
      const wantRefresh =
        forceRefresh === true || needsForcePushRefresh() || vapidChanged;
      // Passkey/WebAuthn mette document.hidden: unsubscribe + subscribe fallisce
      // e lascia l'endpoint morto → zero toast a PWA chiusa.
      if (wantRefresh && sub && hidden) {
        console.warn(
          "subscribeWebPushIfPermitted: refresh rimandato (tab nascosta / Passkey)",
        );
        return sub.toJSON();
      }
      if (wantRefresh && sub) {
        try {
          await sub.unsubscribe();
        } catch (_) {}
        sub = null;
      }
      if (!sub) {
        if (hidden) {
          console.warn(
            "subscribeWebPushIfPermitted: nessuna subscription e tab nascosta, rimando",
          );
          return null;
        }
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlB64ToUint8Array(vapidPublicKey),
        });
      }
      return sub ? sub.toJSON() : null;
    } catch (e) {
      console.error("subscribeWebPushIfPermitted error", e);
      try {
        const hiddenRetry =
          typeof document !== "undefined" && document.hidden === true;
        const reg = await ensurePushServiceWorker();
        const oldSub = await reg?.pushManager?.getSubscription();
        if (hiddenRetry) {
          return oldSub ? oldSub.toJSON() : null;
        }
        if (oldSub) await oldSub.unsubscribe();
        const sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlB64ToUint8Array(vapidPublicKey),
        });
        try {
          localStorage.setItem(VAPID_LS_KEY, vapidPublicKey);
        } catch (_) {}
        return sub ? sub.toJSON() : null;
      } catch (e2) {
        console.error("subscribeWebPushIfPermitted retry error", e2);
        return null;
      }
    }
  }

  async function initWebPush(vapidPublicKey) {
    try {
      if (!("PushManager" in window) || !("Notification" in window)) {
        return null;
      }
      if (Notification.permission === "granted") {
        return await subscribeWebPushIfPermitted(vapidPublicKey);
      }
      const perm = await Notification.requestPermission();
      if (perm !== "granted") return null;
      return await subscribeWebPushIfPermitted(vapidPublicKey);
    } catch (e) {
      console.error("initWebPush error", e);
      return null;
    }
  }

  async function unsubscribeWebPush() {
    try {
      const reg = await ensurePushServiceWorker();
      if (!reg) return null;
      const sub = await reg.pushManager.getSubscription();
      if (!sub) return null;
      const json = sub.toJSON();
      try {
        const notes = await reg.getNotifications();
        for (const n of notes) {
          try {
            n.close();
          } catch (_) {}
        }
      } catch (_) {}
      await sub.unsubscribe();
      return json;
    } catch (e) {
      console.error("unsubscribeWebPush error", e);
      return null;
    }
  }

  async function registerWebPushWithSupabase(functionUrl, accessToken, vapidPublicKey, forceRefresh, authUserId) {
    try {
      if (!functionUrl || !accessToken || !vapidPublicKey) return false;
      try {
        window.cronosPushBootstrap = Object.assign(
          {},
          window.cronosPushBootstrap || {},
          {
            functionUrl,
            accessToken,
            vapidPublicKey,
            authUserId: authUserId ? String(authUserId) : "",
            supabaseUrl: SUPABASE_URL,
            anonKey: SUPABASE_ANON_KEY,
          },
        );
        persistNotificationSession(window.cronosPushBootstrap);
      } catch (_) {}
      if (!isPushSurfaceAllowed()) {
        await revokePushOnNonCanonicalHost(functionUrl, accessToken);
        return false;
      }
      // Non azzerare i flag prima del successo: altrimenti a ogni apertura
      // compare «Registra push» anche se la subscription è ancora valida.
      const authId = authUserId ? String(authUserId) : "";
      const prevBound = boundAuthUserId();
      const accountChanged = !!(authId && prevBound && prevBound !== authId);
      const vapidChanged = (() => {
        try {
          const prev = localStorage.getItem(VAPID_LS_KEY) || "";
          return !!(prev && prev !== vapidPublicKey);
        } catch (_) {
          return false;
        }
      })();
      const force =
        forceRefresh === true ||
        vapidChanged ||
        needsForcePushRefresh() ||
        accountChanged;
      let subscription = await subscribeWebPushIfPermitted(vapidPublicKey, force);
      if (!subscription) {
        if (
          "Notification" in window &&
          Notification.permission === "granted" &&
          !(typeof document !== "undefined" && document.hidden)
        ) {
          subscription = await subscribeWebPushIfPermitted(vapidPublicKey, true);
        }
      }
      if (!subscription || !subscription.endpoint) return false;
      const res = await fetch(functionUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`
        },
        body: JSON.stringify({
          action: "subscribe",
          subscription,
          user_agent: window.navigator.userAgent || "",
          origin: currentPageOrigin(),
        })
      });
      const rawBody = await res.text();
      let payload = {};
      try {
        payload = rawBody ? JSON.parse(rawBody) : {};
      } catch (_) {}
      if (!res.ok || payload.ok === false) {
        console.error("web-push-subscribe failed", res.status, rawBody || payload, {
          accountChanged,
        });
        return false;
      }
      try {
        localStorage.setItem(VAPID_LS_KEY, vapidPublicKey);
      } catch (_) {}
      markPushSwVersion();
      markPushRegistered(authId);
      persistNotificationSession(window.cronosPushBootstrap);
      keepListeningAfterClose();
      _autoPushFailed = false;
      renderTools();
      return true;
    } catch (e) {
      console.error("registerWebPushWithSupabase error", e);
      return false;
    }
  }

  /**
   * Logout: non toccare i flag push.
   * Così alla riapertura (stesso browser, permesso già granted) la
   * registrazione resta automatica senza ripremere «Registra push».
   */
  async function deactivateWebPushOnLogout(functionUrl, accessToken) {
    return true;
  }

  /** Re-sync soft verso Supabase (tab di nuovo visibile / focus / login). */
  async function resyncWebPushIfPossible() {
    try {
      if (!("Notification" in window) || Notification.permission !== "granted") {
        return false;
      }
      hydratePushBootstrapFromStorage();
      const boot = window.cronosPushBootstrap || null;
      if (!boot || !boot.functionUrl || !boot.accessToken || !boot.vapidPublicKey) {
        return false;
      }
      if (!isPushSurfaceAllowed()) {
        await revokePushOnNonCanonicalHost(boot.functionUrl, boot.accessToken);
        return false;
      }
      if (_autoPushInFlight) return false;
      _autoPushInFlight = true;
      renderTools();
      try {
        const ok = await registerWebPushWithSupabase(
          boot.functionUrl,
          boot.accessToken,
          boot.vapidPublicKey,
          false,
          boot.authUserId || ""
        );
        if (!ok) {
          if (typeof document !== "undefined" && document.hidden) {
            _autoPushFailed = true;
            return false;
          }
          const ok2 = await registerWebPushWithSupabase(
            boot.functionUrl,
            boot.accessToken,
            boot.vapidPublicKey,
            true,
            boot.authUserId || ""
          );
          _autoPushFailed = !ok2;
          return ok2;
        }
        _autoPushFailed = false;
        return true;
      } finally {
        _autoPushInFlight = false;
        renderTools();
      }
    } catch (e) {
      console.warn("resyncWebPushIfPossible", e);
      _autoPushFailed = true;
      _autoPushInFlight = false;
      renderTools();
      return false;
    }
  }

  async function reregisterPushFromButton() {
    const boot = window.cronosPushBootstrap || null;
    if (!boot || !boot.functionUrl || !boot.accessToken || !boot.vapidPublicKey) {
      alert("Effettua il login e riprova tra qualche secondo.");
      return;
    }
    try {
      localStorage.removeItem(PUSH_SW_VERSION_KEY);
      clearPushRegisteredFlags();
    } catch (_) {}
    pushRegistration = null;
    const ok = await registerWebPushWithSupabase(
      boot.functionUrl,
      boot.accessToken,
      boot.vapidPublicKey,
      true,
      boot.authUserId || ""
    );
    _autoPushFailed = !ok;
    renderTools();
    alert(
      ok
        ? "Push registrata su QUESTO dispositivo. Gli altri (PC/telefono/tablet) restano indipendenti: apri Cronos su ciascuno e abilita le notifiche se manca il canale."
        : isIos() && !isInStandaloneMode()
          ? "Su iPhone: Condividi → Aggiungi a Home, apri Cronos dall'icona, poi Abilita notifiche. Dalla scheda Safari le push a app chiusa non funzionano."
          : "Registrazione push fallita. Verifica permesso notifiche e che il service worker sia cronos_sw.js (non flutter_service_worker)."
    );
  }

  function renderTools() {
    const container = ensureContainer();
    container.innerHTML = "";

    // iOS web: niente pulsante «Installa app» (l’utente lo fa da Safari se vuole).
    if (!isInStandaloneMode() && !isIos() && deferredInstallPrompt) {
      container.appendChild(mkButton("Installa app", askInstall));
    }

    // Solo se manca il permesso browser. La registrazione push (tab chiusa)
    // avviene in automatico al login se il permesso è già granted.
    if ("Notification" in window && Notification.permission !== "granted") {
      container.appendChild(mkButton("Abilita notifiche browser", askNotificationPermission));
    } else if (
      "Notification" in window &&
      Notification.permission === "granted" &&
      !_autoPushInFlight &&
      !isPushRegistered()
    ) {
      // Mostra subito se non risulta registrato (non solo dopo auto-fail).
      container.appendChild(
        mkButton("Registra push (tab chiusa)", () => {
          reregisterPushFromButton();
        })
      );
    }
  }

  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferredInstallPrompt = e;
    renderTools();
  });

  window.addEventListener("appinstalled", () => {
    deferredInstallPrompt = null;
    renderTools();
  });

  window.addEventListener("load", () => {
    try {
      const vapid = window.CRONOS_VAPID_PUBLIC_KEY || "";
      if (vapid) clearRegisteredIfVapidOrSwChanged(vapid);
    } catch (_) {}
    hydratePushBootstrapFromStorage();
    renderTools();
    // Registra subito il SW push (anche prima del login).
    ensurePushServiceWorker()
      .then(async (reg) => {
        if (!reg || !("Notification" in window)) return;
        if (Notification.permission !== "granted") return;
        try {
          const vapid = window.CRONOS_VAPID_PUBLIC_KEY || "";
          const prevVapid = localStorage.getItem(VAPID_LS_KEY) || "";
          if (vapid && prevVapid && prevVapid !== vapid) {
            renderTools();
            return;
          }
          const sub = await reg.pushManager.getSubscription();
          // NON marcare registrato solo perché esiste una sub locale:
          // senza upsert server le push a tab chiusa non arrivano.
          if (!sub && isPushRegistered()) {
            clearPushRegisteredFlags();
          }
          renderTools();
          await resyncWebPushIfPossible();
          keepListeningAfterClose();
        } catch (_) {}
      })
      .then(async () => {
        try {
          await syncChatAppBadge();
        } catch (_) {}
      })
      .catch((e) => {
        console.warn("ensurePushServiceWorker on load", e);
      });

    // Flutter può caricare dopo pwa_helper: ri-assicura cronos_sw e la sub.
    // (Se compare flutter_service_worker.js, unregister + resubscribe.)
    const reensure = () => {
      ensurePushServiceWorker()
        .then(async (reg) => {
          if (!reg || Notification.permission !== "granted") return;
          const sub = await reg.pushManager.getSubscription();
          if (!sub && isPushRegistered()) {
            clearPushRegisteredFlags();
            renderTools();
          }
          await resyncWebPushIfPossible();
        })
        .catch(() => {});
    };
    setTimeout(reensure, 2800);
    setTimeout(reensure, 7000);
  });

  function readStoredChatBadge() {
    try {
      const n = Number(localStorage.getItem("cronos_chat_app_badge") || 0);
      return Number.isFinite(n) && n > 0 ? Math.min(99, Math.floor(n)) : 0;
    } catch (_) {
      return 0;
    }
  }

  /** Chrome Android: ripristina badge icona Home (pagina + SW). */
  async function syncChatAppBadge() {
    const n = readStoredChatBadge();
    try {
      if (n <= 0) {
        if (typeof navigator.clearAppBadge === "function") {
          await navigator.clearAppBadge();
        }
      } else if (typeof navigator.setAppBadge === "function") {
        await navigator.setAppBadge(n);
      }
    } catch (_) {}
    try {
      const ctrl =
        navigator.serviceWorker && navigator.serviceWorker.controller;
      if (ctrl) {
        ctrl.postMessage({ type: "cronos-set-chat-badge", count: n });
        return;
      }
      if (!navigator.serviceWorker) return;
      const reg = await navigator.serviceWorker.ready;
      if (reg && reg.active) {
        reg.active.postMessage({ type: "cronos-set-chat-badge", count: n });
      }
    } catch (_) {}
  }

  function cronosPageIconUrl() {
    try {
      return new URL("icons/Icon-192.png", location.href).href;
    } catch (_) {
      return "icons/Icon-192.png";
    }
  }

  function listeningNotificationOptions() {
    const icon = cronosPageIconUrl();
    return {
      body: "Notifiche anche da app chiusa",
      tag: "cronos-listening",
      icon: icon,
      badge: icon,
      silent: false,
      renotify: false,
      requireInteraction: true,
      data: { url: "/", action: "listening" },
    };
  }

  function hideListeningBanner() {
    // Windows/iOS: niente banner sticky. Android: resta visibile in foreground.
    if (!isWindowsDesktop() && !isIos()) return;
    try {
      const ctrl =
        navigator.serviceWorker && navigator.serviceWorker.controller;
      if (ctrl) {
        ctrl.postMessage({ type: "cronos-hide-listening" });
      }
    } catch (_) {}
    try {
      const hide = (reg) => {
        if (!reg || typeof reg.getNotifications !== "function") return;
        reg.getNotifications({ tag: "cronos-listening" }).then((list) => {
          for (const n of list || []) {
            try {
              n.close();
            } catch (_) {}
          }
        }).catch(() => {});
      };
      if (pushRegistration) hide(pushRegistration);
      else if (navigator.serviceWorker) {
        navigator.serviceWorker.ready.then(hide).catch(() => {});
      }
    } catch (_) {}
  }

  /** Android: banner sticky. Windows/iOS: push senza banner (su iOS evita loop show/dismiss). */
  function keepListeningAfterClose() {
    persistNotificationSession();
    try {
      if (isWindowsDesktop() || isIos()) {
        hideListeningBanner();
        return;
      }
      if (!("Notification" in window) || Notification.permission !== "granted") {
        return;
      }
      if (!isPushSurfaceAllowed()) return;
      const opts = listeningNotificationOptions();
      const ctrl =
        navigator.serviceWorker && navigator.serviceWorker.controller;
      if (ctrl) {
        // Solo via SW: evita doppio showNotification (flicker).
        ctrl.postMessage({ type: "cronos-keep-listening" });
        return;
      }
      const show = (reg) => {
        if (!reg || typeof reg.showNotification !== "function") return;
        reg.showNotification("Cronos", opts).catch(() => {});
      };
      if (pushRegistration) {
        show(pushRegistration);
      } else if (navigator.serviceWorker) {
        navigator.serviceWorker.ready.then(show).catch(() => {});
      }
    } catch (_) {}
  }

  async function showOsNotification(title, body, tag) {
    const icon = cronosPageIconUrl();
    const opts = {
      body: body || "",
      tag: tag || ("cronos-" + Date.now()),
      icon: icon,
      badge: icon,
      silent: false,
      renotify: true,
      requireInteraction: true,
      data: { url: "/", action: "in_app" },
    };
    try {
      if ("Notification" in window && Notification.permission !== "granted") {
        return;
      }
      if (!isPushSurfaceAllowed()) return;
      const reg = pushRegistration || (await ensurePushServiceWorker());
      if (reg && typeof reg.showNotification === "function") {
        await reg.showNotification(title || "Cronos", opts);
        keepListeningAfterClose();
        return;
      }
    } catch (_) {}
    try {
      if ("Notification" in window && Notification.permission === "granted") {
        new Notification(title || "Cronos", opts);
      }
    } catch (_) {}
  }

  // Tab di nuovo aperta / focus / bfcache: mantiene attiva la subscription.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      hideListeningBanner();
      hydratePushBootstrapFromStorage();
      ensurePushServiceWorker()
        .then(() => resyncWebPushIfPossible())
        .catch(() => {});
      syncChatAppBadge().catch(() => {});
    } else {
      keepListeningAfterClose();
    }
  });
  window.addEventListener("focus", () => {
    hideListeningBanner();
    hydratePushBootstrapFromStorage();
    resyncWebPushIfPossible();
    syncChatAppBadge().catch(() => {});
  });
  window.addEventListener("pageshow", () => {
    hideListeningBanner();
    ensurePushServiceWorker()
      .then(() => resyncWebPushIfPossible())
      .catch(() => {});
    syncChatAppBadge().catch(() => {});
  });

  // Keepalive push: finché la tab/PWA è aperta, riallinea SW + subscription.
  // A tab chiusa la consegna resta sul Service Worker (PushSubscription).
  function startPushKeepalive() {
    const tick = () => {
      try {
        if (document.visibilityState !== "visible") return;
        if (!("Notification" in window) || Notification.permission !== "granted") {
          return;
        }
        if (!isPushSurfaceAllowed()) {
          hydratePushBootstrapFromStorage();
          const boot = window.cronosPushBootstrap || null;
          if (boot && boot.functionUrl && boot.accessToken) {
            revokePushOnNonCanonicalHost(boot.functionUrl, boot.accessToken);
          }
          return;
        }
        ensurePushServiceWorker()
          .then(async (reg) => {
            if (!reg || !reg.pushManager) return;
            let sub = null;
            try {
              sub = await reg.pushManager.getSubscription();
            } catch (_) {}
            if (!sub) {
              clearPushRegisteredFlags();
            }
            await resyncWebPushIfPossible();
          })
          .catch(() => {});
      } catch (_) {}
    };
    setInterval(tick, 30000);
    setTimeout(tick, 2500);
    setTimeout(tick, 8000);
    setTimeout(tick, 15000);
  }
  try {
    startPushKeepalive();
  } catch (_) {}

  try {
    window.addEventListener("freeze", () => keepListeningAfterClose());
    window.addEventListener("beforeunload", () => keepListeningAfterClose());
  } catch (_) {}

  // Alla chiusura finestra PWA: re-applica il badge così resta sulla taskbar Windows.
  window.addEventListener("pagehide", () => {
    keepListeningAfterClose();
    try {
      const n = readStoredChatBadge();
      if (n > 0 && typeof navigator.setAppBadge === "function") {
        navigator.setAppBadge(n).catch(() => {});
      }
      const ctrl =
        navigator.serviceWorker && navigator.serviceWorker.controller;
      if (ctrl) {
        ctrl.postMessage({ type: "cronos-set-chat-badge", count: n });
      }
    } catch (_) {}
  });

  // Push ricevuta dal service worker (anche con tab in background): suona subito.
  if ("serviceWorker" in navigator) {
    try {
      navigator.serviceWorker.addEventListener("message", (event) => {
        const data = event && event.data ? event.data : null;
        if (!data) return;
        if (data.type === "cronos-open-chat") {
          try {
            window.__cronosPendingOpenChat = true;
            window.dispatchEvent(new CustomEvent("cronos-open-chat"));
          } catch (_) {}
          return;
        }
        if (data.type !== "cronos-push-received") return;
        const key =
          String(data.title || "") + "|" + String(data.body || "");
        try {
          const inAppAt = window.__cronosInAppSoundAt || 0;
          const inAppKey = window.__cronosInAppSoundKey || "";
          if (
            inAppKey === key &&
            inAppAt &&
            Date.now() - Number(inAppAt) < 8000
          ) {
            return;
          }
          window.__cronosPushSoundAt = Date.now();
          window.__cronosPushSoundKey = key;
        } catch (_) {}
        playNotificationSound();
      });
    } catch (_) {}
  }

  if ("permissions" in navigator) {
    try {
      navigator.permissions.query({ name: "notifications" }).then((status) => {
        status.onchange = () => {
          renderTools();
          notifyPermissionChange();
        };
      });
    } catch (_) {}
  }

  window.cronosPwa = {
    initWebPush,
    subscribeWebPushIfPermitted,
    unsubscribeWebPush,
    registerWebPushWithSupabase,
    deactivateWebPushOnLogout,
    resyncWebPushIfPossible,
    askNotificationPermission,
    unlockNotificationSound,
    playNotificationSound,
    playSplashIntro,
    persistNotificationSession,
    reregisterPushFromButton,
    showOsNotification,
    keepListeningAfterClose,
    getNotificationPermission: () =>
      "Notification" in window ? Notification.permission : "unsupported",
    isPushRegistered,
    isCanonicalPushHost,
    isIos,
    isInStandaloneMode,
    isPushSurfaceAllowed,
    canUseWebPush: () =>
      "PushManager" in window &&
      "Notification" in window &&
      (!isMobileOs() || isInStandaloneMode()),
  };
})();
