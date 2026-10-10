import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void setPreferHybridPasskey(bool value) {
  globalContext.setProperty('__cronosPreferHybridPasskey'.toJS, value.toJS);
}

void setPreferPlatformPasskey(bool value) {
  globalContext.setProperty('__cronosPreferPlatformPasskey'.toJS, value.toJS);
}

bool get preferHybridPasskeyActive {
  try {
    final v = globalContext.getProperty('__cronosPreferHybridPasskey'.toJS);
    if (v == null || v.isUndefinedOrNull) return false;
    return (v as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}
