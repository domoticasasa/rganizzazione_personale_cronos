{{flutter_js}}
{{flutter_build_config}}

// NON passare serviceWorkerSettings: con serviceWorkerVersion:null Flutter
// registra comunque flutter_service_worker.js che in activate fa unregister()
// e cancella la PushSubscription (push morte a tab chiusa su mobile).
// Il SW push è solo cronos_sw.js (pwa_helper.js).
//
// Preferisci risorse locali (CanvasKit) se presenti nella build, così non dipende
// da fonts.gstatic.com / www.gstatic.com quando la rete le blocca.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
