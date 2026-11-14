cmake_minimum_required(VERSION 3.21)
project(ShadowLauncher VERSION 1.0.1 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)  # Qt default
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# ============================================================
# 构建选项
# ============================================================

# 内测密钥闸门（Beta gate）：
#   ON  = 内测版：启动先弹 BetaKeyDialog 密钥验证窗口（无保存密钥时）
#   OFF = 公测版：直接加载 MainWindow，跳过内测验证（默认）
# 加回内测：cmake 重新配置 -DSHADOW_ENABLE_BETA_GATE=ON 即可，相关代码/资源全部保留。
option(SHADOW_ENABLE_BETA_GATE "Enable beta key gate (internal testing)" OFF)

# ============================================================
# Dependencies
# ============================================================

# Qt 6.8 LTS
set(CMAKE_PREFIX_PATH "C:/Qt/6.8.3/msvc2022_64")
find_package(Qt6 6.8 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    QuickLayouts
    Concurrent
    Network
    Widgets
    LinguistTools
)

# nlohmann/json (header-only 鈥?manually downloaded)
add_library(nlohmann_json INTERFACE)
target_include_directories(nlohmann_json INTERFACE src/third_party/nlohmann)

# cpr (libcurl C++ wrapper) 鈥?TODO: install via vcpkg or manual
# For Phase 1 build test, use Qt Network as fallback
# Uncomment when cpr is available:
# include(FetchContent)
# FetchContent_Declare(cpr ...) 
# FetchContent_MakeAvailable(cpr)
# target_link_libraries(... cpr::cpr)

# ============================================================
# Sources
# ============================================================

set(SOURCES
    src/main_release.cpp

    # Utilities (Phase 4 鈥?structured logging)
    src/utils/logger.cpp
    src/utils/temp_tracker.cpp
    src/utils/token_crypto.cpp

    # Core services (Phase 2 鈥?added progressively)
    src/core/http_client.cpp
    src/core/resource_fetch_engine.cpp
    src/core/cf_api.cpp
    src/core/logger.cpp
    src/core/version_manager.cpp
    src/core/file_downloader.cpp
    src/core/asset_downloader.cpp
    src/core/version_downloader.cpp
    src/core/launcher.cpp
    src/core/mc_language.cpp
    src/core/geoip_service.cpp
    src/core/mod_manager.cpp
    src/core/icon_cache.cpp
    src/core/microsoft_auth.cpp
    src/core/yggdrasil_auth.cpp
    src/core/version_isolation.cpp
    src/core/minecraft_layout.cpp
    src/core/mod_loader_installer.cpp
    src/core/java_runtime_installer.cpp
    src/core/local_mod_manager.cpp
    src/core/modpack_importer.cpp
    src/core/modpack/modpack_common.cpp
    src/core/modpack/zip_archive.cpp
    src/core/modpack/modpack_parser.cpp
    src/core/modpack/modpack_downloader.cpp
    src/core/modpack/mod_download_engine.cpp
    src/core/modpack/modpack_install_task.cpp
    src/core/modpack/modpack_exporter.cpp
    src/core/update_manager.cpp
    thirdparty/miniz/miniz.c
    src/utils/lzma/LzmaDec.c
    src/core/crash_detector.cpp
    src/core/screenshot_server.cpp
    src/core/step_node.cpp
    src/core/step_pipeline.cpp
    # Backend (Phase 3 鈥?added progressively)
    src/backend/app_backend.cpp
    src/backend/settings_backend.cpp
    src/backend/yggdrasil_backend.cpp
    src/backend/yggdrasil_skin_fetcher.cpp
    src/backend/account_backend.cpp
    src/backend/version_backend.cpp
    src/session/download_session.cpp
    src/backend/launch_backend.cpp
    src/backend/resource_backend.cpp
    src/backend/java_backend.cpp
    src/backend/check_backend.cpp
    src/backend/userdata_backend.cpp
    src/backend/debug_logger.cpp
    src/backend/minecraft_folder_backend.cpp

    # Unified backend wrapper (Phase 4)
    src/backend/shadow_backend.cpp

    # Independent next-generation UI presentation layer
    src/ui_next/appearance_controller.cpp
    # 下载步骤不确定环：QQuickItem + QSGNode（照 Qt Material BusyIndicator 的结构）
    src/ui_next/dl_spinner_item.cpp
)

set(HEADERS
    src/utils/types.h
    src/utils/logger.h
    src/utils/temp_tracker.h
    src/core/http_client.h
    src/core/resource_fetch_engine.h
    src/core/cf_api.h
    src/core/logger.h
    src/core/version_manager.h
    src/core/file_downloader.h
    src/core/asset_downloader.h
    src/core/version_downloader.h
    src/core/step_node.h
    src/core/step_pipeline.h
    src/core/launcher.h
    src/core/mc_language.h
    src/core/geoip_service.h
    src/core/mod_manager.h
    src/core/local_mod_manager.h
    src/core/modpack_importer.h
    src/core/modpack/modpack_common.h
    src/core/modpack/zip_archive.h
    src/core/modpack/modpack_parser.h
    src/core/modpack/modpack_downloader.h
    src/core/modpack/mod_download_engine.h
    src/core/modpack/modpack_install_task.h
    src/core/modpack/modpack_exporter.h
    src/core/update_manager.h
    src/core/version_isolation.h
    src/core/minecraft_layout.h
    src/core/yggdrasil_auth.h
    src/core/crash_detector.h
    src/core/screenshot_server.h
    src/backend/app_backend.h
    src/backend/settings_backend.h
    src/backend/yggdrasil_backend.h
    src/backend/yggdrasil_skin_fetcher.h
    src/backend/account_backend.h
    src/backend/version_backend.h
    src/backend/launch_backend.h
    src/backend/resource_backend.h
    src/backend/check_backend.h
    src/backend/userdata_backend.h
    src/backend/debug_logger.h
    src/backend/minecraft_folder_backend.h

    # Unified backend wrapper (Phase 4)
    src/backend/shadow_backend.h

    src/ui_next/appearance_controller.h
    src/ui_next/dl_spinner_item.h

    src/multiplayer/room_code.cpp
    src/multiplayer/room_code.h
    src/multiplayer/scaffolding_protocol.cpp
    src/multiplayer/scaffolding_protocol.h
    src/multiplayer/connection_guard.cpp
    src/multiplayer/connection_guard.h
    src/multiplayer/relay_crypto.cpp
    src/multiplayer/relay_crypto.h
    src/multiplayer/encrypted_addr.h
    src/multiplayer/easytier_process.cpp
    src/multiplayer/easytier_process.h
    src/multiplayer/multiplayer_manager.cpp
    src/multiplayer/multiplayer_manager.h
    src/multiplayer/mc_scanner.cpp
    src/multiplayer/mc_scanner.h
    src/multiplayer/port_request.cpp
    src/multiplayer/port_request.h
)

