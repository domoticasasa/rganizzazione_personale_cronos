cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Icona dell'app Windows
set(APPLICATION_ICON "${CMAKE_CURRENT_SOURCE_DIR}/resources/app_icon.ico")

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer work.

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
)

# Applica configurazioni standard
apply_standard_settings(${BINARY_NAME})

# Sopprime LNK4099 (PDB non trovati per lib precompilate plugin)
if(MSVC)
  target_link_options(${BINARY_NAME} PRIVATE /IGNORE:4099)
endif()

# Versioni flutter
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Necessario per evitare macro windows
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Link librerie
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "shell32.lib" "ole32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Collega l'icona come risorsa
if(WIN32)
  target_sources(${BINARY_NAME} PRIVATE "Runner.rc")
endif()

# Dipendenze flutter
add_dependencies(${BINARY_NAME} flutter_assemble)