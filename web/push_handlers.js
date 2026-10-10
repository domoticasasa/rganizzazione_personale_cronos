// Handler push condivisi (usati da cronos_sw.js e push-sw.js).
// Devono mostrare SEMPRE una notifica visibile (userVisibleOnly) anche a tab chiusa.
// v12: niente banner OS se c'è una tab visibile (una sola consegna).

function cronosAssetUrl(path) {
  try {
    return new URL(path, self.registration.scope).href;
  } catch (_) {
    return path;
  }
}

function cronosChatBadgeCacheUrl() {
  try {
    return new URL("cronos-chat-badge", self.registration.scope).href;
  } catch (_) {
    return "cronos-chat-badge";
  }
}

async function cronosPersistChatBadge(n) {
  try {
    const cache = await caches.open("cronos-chat-badge-v1");
    await cache.put(
      cronosChatBadgeCacheUrl(),
      new Response(String(n), {
        headers: { "Content-Type": "text/plain" },
      }),
    );
  } catch (_) {}
}

async function cronosRestoreChatBadge() {
  try {
    const cache = await caches.open("cronos-chat-badge-v1");
    const res = await cache.match(cronosChatBadgeCacheUrl());
    if (!res) return;
    const n = Number(await res.text());
    if (!Number.isFinite(n)) return;
    await cronosSetChatAppBadge(n);
  } catch (_) {}
}

async function cronosReadPersistedChatBadge() {
  try {
    const cache = await caches.open("cronos-chat-badge-v1");
    const res = await cache.match(cronosChatBadgeCacheUrl());
    if (!res) return 0;
    const n = Number(await res.text());
    return Number.isFinite(n) && n > 0 ? Math.min(99, Math.floor(n)) : 0;
  } catch (_) {
    return 0;
  }
}

async function cronosBumpChatAppBadge() {
  try {
    // SW può essere ripartito a freddo: recupera il valore salvato prima di +1.
    let prev = Number(self.__cronosChatBadge);
    if (!Number.isFinite(prev) || prev < 0) {
      prev = await cronosReadPersistedChatBadge();
    }
    const n = Math.min(99, prev + 1);
    await cronosSetChatAppBadge(n);
  } catch (_) {}
}

async function cronosSetChatAppBadge(count) {
  try {
    const n = Math.max(0, Math.min(99, Number(count) || 0));
    self.__cronosChatBadge = n;
    await cronosPersistChatBadge(n);
    if (!self.navigator) return;
    if (n <= 0) {
      if (typeof self.navigator.clearAppBadge === "function") {
        await self.navigator.clearAppBadge();
      }
      return;
    }
    if (typeof self.navigator.setAppBadge === "function") {
      // Numero; se fallisce, almeno il pallino.
      try {
        await self.navigator.setAppBadge(n);
      } catch (_) {
        await self.navigator.setAppBadge();
      }
    }
  } catch (_) {}
}

function cronosIsChatPush(data) {
  const action = String((data && data.action) || "");
  const tag = String((data && data.tag) || "");
  const url = String((data && data.url) || "");
  return (
    action === "app_chat" ||
    action === "app_chat_dm" ||
    action === "app_chat_group" ||
    tag.indexOf("app-chat") === 0 ||
    url.indexOf("openChat") >= 0
  );
}

const CRONOS_LISTENING_TAG = "cronos-listening";

function cronosNotificationIconUrl() {
  return cronosAssetUrl("icons/Icon-192.png");
}

function cronosIsWindowsDesktop() {
  try {
    const ua = String((self.navigator && self.navigator.userAgent) || "");
    return /Windows/i.test(ua) && !/Android/i.test(ua);
  } catch (_) {
    return false;
  }
}

function cronosIsIos() {
  try {
    const ua = String((self.navigator && self.navigator.userAgent) || "").toLowerCase();
    return /iphone|ipad|ipod/.test(ua);
  } catch (_) {
    return false;
  }
}

/** Banner sticky "listening": solo Android. Windows/iOS = quiet. */
function cronosIsListeningQuiet() {
  return cronosIsWindowsDesktop() || cronosIsIos();
}

function cronosIsListeningNotification(notification) {
  try {
    const tag = String((notification && notification.tag) || "");
    const action = String((notification && notification.data && notification.data.action) || "");
    return tag === CRONOS_LISTENING_TAG || action === "listening";
  } catch (_) {
    return false;
  }
}

async function cronosHideListeningNotification() {
  try {
    const list = await self.registration.getNotifications({
      tag: CRONOS_LISTENING_TAG,
    });
    for (const n of list || []) {
      try {
        n.close();
      } catch (_) {}
    }
  } catch (_) {}
}