# Encrypted blob fragments (scrambled, split across compilation units)
# Real files exist only on the developer's machine (gitignored).
# CI/third-party builds use the stub with zero placeholders.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/multiplayer/encrypted_frag_1.cpp")
    list(APPEND SOURCES
        src/multiplayer/encrypted_frag_1.cpp
        src/multiplayer/encrypted_frag_2.cpp
        src/multiplayer/encrypted_frag_3.cpp
        src/multiplayer/encrypted_frag_4.cpp
        src/multiplayer/encrypted_frag_5.cpp
    )
else()
    list(APPEND SOURCES src/multiplayer/encrypted_frag_stub.cpp)
endif()

# ============================================================
# Target
# ============================================================

# 鈹€鈹€ App icon (.ico must be next to .rc during rc compilation) 鈹€鈹€
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/resources/app.ico"
    "${CMAKE_CURRENT_BINARY_DIR}/app.ico"
    COPYONLY
)

qt_add_executable(ShadowLauncher ${SOURCES} ${HEADERS} resources/app.rc)
add_dependencies(ShadowLauncher SLUpdater)

qt_policy(SET QTP0004 NEW)

# ============================================================
# 新一代 UI（ui/）—— URI ShadowLauncher.Next，入口 Main.qml
# 说明：旧的 qml-next/ 已废弃并从本仓库移除（Qcoder 第三轮产物）。
# ============================================================
set_source_files_properties(ui/Main.qml PROPERTIES QT_RESOURCE_ALIAS Main.qml)
set_source_files_properties(ui/Theme.qml PROPERTIES QT_RESOURCE_ALIAS Theme.qml QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(ui/StageShell.qml PROPERTIES QT_RESOURCE_ALIAS StageShell.qml)
set_source_files_properties(ui/SideBar.qml PROPERTIES QT_RESOURCE_ALIAS SideBar.qml)
set_source_files_properties(ui/pages/StagePage.qml PROPERTIES QT_RESOURCE_ALIAS pages/StagePage.qml)
set_source_files_properties(ui/pages/VersionPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/VersionPage.qml)
set_source_files_properties(ui/pages/AccountPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/AccountPage.qml)
set_source_files_properties(ui/pages/DownloadPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/DownloadPage.qml)
set_source_files_properties(ui/pages/ProgressPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/ProgressPage.qml)
set_source_files_properties(ui/LaunchOverlay.qml PROPERTIES QT_RESOURCE_ALIAS LaunchOverlay.qml)
set_source_files_properties(ui/controls/SIcon.qml PROPERTIES QT_RESOURCE_ALIAS controls/SIcon.qml)
set_source_files_properties(ui/controls/SButton.qml PROPERTIES QT_RESOURCE_ALIAS controls/SButton.qml)
set_source_files_properties(ui/controls/SBgImage.qml PROPERTIES QT_RESOURCE_ALIAS controls/SBgImage.qml)
set_source_files_properties(ui/controls/SWindowButton.qml PROPERTIES QT_RESOURCE_ALIAS controls/SWindowButton.qml)
set_source_files_properties(ui/controls/SAcctChip.qml PROPERTIES QT_RESOURCE_ALIAS controls/SAcctChip.qml)
set_source_files_properties(ui/controls/SMinecraftHead.qml PROPERTIES QT_RESOURCE_ALIAS controls/SMinecraftHead.qml)
set_source_files_properties(ui/controls/SLoadingBar.qml PROPERTIES QT_RESOURCE_ALIAS controls/SLoadingBar.qml)
set_source_files_properties(ui/controls/ResourceTile.qml PROPERTIES QT_RESOURCE_ALIAS controls/ResourceTile.qml)
set_source_files_properties(ui/controls/SField.qml PROPERTIES QT_RESOURCE_ALIAS controls/SField.qml)
set_source_files_properties(ui/controls/SShimmer.qml PROPERTIES QT_RESOURCE_ALIAS controls/SShimmer.qml)
set_source_files_properties(ui/controls/SRipple.qml PROPERTIES QT_RESOURCE_ALIAS controls/SRipple.qml)
set_source_files_properties(ui/controls/SSwitch.qml PROPERTIES QT_RESOURCE_ALIAS controls/SSwitch.qml)
set_source_files_properties(ui/controls/SSegmented.qml PROPERTIES QT_RESOURCE_ALIAS controls/SSegmented.qml)
set_source_files_properties(ui/controls/SSelect.qml PROPERTIES QT_RESOURCE_ALIAS controls/SSelect.qml)
set_source_files_properties(ui/controls/SCard.qml PROPERTIES QT_RESOURCE_ALIAS controls/SCard.qml)
set_source_files_properties(ui/controls/SRow.qml PROPERTIES QT_RESOURCE_ALIAS controls/SRow.qml)
set_source_files_properties(ui/controls/STextArea.qml PROPERTIES QT_RESOURCE_ALIAS controls/STextArea.qml)
set_source_files_properties(ui/controls/SInput.qml PROPERTIES QT_RESOURCE_ALIAS controls/SInput.qml)
set_source_files_properties(ui/pages/ResourcePage.qml PROPERTIES QT_RESOURCE_ALIAS pages/ResourcePage.qml)
set_source_files_properties(ui/pages/JavaPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/JavaPage.qml)
set_source_files_properties(ui/pages/MultiplayerPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/MultiplayerPage.qml)
set_source_files_properties(ui/pages/VersionSettingsPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/VersionSettingsPage.qml)
set_source_files_properties(ui/pages/VsQuickPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsQuickPane.qml)
set_source_files_properties(ui/pages/VsPlaceholderPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsPlaceholderPane.qml)
set_source_files_properties(ui/pages/VsOverviewPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsOverviewPane.qml)
set_source_files_properties(ui/pages/VsLaunchPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsLaunchPane.qml)
set_source_files_properties(ui/pages/ResourceDetailPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/ResourceDetailPage.qml)
set_source_files_properties(ui/ToastHost.qml PROPERTIES QT_RESOURCE_ALIAS ToastHost.qml)
set_source_files_properties(ui/controls/SSlider.qml PROPERTIES QT_RESOURCE_ALIAS controls/SSlider.qml)
set_source_files_properties(ui/pages/VsMemoryPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsMemoryPane.qml)
set_source_files_properties(ui/pages/VsToolsPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsToolsPane.qml)
set_source_files_properties(ui/pages/VsModsPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsModsPane.qml)
set_source_files_properties(ui/pages/VsPacksPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsPacksPane.qml)
set_source_files_properties(ui/pages/VsSavesPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsSavesPane.qml)
set_source_files_properties(ui/pages/VsExportPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsExportPane.qml)
set_source_files_properties(ui/pages/VsShadersPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/VsShadersPane.qml)
set_source_files_properties(ui/controls/SDropZone.qml PROPERTIES QT_RESOURCE_ALIAS controls/SDropZone.qml)
set_source_files_properties(ui/controls/SetGroup.qml PROPERTIES QT_RESOURCE_ALIAS controls/SetGroup.qml)
set_source_files_properties(ui/controls/SetRow.qml PROPERTIES QT_RESOURCE_ALIAS controls/SetRow.qml)
set_source_files_properties(ui/controls/SetStack.qml PROPERTIES QT_RESOURCE_ALIAS controls/SetStack.qml)
set_source_files_properties(ui/controls/SetNote.qml PROPERTIES QT_RESOURCE_ALIAS controls/SetNote.qml)
set_source_files_properties(ui/pages/SettingsPage.qml PROPERTIES QT_RESOURCE_ALIAS pages/SettingsPage.qml)
set_source_files_properties(ui/pages/SetGeneralPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/SetGeneralPane.qml)
set_source_files_properties(ui/pages/SetJavaPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/SetJavaPane.qml)
set_source_files_properties(ui/pages/SetLaunchPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/SetLaunchPane.qml)
set_source_files_properties(ui/pages/SetDownloadPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/SetDownloadPane.qml)
set_source_files_properties(ui/pages/SetAdvancedPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/SetAdvancedPane.qml)
set_source_files_properties(ui/pages/SetAppearancePane.qml PROPERTIES QT_RESOURCE_ALIAS pages/SetAppearancePane.qml)
set_source_files_properties(ui/pages/SetAboutPane.qml PROPERTIES QT_RESOURCE_ALIAS pages/SetAboutPane.qml)

qt_add_qml_module(ShadowLauncher
    URI ShadowLauncher.Next
    VERSION 1.0
    RESOURCE_PREFIX "/qt/qml"
    NO_PLUGIN
    QML_FILES
        ui/Main.qml
        ui/Theme.qml
        ui/StageShell.qml
        ui/SideBar.qml
        ui/pages/StagePage.qml
        ui/pages/VersionPage.qml
        ui/pages/AccountPage.qml
        ui/pages/DownloadPage.qml
        ui/pages/ProgressPage.qml
        ui/LaunchOverlay.qml
        ui/AgreementGate.qml
        ui/controls/SIcon.qml
        ui/controls/SButton.qml
        ui/controls/SBgImage.qml
        ui/controls/SWindowButton.qml
        ui/controls/SAcctChip.qml
        ui/controls/SMinecraftHead.qml
        ui/controls/SLoadingBar.qml
        ui/controls/ResourceTile.qml
    ui/controls/SField.qml
    ui/controls/SShimmer.qml
    ui/controls/SRipple.qml
        ui/pages/ResourcePage.qml
        ui/pages/ResourceDetailPage.qml
        ui/pages/JavaPage.qml
        ui/pages/MultiplayerPage.qml
        ui/pages/VersionSettingsPage.qml
        ui/pages/VsQuickPane.qml
        ui/pages/VsPlaceholderPane.qml
        ui/pages/VsOverviewPane.qml
        ui/pages/VsLaunchPane.qml
        ui/ToastHost.qml
        ui/controls/SSwitch.qml
        ui/controls/SSegmented.qml
        ui/controls/SSelect.qml
        ui/controls/SCard.qml
        ui/controls/SRow.qml
        ui/controls/STextArea.qml
        ui/controls/SInput.qml
        ui/controls/SSlider.qml
        ui/pages/VsMemoryPane.qml
        ui/pages/VsToolsPane.qml
        ui/pages/VsModsPane.qml
        ui/pages/VsPacksPane.qml
  ui/pages/VsSavesPane.qml
  ui/pages/VsExportPane.qml
        ui/pages/VsShadersPane.qml
        ui/controls/SDropZone.qml
        ui/controls/SetGroup.qml
        ui/controls/SetRow.qml
        ui/controls/SetStack.qml
        ui/controls/SetNote.qml
        ui/pages/SettingsPage.qml
        ui/pages/SetGeneralPane.qml
        ui/pages/SetJavaPane.qml
        ui/pages/SetLaunchPane.qml
        ui/pages/SetDownloadPane.qml
        ui/pages/SetAdvancedPane.qml
        ui/pages/SetAppearancePane.qml
        ui/pages/SetAboutPane.qml
)

# UI 契约检查（构建期硬失败：版本号装饰 / emoji 图标 / SpringAnimation / pixelSize 小数 ...）
add_custom_target(UiContractCheck
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File "${CMAKE_SOURCE_DIR}/tools/check-ui-contract.ps1" -UiDir "${CMAKE_SOURCE_DIR}/ui"
    COMMENT "Checking ui/ contract"
    VERBATIM
)
add_dependencies(ShadowLauncher UiContractCheck)

# 启动页背景图（内置图库；用户仍可自定义 / 导入自己的图）
qt6_add_resources(ShadowLauncher "ui_stage_assets"
    PREFIX "/ui"
    BASE "ui/assets"
    FILES
        ui/assets/stage-aurora.jpg
        ui/assets/stage-fangcun.jpg
        ui/assets/stage-shanhe.jpg
        ui/assets/stage-linlan.jpg
        ui/assets/stage-weijian-2.jpg
        ui/assets/stage-weijian-4.jpg
        ui/assets/stage-weijian-6.jpg
        ui/assets/stage-jiguang.jpg
        ui/assets/stage-yuwen-1.jpg
        ui/assets/stage-yuwen-2.jpg
        ui/assets/stage-city-2.jpg
        ui/assets/stage-city-4.jpg
        ui/assets/stage-citywalk-6.jpg
        ui/assets/stage-jingmi.jpg
)

# 运行时数据（不属于任何 UI）：从旧 qml/ 目录迁出，路径见 src/backend/resource_backend.cpp
qt6_add_resources(ShadowLauncher "data_resources"
    PREFIX "/qt/qml/ShadowLauncher"
    FILES
        assets/data/mod_zh.json
        assets/data/mcmod_map.json
)
target_include_directories(ShadowLauncher PRIVATE src src/backend src/ui_next)

# ── Baked animation sprites (预烘焙帧动画) ──
# 进度步骤的 Google 不确定环：60 帧序列烘焙成一张网格图，QML 用 AnimatedSprite 播放。
# 渲染脚本：tools/bake_spin_sprite.py（改颜色/尺寸后重跑即可）
qt6_add_resources(ShadowLauncher "anim_resources"
    PREFIX "/qt/qml/ShadowLauncher/qml"
    FILES
        icons/anim/spin-f.png
)

# 鈹€鈹€ Lucide icon resources (must mirror dev-mode copy: icons copied into qml/icons/) 鈹€鈹€
qt6_add_resources(ShadowLauncher "icon_resources"
    PREFIX "/qt/qml/ShadowLauncher/qml"
    FILES
        icons/lucide/home.svg
        icons/lucide/download.svg
        icons/lucide/settings.svg
        icons/lucide/package.svg
        icons/lucide/x-circle.svg
        icons/lucide/minus.svg
        icons/lucide/x.svg
        icons/lucide/shield-check.svg
        icons/lucide/key.svg
        icons/lucide/lock.svg
        icons/lucide/user.svg
        icons/lucide/chevron-down.svg
        icons/lucide/chevron-up.svg
        icons/lucide/log-out.svg
        icons/lucide/play.svg
        icons/lucide/list.svg
        icons/lucide/wrench.svg
        icons/lucide/box.svg
        icons/lucide/puzzle.svg
        icons/lucide/sparkles.svg
        icons/lucide/palette.svg
        icons/lucide/check-circle.svg
        icons/lucide/flask-conical.svg
        icons/lucide/landmark.svg
        icons/lucide/refresh-cw.svg
        icons/lucide/globe.svg
        icons/lucide/search.svg
        icons/lucide/plug-zap.svg
        icons/lucide/gamepad-2.svg
        icons/lucide/folder-tree.svg
        icons/lucide/monitor.svg
        icons/lucide/scroll-text.svg
        icons/lucide/info.svg
        icons/lucide/tag.svg
        icons/lucide/shopping-cart.svg
        icons/lucide/zap.svg
        icons/lucide/ruler.svg
        icons/lucide/arrow-left.svg
        icons/lucide/hammer.svg
        icons/lucide/eye.svg
        icons/lucide/package-plus.svg
        icons/lucide/star.svg
        icons/lucide/pen.svg
        icons/lucide/alert-triangle.svg
        icons/lucide/terminal.svg
        icons/lucide/cpu.svg
        icons/lucide/door-open.svg
        icons/lucide/folder-open.svg
        icons/lucide/bot.svg
        icons/lucide/bar-chart-3.svg
        icons/lucide/layout-panel-top.svg
        icons/lucide/languages.svg
        icons/lucide/rotate-ccw.svg
        icons/lucide/folder.svg
        icons/lucide/folder-plus.svg
        icons/lucide/clipboard-list.svg
        icons/lucide/rocket.svg
        icons/lucide/map.svg
        icons/lucide/camera.svg
        icons/lucide/file-text.svg
        icons/lucide/file.svg
        icons/lucide/alert-octagon.svg
        icons/lucide/clipboard-copy.svg
        icons/lucide/folder-search.svg
        icons/lucide/trash-2.svg
        icons/lucide/broom.svg
        icons/lucide/file-search.svg
        icons/lucide/copy.svg
        icons/lucide/folder-sync.svg
        icons/lucide/skip-forward.svg
        icons/lucide/log-in.svg
        icons/lucide/check.svg
        icons/lucide/construction.svg
        icons/lucide/target.svg
        icons/lucide/sliders-horizontal.svg
        icons/lucide/image.svg
        icons/lucide/sun.svg
        icons/lucide/download-cloud.svg
        icons/lucide/external-link.svg
        icons/lucide/compass.svg
        icons/lucide/book-open.svg
        icons/lucide/users.svg
        icons/lucide/chevron-right.svg

        # ── Version type icons (Blocks) ──
        icons/blocks/Anvil.png
        icons/blocks/CobbleStone.png
        icons/blocks/CommandBlock.png
        icons/blocks/Egg.png
        icons/blocks/Fabric.png
        icons/blocks/GoldBlock.png
        icons/blocks/Grass.png
        icons/blocks/GrassPath.png
        icons/blocks/NeoForge.png
        icons/blocks/OptiFabric.png
        icons/blocks/RedstoneBlock.png
        icons/blocks/RedstoneLampOff.png
        icons/blocks/RedstoneLampOn.png

        # ── Release type icons ──
        icons/types/Alpha.png
        icons/types/Beta.png
        icons/types/Release.png

)

# 鈹€鈹€ Agreement HTML resources (embedded for offline access) 鈹€鈹€
# 必须用 QT_RESOURCE_ALIAS：否则 PREFIX + 文件相对路径会拼出
# agreements/assets/agreements/xxx.html（旧实现就是这样多带了一层 qml/agreements），
# 而 C++ 读的是 /qt/qml/ShadowLauncher/agreements/xxx.html。
set_source_files_properties(assets/agreements/beta_agreement.html PROPERTIES QT_RESOURCE_ALIAS beta_agreement.html)
set_source_files_properties(assets/agreements/terms_of_service.html PROPERTIES QT_RESOURCE_ALIAS terms_of_service.html)
set_source_files_properties(assets/agreements/privacy_policy.html PROPERTIES QT_RESOURCE_ALIAS privacy_policy.html)
qt6_add_resources(ShadowLauncher "agreement_resources"
    PREFIX "/qt/qml/ShadowLauncher/agreements"
    FILES
        assets/agreements/beta_agreement.html
        assets/agreements/terms_of_service.html
        assets/agreements/privacy_policy.html
)

# ── Bootstrap tools (embedded installer helper JARs) ──
qt6_add_resources(ShadowLauncher "tools_resources"
    PREFIX "/"
    FILES
        resources/tools/forge-installer.jar
        resources/tools/java-wrapper.jar
        resources/tools/ProGuardToTSRG.class
)

# Cape textures (Wardrobe)
# 同 agreements：PREFIX + 相对路径会拼成 resources/capes/resources/capes/x.png，
# 而 C++/QML 读的是 /qt/qml/ShadowLauncher/resources/capes/x.png → 必须给 alias。
file(GLOB SHADOW_CAPE_TEXTURES "${CMAKE_SOURCE_DIR}/resources/capes/*.png")
foreach(_cape ${SHADOW_CAPE_TEXTURES})
    get_filename_component(_cape_name "${_cape}" NAME)
    set_source_files_properties("resources/capes/${_cape_name}" PROPERTIES QT_RESOURCE_ALIAS "${_cape_name}")
endforeach()
qt6_add_resources(ShadowLauncher "cape_resources"
    PREFIX "/qt/qml/ShadowLauncher/resources/capes"
    FILES
        resources/capes/15th_anniversary.png
        resources/capes/builder.png
        resources/capes/cherry_blossom.png
        resources/capes/common.png
        resources/capes/copper.png
        resources/capes/followers.png
        resources/capes/founders.png
        resources/capes/home.png
        resources/capes/mcc_15th_year.png
        resources/capes/menace.png
        resources/capes/migrator.png
        resources/capes/minecon_2011.png
        resources/capes/minecon_2012.png
        resources/capes/minecon_2013.png
        resources/capes/minecon_2015.png
        resources/capes/minecon_2016.png
        resources/capes/minecraft_experience.png
        resources/capes/mojang.png
        resources/capes/mojang_studios.png
        resources/capes/pan.png
        resources/capes/purple_heart.png
        resources/capes/realms_mapmaker.png
        resources/capes/translator_chinese.png
        resources/capes/vanilla.png
        resources/capes/yearn.png
        resources/capes/zombie_horse.png
)


# 鈹€鈹€ Multi-language translations 鈹€鈹€
file(GLOB_RECURSE I18N_QML_SOURCES "${CMAKE_SOURCE_DIR}/ui/*.qml")
file(GLOB_RECURSE I18N_CPP_SOURCES "${CMAKE_SOURCE_DIR}/src/*.cpp" "${CMAKE_SOURCE_DIR}/src/*.h")
qt_add_translations(ShadowLauncher
    TS_FILES
        i18n/shadow_zh_CN.ts
        i18n/shadow_zh_HK.ts
        i18n/shadow_zh_TW.ts
        i18n/shadow_en.ts
    SOURCES
        ${I18N_QML_SOURCES}
        ${I18N_CPP_SOURCES}
    RESOURCE_PREFIX /i18n
)

# 鈹€鈹€ libwebp (static, for webp鈫扨NG icon decoding) 鈹€鈹€
set(WEBP_ROOT "${CMAKE_SOURCE_DIR}/thirdparty/libwebp")
target_include_directories(ShadowLauncher PRIVATE "${WEBP_ROOT}/include")
target_link_directories(ShadowLauncher PRIVATE "${WEBP_ROOT}/lib")

# 鈹€鈹€ miniz (public domain, ZIP 解压 — 整合包导入用) 鈹€鈹€
target_include_directories(ShadowLauncher PRIVATE "${CMAKE_SOURCE_DIR}/thirdparty/miniz")

# Define WEBP_STATIC_LINK for static lib (needed on Windows)
target_compile_definitions(ShadowLauncher PRIVATE
    WEBP_STATIC_LINK
    SHADOW_QT_VERSION="${Qt6_VERSION}"
    SHADOW_RESOURCE_EPOCH=1
)

# Beta gate 开关：ON 时定义 SHADOW_ENABLE_BETA_GATE=1（main_release 启用内测密钥闸门）
if(SHADOW_ENABLE_BETA_GATE)
    target_compile_definitions(ShadowLauncher PRIVATE SHADOW_ENABLE_BETA_GATE=1)
endif()

target_link_libraries(ShadowLauncher PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::GuiPrivate
    Qt6::CorePrivate
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickLayouts
    Qt6::Concurrent
    Qt6::Network
    Qt6::Widgets
    bcrypt
    nlohmann_json
    libwebp
    bcrypt
    crypt32
)

# cpr::cpr 鈥?added when libcurl is installed

# Windows: hide console window
if(WIN32)
    set_target_properties(ShadowLauncher PROPERTIES
        WIN32_EXECUTABLE TRUE
    )
    # Auto-deploy Qt DLLs after each build
    add_custom_command(TARGET ShadowLauncher POST_BUILD
        COMMAND "${CMAKE_PREFIX_PATH}/bin/windeployqt.exe"
            "$<TARGET_FILE:ShadowLauncher>"
            --qmldir "${CMAKE_SOURCE_DIR}/ui"
            --no-translations --no-compiler-runtime
        COMMENT "Deploying Qt runtime..."
    )
    add_custom_command(TARGET ShadowLauncher POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_SOURCE_DIR}/ui"
            "$<TARGET_FILE_DIR:ShadowLauncher>/ui"
        COMMENT "Copying next-generation QML sources..."
    )
    # Copy icon SVGs into qml dir for dev-mode (same relative path works in both modes)
    add_custom_command(TARGET ShadowLauncher POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_SOURCE_DIR}/icons"
            "$<TARGET_FILE_DIR:ShadowLauncher>/qml/icons"
        COMMENT "Copying icon SVGs for dev-mode..."
    )
    add_custom_command(TARGET ShadowLauncher POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_SOURCE_DIR}/assets/agreements"
            "$<TARGET_FILE_DIR:ShadowLauncher>/qml/agreements"
        COMMENT "Copying agreement HTMLs for dev-mode..."
    )
    # 联机隧道（EasyTier）：运行期按 applicationDirPath()/bin/easytier-core.exe 查找，缺它建房直接失败。
    # 二进制放 vendor/easytier/（2.6.4），构建后同步到 exe 旁的 bin/。
    add_custom_command(TARGET ShadowLauncher POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:ShadowLauncher>/bin"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_SOURCE_DIR}/vendor/easytier"
            "$<TARGET_FILE_DIR:ShadowLauncher>/bin"
        COMMENT "Copying EasyTier runtime into bin/..."
    )
