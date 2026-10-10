#include "flutter_window.h"

#include <memory>
#include <optional>
#include <string>
#include <variant>

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return L"";
  }
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (len <= 0) {
    return L"";
  }
  std::wstring w(static_cast<size_t>(len - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, w.data(), len);
  return w;
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_taskbar_icon_channel;
FlutterWindow* g_flutter_window_for_icons = nullptr;
HICON g_loaded_icon_sm = nullptr;
HICON g_loaded_icon_lg = nullptr;
HICON g_overlay_icon = nullptr;
ITaskbarList3* g_taskbar_list = nullptr;

bool EnsureTaskbarList() {
  if (g_taskbar_list != nullptr) {
    return true;
  }
  HRESULT hr = CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                IID_ITaskbarList3,
                                reinterpret_cast<void**>(&g_taskbar_list));
  if (FAILED(hr) || g_taskbar_list == nullptr) {
    return false;
  }
  hr = g_taskbar_list->HrInit();
  return SUCCEEDED(hr);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  g_flutter_window_for_icons = this;
  g_taskbar_icon_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "organizzazione_personale_cronos/taskbar_icon",
          &flutter::StandardMethodCodec::GetInstance());
  g_taskbar_icon_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string method = call.method_name();
        HWND hwnd = g_flutter_window_for_icons
                        ? g_flutter_window_for_icons->GetHandle()
                        : nullptr;
        if (!hwnd) {
          result->Error("no_hwnd", "window handle null",
                        flutter::EncodableValue());
          return;
        }

        if (method == "clearOverlay") {
          if (EnsureTaskbarList()) {
            g_taskbar_list->SetOverlayIcon(hwnd, nullptr, L"");
          }
          if (g_overlay_icon) {
            DestroyIcon(g_overlay_icon);
            g_overlay_icon = nullptr;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (!call.arguments() ||
            !std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
          result->Error("bad_args", "expected map", flutter::EncodableValue());
          return;
        }
        const flutter::EncodableMap& args =
            std::get<flutter::EncodableMap>(*call.arguments());
        auto it = args.find(flutter::EncodableValue("path"));
        if (it == args.end()) {
          result->Error("bad_args", "missing path", flutter::EncodableValue());
          return;
        }
        const std::string* path_utf8 =
            std::get_if<std::string>(&it->second);
        if (!path_utf8 || path_utf8->empty()) {
          result->Error("bad_args", "path not string", flutter::EncodableValue());
          return;
        }
        std::wstring wpath = Utf8ToWide(*path_utf8);
        if (method == "setOverlay") {
          HICON h_overlay = (HICON)(LoadImageW(
              nullptr, wpath.c_str(), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
              GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));
          if (!h_overlay) {
            result->Error("load_failed", "LoadImageW overlay failed",
                          flutter::EncodableValue(*path_utf8));
            return;
          }
          std::wstring desc = L"Notifica";
          auto d = args.find(flutter::EncodableValue("description"));
          if (d != args.end()) {
            const std::string* ds = std::get_if<std::string>(&d->second);
            if (ds && !ds->empty()) {
              desc = Utf8ToWide(*ds);
            }
          }
          if (!EnsureTaskbarList()) {
            DestroyIcon(h_overlay);
            result->Error("taskbar_api", "ITaskbarList3 init failed",
                          flutter::EncodableValue());
            return;
          }
          if (g_overlay_icon) {
            DestroyIcon(g_overlay_icon);
          }
          g_overlay_icon = h_overlay;
          g_taskbar_list->SetOverlayIcon(hwnd, g_overlay_icon, desc.c_str());
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method != "setIcon") {
          result->NotImplemented();
          return;
        }

        HICON h_sm = (HICON)(LoadImageW(
            nullptr, wpath.c_str(), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
            GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));
        HICON h_lg = (HICON)(LoadImageW(
            nullptr, wpath.c_str(), IMAGE_ICON, GetSystemMetrics(SM_CXICON),
            GetSystemMetrics(SM_CYICON), LR_LOADFROMFILE));
        if (!h_sm || !h_lg) {
          result->Error("load_failed", "LoadImageW failed",
                        flutter::EncodableValue(*path_utf8));
          return;
        }

        if (g_loaded_icon_sm) {
          DestroyIcon(g_loaded_icon_sm);
        }
        if (g_loaded_icon_lg) {
          DestroyIcon(g_loaded_icon_lg);
        }
        g_loaded_icon_sm = h_sm;
        g_loaded_icon_lg = h_lg;

        SendMessage(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)h_sm);
        SendMessage(hwnd, WM_SETICON, ICON_BIG, (LPARAM)h_lg);
        SetClassLongPtr(hwnd, GCLP_HICONSM, (LONG_PTR)h_sm);
        SetClassLongPtr(hwnd, GCLP_HICON, (LONG_PTR)h_lg);
        SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);

        result->Success(flutter::EncodableValue(true));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  g_taskbar_icon_channel.reset();
  g_flutter_window_for_icons = nullptr;
  if (g_overlay_icon) {
    DestroyIcon(g_overlay_icon);
    g_overlay_icon = nullptr;
  }
  if (g_taskbar_list) {
    g_taskbar_list->Release();
    g_taskbar_list = nullptr;
  }
  g_loaded_icon_sm = nullptr;
  g_loaded_icon_lg = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