async function cronosShowListeningNotification(options) {
  // Windows/iOS: push senza banner sticky (su iOS WebKit evita loop show/dismiss).
  if (
    cronosIsListeningQuiet() ||
    (options && (options.windowsQuiet || options.iosQuiet))
  ) {
    await cronosHideListeningNotification();
    return true;
  }
  const icon = cronosNotificationIconUrl();
  const opts = {
    body: "Notifiche anche da app chiusa",
    tag: CRONOS_LISTENING_TAG,
    icon: icon,
    badge: icon,
    silent: false,
    renotify: false,
    requireInteraction: true,
    data: { url: "/", action: "listening" },
  };
  if (await cronosShowNotification("Cronos", opts)) return true;
  try {
    await self.registration.showNotification("Cronos", opts);
    return true;
  } catch (e) {
    console.warn("cronos listening notification failed", e);
    return false;
  }
}

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      await cronosRestoreChatBadge();
      try {
        const sub = await self.registration.pushManager.getSubscription();
        if (!sub) return;
        if (cronosIsListeningQuiet()) {
          await cronosHideListeningNotification();
          return;
        }
        await cronosShowListeningNotification();
      } catch (_) {}
    })(),
  );
});

self.addEventListener("message", (event) => {
  try {
    const data = event && event.data ? event.data : null;
    if (!data || !data.type) return;
    if (data.type === "cronos-set-chat-badge") {
      event.waitUntil(cronosSetChatAppBadge(data.count));
      return;
    }
    if (data.type === "cronos-hide-listening") {
      event.waitUntil(cronosHideListeningNotification());
      return;
    }
    if (data.type === "cronos-keep-listening") {
      event.waitUntil(
        cronosShowListeningNotification({
          windowsQuiet: !!data.windowsQuiet,
        }),
      );
    }
  } catch (_) {}
});

async function cronosShowNotification(title, options) {
  try {
    await self.registration.showNotification(title, options);
    return true;
  } catch (e) {
    console.warn("cronos showNotification failed", e, options);
    return false;
  }
}