endif()

option(SHADOW_BUILD_UI_NEXT_TESTS "Build next-generation UI foundation tests" OFF)
if(SHADOW_BUILD_UI_NEXT_TESTS)
    add_executable(UiNextAppearanceTest
        tests/test_appearance_controller.cpp
        src/ui_next/appearance_controller.cpp
        src/ui_next/appearance_controller.h
    )
    target_include_directories(UiNextAppearanceTest PRIVATE src)
    target_link_libraries(UiNextAppearanceTest PRIVATE Qt6::Core Qt6::Gui Qt6::Qml)
endif()

# ============================================================
# Modpack 模块自测（可选目标，不参与主程序构建）
#   cmake -S . -B build-test -DSHADOW_BUILD_MODPACK_SELFTEST=ON
# ============================================================
option(SHADOW_BUILD_MODPACK_SELFTEST "Build modpack self-test executable" OFF)

if(SHADOW_BUILD_MODPACK_SELFTEST)
    add_executable(ModpackSelfTest
        tests/test_modpack.cpp
        tests/test_zip_helper.cpp
        src/core/modpack/modpack_common.cpp
        src/core/modpack/zip_archive.cpp
        src/core/modpack/modpack_parser.cpp
        src/core/modpack/modpack_downloader.cpp
        src/core/modpack/mod_download_engine.cpp
        src/core/file_downloader.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
        thirdparty/miniz/miniz.c
    )
    target_include_directories(ModpackSelfTest PRIVATE src thirdparty/miniz)
    target_link_libraries(ModpackSelfTest PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent)

    # 精卫补位重试回归（2026-08-12）：每文件重试预算 + 任务层重试结果可见性
    # 用法：JingweiRetryTest.exe（本地 HTTP 服务器，无需外网）
    add_executable(JingweiRetryTest
        tests/test_jingwei_retry.cpp
        src/core/modpack/modpack_common.cpp
        src/core/modpack/modpack_downloader.cpp
        src/core/modpack/mod_download_engine.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
    )
    target_include_directories(JingweiRetryTest PRIVATE src)
    target_link_libraries(JingweiRetryTest PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent)

    # CF API Key 加密互操作测试（验证 Python 工具链生成的密文可被 C++ 解密）
    add_executable(CfCryptoInteropTest
        tests/test_cf_crypto_interop.cpp
    )
    target_include_directories(CfCryptoInteropTest PRIVATE src)
    target_link_libraries(CfCryptoInteropTest PRIVATE Qt6::Core bcrypt)

    # 驿道 v2 集成测试：实测分片下载（用法: YidaoTest <url> [expectedSize] [outPath]）
    add_executable(YidaoTest
        tests/test_yidao.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
    )
    target_include_directories(YidaoTest PRIVATE src)
    target_link_libraries(YidaoTest PRIVATE Qt6::Core Qt6::Network)

    # 夸父（FileDownloader）单文件下载测试
    add_executable(FDTest
        tests/test_fd.cpp
        src/core/file_downloader.cpp
        src/utils/logger.cpp
    )

    # 整合包导出测试（临时）：ModpackExportTest <gameDir> <versionId> [outPath]
    add_executable(ModpackExportTest
        tests/test_export.cpp
        src/core/modpack/modpack_exporter.cpp
        src/core/modpack/modpack_parser.cpp
        src/core/modpack/zip_archive.cpp
        src/core/modpack/modpack_common.cpp
        src/utils/logger.cpp
        thirdparty/miniz/miniz.c
    )
    target_include_directories(ModpackExportTest PRIVATE src thirdparty/miniz)
    target_link_libraries(ModpackExportTest PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent bcrypt)
    target_include_directories(FDTest PRIVATE src)
    target_link_libraries(FDTest PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent)

    # CF 适配器自测：搜索统一模型 + 文件→版本转换 + 分类表
    add_executable(CfApiTest
        tests/test_cf_api.cpp
        src/core/cf_api.cpp
        src/core/resource_fetch_engine.cpp
        src/utils/logger.cpp
    )
    target_include_directories(CfApiTest PRIVATE src "${WEBP_ROOT}/include")
    target_link_directories(CfApiTest PRIVATE "${WEBP_ROOT}/lib")
    target_compile_definitions(CfApiTest PRIVATE WEBP_STATIC_LINK)
    target_link_libraries(CfApiTest PRIVATE Qt6::Core Qt6::Network Qt6::Gui libwebp bcrypt)

    # 资源拉取引擎（司南）自测：搜索缓存命中 + 图标下载 + 缩略图生成
    add_executable(ResourceFetchEngineTest
        tests/test_resource_fetch_engine.cpp
        src/core/resource_fetch_engine.cpp
        src/utils/logger.cpp
    )
    target_include_directories(ResourceFetchEngineTest PRIVATE src "${WEBP_ROOT}/include")
    target_link_directories(ResourceFetchEngineTest PRIVATE "${WEBP_ROOT}/lib")
    target_compile_definitions(ResourceFetchEngineTest PRIVATE WEBP_STATIC_LINK)
    target_link_libraries(ResourceFetchEngineTest PRIVATE Qt6::Core Qt6::Network Qt6::Gui libwebp)

    # 图像解码诊断（webp 支持验证）
    add_executable(DiagImage tests/diag_image.cpp)
    target_include_directories(DiagImage PRIVATE "${WEBP_ROOT}/include")
    target_link_directories(DiagImage PRIVATE "${WEBP_ROOT}/lib")
    target_compile_definitions(DiagImage PRIVATE WEBP_STATIC_LINK)
    target_link_libraries(DiagImage PRIVATE Qt6::Gui Qt6::Core libwebp)

    # Forge 旧版安装集成测试（Legacy 2/3 统一路线）：真实网络跑 installForge
    add_executable(Forge147Test
        tests/test_forge147.cpp
        src/core/mod_loader_installer.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
    )
    target_include_directories(Forge147Test PRIVATE src)
    target_link_libraries(Forge147Test PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent Qt6::Gui Qt6::GuiPrivate)

    # 驿道下载 1.4.7 universal.zip（merged fallback 目标）完整性验证
    add_executable(Yidao147Test
        tests/test_yidao147.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
    )
    target_include_directories(Yidao147Test PRIVATE src)
    target_link_libraries(Yidao147Test PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent)

    # Mod 启禁用 + 启动脚本导出验证
    add_executable(ToggleScriptTest
        tests/test_toggle_script.cpp
        src/core/local_mod_manager.cpp
        src/core/launcher.cpp
        src/core/mc_language.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
    )
    target_include_directories(ToggleScriptTest PRIVATE src)
    target_link_libraries(ToggleScriptTest PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent Qt6::Gui Qt6::GuiPrivate)

    # 山海经 in-flight 挂起看门狗验证（2026-08-10）：挂起源 30s 无数据 → abort 换源 → 成功
    add_executable(AssetWatchdogTest
        tests/test_asset_watchdog.cpp
        src/core/asset_downloader.cpp
        src/utils/logger.cpp
    )
    target_include_directories(AssetWatchdogTest PRIVATE src)
    target_link_libraries(AssetWatchdogTest PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent)

    # 山海经完成兜底 + 同SHA1预检查 key 测试（2026-08-14：assets 卡 92% 修复验证）
    add_executable(AssetCompletionTest
        tests/test_asset_completion.cpp
        src/core/asset_downloader.cpp
        src/utils/logger.cpp
    )
    target_include_directories(AssetCompletionTest PRIVATE src)
    target_link_libraries(AssetCompletionTest PRIVATE Qt6::Core Qt6::Network Qt6::Concurrent)

    # 版本隔离 game 目录布局感知验证（散文件→版本根 / game非空→game）
    add_executable(IsoGdTest
        tests/test_isogd.cpp
        src/core/version_isolation.cpp
        src/utils/logger.cpp
    )
    target_include_directories(IsoGdTest PRIVATE src)
    target_link_libraries(IsoGdTest PRIVATE Qt6::Core)

    # 外部 .minecraft 布局识别/游戏目录解析验证（版本隔离/非隔离/混合/game子目录 +
    # 真实 PCL2/HMCL 目录探测，仅读取不写盘）
    add_executable(MinecraftLayoutTest
        tests/test_minecraft_layout.cpp
        src/core/minecraft_layout.cpp
        src/core/version_isolation.cpp
        src/utils/logger.cpp
    )
    target_include_directories(MinecraftLayoutTest PRIVATE src)
    target_link_libraries(MinecraftLayoutTest PRIVATE Qt6::Core)

    # 游戏文件夹注册表验证（命名文件/注册表/增删改/活动切换，异步刷新）
    add_executable(GameFolderTest
        tests/test_game_folder.cpp
        src/backend/minecraft_folder_backend.cpp
        src/core/minecraft_layout.cpp
        src/utils/logger.cpp
    )
    target_include_directories(GameFolderTest PRIVATE src)
    target_link_libraries(GameFolderTest PRIVATE Qt6::Core Qt6::Widgets Qt6::Concurrent)

    # 启动自动安装 Java 组件验证（真实网络 Tuna，worker 下载/解压 + 主线程回调）
    # 用法: JavaAutoInstallTest <major>（默认 8；已缓存直接完成）
    add_executable(JavaAutoInstallTest
        tests/test_java_autoinstall.cpp
        src/core/java_runtime_installer.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
    )
    target_include_directories(JavaAutoInstallTest PRIVATE src)
    target_link_libraries(JavaAutoInstallTest PRIVATE Qt6::Core Qt6::Network Qt6::Gui Qt6::GuiPrivate)

    # Java 需求规则验证（1.16.5-→8 / 1.17→16 / 1.18-1.20.4→17 / 1.20.5-1.21→21 / 22+→25）
    add_executable(JavaRulesTest
        tests/test_java_rules.cpp
        src/utils/logger.cpp
    )
    target_include_directories(JavaRulesTest PRIVATE src)
    target_link_libraries(JavaRulesTest PRIVATE Qt6::Core)

    # Java 自动安装取消语义验证（已缓存不误删 / 失败清理残留）
    add_executable(JavaCancelTest
        tests/test_java_cancel.cpp
        src/core/java_runtime_installer.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
    )
    target_include_directories(JavaCancelTest PRIVATE src)
    target_link_libraries(JavaCancelTest PRIVATE Qt6::Core Qt6::Network Qt6::Gui Qt6::GuiPrivate)

    # Java 列表扫描验证（MC 官方 runtime 路径可达性）
    add_executable(JavaScanTest
        tests/test_java_scan.cpp
        src/core/java_runtime_installer.cpp
        src/core/http_client.cpp
        src/utils/logger.cpp
    )
    target_include_directories(JavaScanTest PRIVATE src)
    target_link_libraries(JavaScanTest PRIVATE Qt6::Core Qt6::Network Qt6::Gui Qt6::GuiPrivate)

    # 启动细节工程验证（2026-08-08 低垂果实批）：GC 四档 / 全屏 / 自动进服新旧语法 /
    # 设置导入导出往返 / launcher_profiles 结构 / 脚本冒烟
    add_executable(LaunchDetailTest
        tests/test_launch_detail.cpp
        src/core/launcher.cpp
        src/core/mc_language.cpp
        src/backend/settings_backend.cpp
        src/core/version_isolation.cpp
        src/core/minecraft_layout.cpp
        src/utils/logger.cpp
    )
    target_include_directories(LaunchDetailTest PRIVATE src)
    target_link_libraries(LaunchDetailTest PRIVATE Qt6::Core Qt6::Network Qt6::Gui Qt6::Widgets Qt6::GuiPrivate)

    # NeoForge 1.20.6 log4j-slf4j 绑定去重测试（2026-08-14：启动崩溃 ResolutionException 修复验证）
    add_executable(Slf4jDedupTest
        tests/test_slf4j_dedup.cpp
        src/core/launcher.cpp
        src/core/mc_language.cpp
        src/utils/logger.cpp
    )
    target_include_directories(Slf4jDedupTest PRIVATE src)
    target_link_libraries(Slf4jDedupTest PRIVATE Qt6::Core Qt6::Network Qt6::Gui Qt6::Widgets Qt6::GuiPrivate)

    # 真实 1.20.6-neoforge JSON 验证（用户游戏目录，本地跑）
    add_executable(Slf4jRealTest
        tests/test_slf4j_real.cpp
        src/core/launcher.cpp
        src/core/mc_language.cpp
        src/utils/logger.cpp
    )
    target_include_directories(Slf4jRealTest PRIVATE src)
    target_link_libraries(Slf4jRealTest PRIVATE Qt6::Core Qt6::Network Qt6::Gui Qt6::Widgets Qt6::GuiPrivate)
