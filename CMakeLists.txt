cmake_minimum_required(VERSION 3.21)
project(super_booster VERSION 2.0.3 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Widgets Quick Qml QuickControls2 ShaderTools Network WebSockets)
qt_standard_project_setup(REQUIRES 6.5)

include(CTest)
if(BUILD_TESTING)
    add_executable(playback_selection_test tests/playback_selection.cpp)
    target_include_directories(playback_selection_test PRIVATE src)
    target_link_libraries(playback_selection_test PRIVATE Qt6::Core)
    add_test(NAME playback_selection COMMAND playback_selection_test)
endif()

set(SUPER_BOOSTER_PUSH_URL "wss://super-booster-release-push.auralis-updates.workers.dev/events"
    CACHE STRING "WebSocket used to announce Super Booster releases")

# Locate Cargo for building the Rust audio_core static library
find_program(CARGO_EXECUTABLE cargo HINTS "$ENV{USERPROFILE}/.cargo/bin" REQUIRED)

set(RUST_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/audio_core/Cargo.toml")
set(RUST_TARGET_DIR "${CMAKE_CURRENT_SOURCE_DIR}/audio_core/target")
set(RUST_LIB_PATH "${RUST_TARGET_DIR}/x86_64-pc-windows-gnu/release/libaudio_core.a")

add_custom_target(build_rust_audio_core ALL
    COMMAND "${CARGO_EXECUTABLE}" build --release --target x86_64-pc-windows-gnu --manifest-path "${RUST_MANIFEST}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/audio_core"
    BYPRODUCTS "${RUST_LIB_PATH}"
    COMMENT "Building Rust audio_core engine (WASAPI + DSP)..."
)

add_library(audio_core STATIC IMPORTED GLOBAL)
set_target_properties(audio_core PROPERTIES IMPORTED_LOCATION "${RUST_LIB_PATH}")
add_dependencies(audio_core build_rust_audio_core)

qt_add_executable(super_booster
    WIN32
    src/main.cpp
    src/app_backend.h
    src/app_backend.cpp
    src/win_window_helper.h
    src/win_window_helper.cpp
    src/windows_audio_route.cpp
    src/audio_ffi.h
    src/updater.cpp
    src/updater.h
)

target_compile_definitions(super_booster PRIVATE
    SUPER_BOOSTER_VERSION="${PROJECT_VERSION}"
    SUPER_BOOSTER_PUSH_URL="${SUPER_BOOSTER_PUSH_URL}"
)

qt_add_qml_module(super_booster
    URI SuperBoosterUI
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/MiniPopup.qml
        qml/GlassCard.qml
        qml/BoostSlider.qml
        qml/UpdateNotice.qml
)

qt_add_resources(super_booster "superbooster_icons"
    PREFIX "/icons"
    BASE assets
    FILES assets/super-booster.ico
)

qt_add_shaders(super_booster "superbooster_shaders"
    PREFIX "/"
    FILES
        shaders/glass_backdrop.frag
        shaders/audio_orb.frag
        shaders/spectrum_glow.frag
)

target_link_libraries(super_booster PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    Qt6::Network
    Qt6::WebSockets
    audio_core
)

if(WIN32)
    enable_language(RC)
    add_executable(super_booster_update_helper WIN32 src/update_helper.cpp)
    target_link_libraries(super_booster_update_helper PRIVATE advapi32 bcrypt shell32 user32)
    if(MINGW)
        target_link_options(super_booster_update_helper PRIVATE -municode -static -static-libgcc -static-libstdc++)
    endif()
    target_sources(super_booster PRIVATE assets/super-booster.rc)
    target_include_directories(super_booster PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/assets")
    set_source_files_properties(assets/super-booster.rc PROPERTIES
        OBJECT_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/assets/super-booster.ico")
    target_link_libraries(super_booster PRIVATE
        dwmapi
        advapi32
        user32
        kernel32
        ole32
        oleaut32
        propsys
        avrt
        mmdevapi
        ws2_32
        userenv
        bcrypt
        ntdll
        crypt32
        secur32
        ncrypt
        runtimeobject
        synchronization
    )
endif()