self.addEventListener("push", (event) => {
  let data = {};
  try {
    if (event.data) {
      try {
        data = event.data.json();
      } catch (_) {
        const text = event.data.text();
        data = { body: text, title: "Cronos" };
      }
    }
  } catch (_) {
    data = {};
  }

  const title = (data.title || "Cronos Gestopro").toString();
  const body = (data.body || "Nuova notifica").toString();
  const url = (data.url || "/").toString();
  const tag = (
    data.tag ||
    data.booking_id ||
    data.action ||
    ("cronos-" + Date.now())
  ).toString();

  const icon = cronosNotificationIconUrl();
  const payloadData = {
    url,
    booking_id: data.booking_id,
    action: data.action,
    message_id: data.message_id,
  };

  event.waitUntil(
    (async () => {
      // Solo finestra in FOCUS = app davvero in uso.
      // Minimizzata / chiusa: visibility può restare ambigua su Windows.
      let hasFocusedClient = false;
      try {
        const list = await self.clients.matchAll({
          type: "window",
          includeUncontrolled: true,
        });
        for (const client of list) {
          try {
            if (client.focused === true) {
              hasFocusedClient = true;
            }
            client.postMessage({
              type: "cronos-push-received",
              title,
              body,
              action: data.action || "",
            });
          } catch (_) {}
        }
      } catch (_) {}

      const isChat = cronosIsChatPush(data);

      // SEMPRE toast OS (tab chiusa / aperta). I push "silenziosi" fanno revocare
      // la PushSubscription in Chrome (userVisibleOnly). Flutter deduplica.

      // Conta + badge SUBITO (anche se la toast fallisce): serve a app chiusa.
      let badgeN = 0;
      if (isChat) {
        try {
          await cronosBumpChatAppBadge();
          badgeN = Number(self.__cronosChatBadge || 0) || 0;
          if (badgeN > 0 && typeof self.navigator?.setAppBadge === "function") {
            try {
              await self.navigator.setAppBadge(badgeN);
            } catch (_) {
              try {
                await self.navigator.setAppBadge();
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      const notifyTitle =
        isChat && badgeN > 0
          ? "(" + (badgeN > 99 ? "99+" : String(badgeN)) + ") " + title
          : title;

      // Sempre icona Cronos (senza icon/badge Chrome usa il logo Chrome).
      const attempts = [
        {
          body,
          tag,
          data: payloadData,
          icon: icon,
          badge: icon,
          requireInteraction: true,
          silent: false,
          renotify: true,
        },
        {
          body,
          silent: false,
          tag,
          data: payloadData,
          icon: icon,
          badge: icon,
          requireInteraction: isChat,
        },
        {
          body,
          silent: false,
          tag,
          data: payloadData,
          requireInteraction: isChat,
        },
      ];

      let shown = false;
      for (const opts of attempts) {
        if (await cronosShowNotification(notifyTitle, opts)) {
          shown = true;
          break;
        }
      }
      if (!shown) {
        try {
          await self.registration.showNotification(notifyTitle || "Cronos", {
            body: body || "Nuova notifica",
            tag,
            icon: icon,
            badge: icon,
            data: payloadData,
            requireInteraction: true,
          });
          shown = true;
        } catch (e) {
          console.error("cronos showNotification ultimate fallback failed", e);
        }
      }

      try {
        if (cronosIsListeningQuiet()) {
          await cronosHideListeningNotification();
        } else {
          await cronosShowListeningNotification();
        }
      } catch (_) {}

      // Re-applica badge dopo la toast (Chrome/Edge Windows).
      if (isChat && badgeN > 0 && typeof self.navigator?.setAppBadge === "function") {
        try {
          await self.navigator.setAppBadge(badgeN);
        } catch (_) {}
      }
    })(),
  );
});

self.addEventListener("notificationclick", (event) => {
  const listening = cronosIsListeningNotification(event.notification);
  event.notification.close();
  let targetUrl = event.notification?.data?.url || "/";
  try {
    const action = String(event.notification?.data?.action || "");
    const isChat =
      !listening &&
      (action === "app_chat" ||
        action === "app_chat_dm" ||
        action === "app_chat_group");
    if (isChat && String(targetUrl).indexOf("openChat") < 0) {
      targetUrl = "/?openChat=1";
    }
  } catch (_) {}
  if (listening) {
    event.waitUntil(
      (async () => {
        try {
          if (cronosIsListeningQuiet()) {
            await cronosHideListeningNotification();
          } else {
            await cronosShowListeningNotification();
          }
        } catch (_) {}
        const list = await clients.matchAll({
          type: "window",
          includeUncontrolled: true,
        });
        for (const client of list) {
          if ("focus" in client) return client.focus();
        }
        if (clients.openWindow) return clients.openWindow("/");
      })(),
    );
    return;
  }
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ("focus" in client) {
          try {
            // Sempre: Flutter ascolta cronos-open-chat (app già aperta su Android).
            client.postMessage({ type: "cronos-open-chat" });
            if (typeof client.navigate === "function") {
              client.navigate(targetUrl);
            }
          } catch (_) {}
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
      return undefined;
    }),
  );
});

function cronosUrlB64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

async function cronosRefreshAccessToken(session) {
  const supabaseUrl = String(session?.supabaseUrl || "").replace(/\/+$/, "");
  const anonKey = String(session?.anonKey || "").trim();
  const refreshToken = String(session?.refreshToken || "").trim();
  if (!supabaseUrl || !anonKey || !refreshToken) return session;
  try {
    const res = await fetch(supabaseUrl + "/auth/v1/token?grant_type=refresh_token", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey,
        Authorization: "Bearer " + anonKey,
      },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
    if (!res.ok) return session;
    const body = await res.json();
    const next = Object.assign({}, session, {
      accessToken: String(body.access_token || session.accessToken || "").trim(),
      refreshToken: String(body.refresh_token || refreshToken).trim(),
      savedAt: Date.now(),
    });
    try {
      if (self.cronosPushSession && typeof self.cronosPushSession.save === "function") {
        await self.cronosPushSession.save(next);
      }
    } catch (_) {}
    return next;
  } catch (e) {
    console.warn("cronos refresh access token", e);
    return session;
  }
}

async function cronosUpsertPushSubscription(subscriptionJson, session) {
  let boot = session;
  if (!boot && self.cronosPushSession && typeof self.cronosPushSession.load === "function") {
    boot = await self.cronosPushSession.load();
  }
  if (!boot || !boot.functionUrl || !boot.accessToken) return false;
  if (!subscriptionJson || !subscriptionJson.endpoint) return false;
  const post = async (token) =>
    fetch(boot.functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer " + token,
      },
      body: JSON.stringify({
        action: "subscribe",
        subscription: subscriptionJson,
        user_agent: (self.navigator && self.navigator.userAgent) || "cronos-sw",
        origin: self.registration ? self.registration.scope : "",
      }),
    });
  let res = await post(boot.accessToken);
  if (res.status === 401) {
    boot = await cronosRefreshAccessToken(boot);
    if (boot && boot.accessToken) {
      res = await post(boot.accessToken);
    }
  }
  return !!(res && res.ok);
}

// Chrome può ruotare l'endpoint anche a PWA chiusa. Senza questo handler
// la riga su Supabase resta sull'endpoint morto e le toast smettono di arrivare.
self.addEventListener("pushsubscriptionchange", (event) => {
  event.waitUntil(
    (async () => {
      try {
        let session = null;
        if (self.cronosPushSession && typeof self.cronosPushSession.load === "function") {
          session = await self.cronosPushSession.load();
        }
        const vapid = session && session.vapidPublicKey ? session.vapidPublicKey : "";
        const opts = { userVisibleOnly: true };
        if (vapid) {
          opts.applicationServerKey = cronosUrlB64ToUint8Array(vapid);
        }
        const sub = await self.registration.pushManager.subscribe(opts);
        const json = sub && typeof sub.toJSON === "function" ? sub.toJSON() : null;
        await cronosUpsertPushSubscription(json, session);
      } catch (e) {
        console.error("cronos pushsubscriptionchange", e);
      }
    })(),
  );
});