endif()

# ============================================================
# Install
# ============================================================

install(TARGETS ShadowLauncher
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# ============================================================
# SLUpdater — standalone self-update helper (no Qt dependency)
# ============================================================
add_executable(SLUpdater
    update/SLUpdater.cpp
)
set_target_properties(SLUpdater PROPERTIES
    WIN32_EXECUTABLE TRUE
    AUTOMOC OFF
)
target_compile_options(SLUpdater PRIVATE /utf-8 /MT)
# ⚠ 2026-08-15：/MT 静态 CRT 必须！SLUpdater 若用动态 CRT(/MD) 会按 DLL 搜索
# 顺序从自身 exe 目录加载 msvcp140.dll（全量更新目录里恰好有）→ 进程自锁 →
# 覆盖复制该 DLL 恒报 error 32（实测 _update/sl_updater.log 8 次重试全失败）
target_link_libraries(SLUpdater PRIVATE
    shell32
    comctl32    # 2026-08-15：进度条控件 PROGRESS_CLASS
)

# ============================================================
# wv2login — Microsoft 内嵌登录助手（Edge WebView2，独立进程，无 Qt）
# ============================================================
# 为什么是独立进程：登录窗口崩溃/被杀不会带崩启动器；
# 启动器只用 QProcess 起它、等退出、读结果文件（见 src/core/microsoft_auth.cpp）。
#
# 2026-11-12：这个工程原本在旧仓库 cpp/thirdparty/wv2login（VS 工程 + NuGet 包 466MB），
# v2 建仓时按“体积垃圾”整个排除了，结果 v2 的内嵌登录成了永远找不到 exe 的死代码。
# 现在只把 src/ 4 个文件和最小 SDK 头/导入库搬进来（4.8MB），由 CMake 自己编。
set(WV2LOGIN_DIR "${CMAKE_SOURCE_DIR}/thirdparty/wv2login")

add_executable(wv2login WIN32
    ${WV2LOGIN_DIR}/src/App.cpp
    ${WV2LOGIN_DIR}/src/AppWindow.cpp
)
set_target_properties(wv2login PROPERTIES
    WIN32_EXECUTABLE TRUE
    AUTOMOC OFF
)
target_include_directories(wv2login PRIVATE
    "${WV2LOGIN_DIR}/src"
    "${WV2LOGIN_DIR}/sdk/WebView2"   # <WebView2.h> / <WebView2EnvironmentOptions.h>
    "${WV2LOGIN_DIR}/sdk"            # <wil/com.h> 等
)
target_compile_definitions(wv2login PRIVATE UNICODE _UNICODE)
# 旧 vcxproj 靠 <CharacterSet>Unicode</CharacterSet> 提供这两个宏；缺了 IDC_ARROW 会退化成
# MAKEINTRESOURCEA，LoadCursorW 直接编译不过。
target_compile_options(wv2login PRIVATE /utf-8 /MT)
# /MT 与 SLUpdater 同理：助手进程独立运行，静态 CRT 免得受 DLL 搜索顺序影响
target_link_libraries(wv2login PRIVATE
    "${WV2LOGIN_DIR}/sdk/lib/x64/WebView2Loader.dll.lib"
    ole32 oleaut32 uuid shell32 shlwapi user32 gdi32 advapi32 urlmon gdiplus comdlg32
)

# 助手 exe 与 WebView2Loader.dll 都必须和 ShadowLauncher.exe 同目录：
# microsoft_auth.cpp 按 applicationDirPath() + "/wv2login.exe" 找它。
add_custom_command(TARGET wv2login POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${WV2LOGIN_DIR}/sdk/lib/x64/WebView2Loader.dll"
        "$<TARGET_FILE_DIR:wv2login>/WebView2Loader.dll"
    COMMENT "Copying WebView2Loader.dll next to wv2login.exe"
)
