#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kRunnerClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kRunnerTitle[] = L"organizzazione_personale_cronos";

bool ActivateExistingInstance() {
  HWND existing = ::FindWindowW(kRunnerClassName, kRunnerTitle);
  if (existing == nullptr) {
    // Fallback: cerca per classe anche se il titolo dovesse cambiare.
    existing = ::FindWindowW(kRunnerClassName, nullptr);
  }
  if (existing == nullptr) return false;

  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  } else {
    ::ShowWindow(existing, SW_SHOW);
  }
  ::SetForegroundWindow(existing);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single-instance robusto:
  // 1) se esiste gia' una finestra Cronos, la riattiva e termina subito;
  // 2) mutex globale come ulteriore guardia contro race all'avvio.
  if (ActivateExistingInstance()) {
    return EXIT_SUCCESS;
  }

  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE,
                     L"Global\\organizzazione_personale_cronos_single_instance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstance();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  POINT pt{static_cast<LONG>(origin.x), static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
  if (GetMonitorInfo(monitor, &mi)) {
    const int work_w = mi.rcWork.right - mi.rcWork.left;
    const int work_h = mi.rcWork.bottom - mi.rcWork.top;
    unsigned w = size.width;
    unsigned h = size.height;
    if (static_cast<int>(w) > work_w) {
      w = work_w > 40 ? static_cast<unsigned>(work_w - 20) : static_cast<unsigned>(work_w);
    }
    if (static_cast<int>(h) > work_h) {
      h = work_h > 40 ? static_cast<unsigned>(work_h - 20) : static_cast<unsigned>(work_h);
    }
    size = Win32Window::Size(w, h);
  }
  if (!window.Create(L"organizzazione_personale_cronos", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
