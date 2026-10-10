import 'windows_webview2_bootstrap_stub.dart'
    if (dart.library.io) 'windows_webview2_bootstrap_io.dart' as impl;

Future<bool> bootstrapWindowsWebView2() => impl.bootstrapWindowsWebView2();

Future<bool> isWindowsWebView2Available() => impl.isWindowsWebView2Available();
