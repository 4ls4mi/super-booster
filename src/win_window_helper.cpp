#include "win_window_helper.h"

#include <QCoreApplication>
#include <QJSValue>
#include <QtMath>
#include <QQuickWindow>
#include <QTimer>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>
#endif

namespace {
constexpr int HOTKEY_VOL_UP = 0x5301;
constexpr int HOTKEY_VOL_DOWN = 0x5302;
constexpr int HOTKEY_TOGGLE = 0x5303;

#ifdef Q_OS_WIN
// The MinGW Windows SDK predates these DWM constants.
constexpr DWORD DwmDarkMode = 20;              // DWMWA_USE_IMMERSIVE_DARK_MODE
constexpr DWORD DwmCornerPreference = 33;      // DWMWA_WINDOW_CORNER_PREFERENCE
constexpr DWORD DwmBorderColor = 34;           // DWMWA_BORDER_COLOR
constexpr DWORD DwmSystemBackdrop = 38;       // DWMWA_SYSTEMBACKDROP_TYPE
constexpr DWORD DwmNoCorners = 1;             // DWMWCP_DONOTROUND
constexpr COLORREF DwmNoBorder = 0xfffffffe;  // DWMWA_COLOR_NONE
constexpr int MicaBackdrop = 2;               // DWMSBT_MAINWINDOW
constexpr int AcrylicBackdrop = 3;            // DWMSBT_TRANSIENTWINDOW
constexpr wchar_t BackdropClass[] = L"SuperBooster.ShardBackdrop";

void removeDwmDecorations(HWND hwnd) {
    DwmSetWindowAttribute(hwnd, DwmCornerPreference, &DwmNoCorners, sizeof(DwmNoCorners));
    DwmSetWindowAttribute(hwnd, DwmBorderColor, &DwmNoBorder, sizeof(DwmNoBorder));
}

LRESULT CALLBACK backdropWindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    default:
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }
}

bool registerBackdropClass() {
    WNDCLASSW windowClass{};
    windowClass.lpfnWndProc = backdropWindowProc;
    windowClass.hInstance = GetModuleHandleW(nullptr);
    windowClass.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    windowClass.lpszClassName = BackdropClass;
    return RegisterClassW(&windowClass) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

bool systemTransparencyEnabled() {
    BOOL composition = FALSE;
    if (FAILED(DwmIsCompositionEnabled(&composition)) || !composition) return false;

    HIGHCONTRASTW highContrast{sizeof(HIGHCONTRASTW), 0, nullptr};
    if (SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(highContrast), &highContrast, 0)
            && (highContrast.dwFlags & HCF_HIGHCONTRASTON)) {
        return false;
    }

    DWORD enabled = 1;
    DWORD size = sizeof(enabled);
    const auto preference = RegGetValueW(HKEY_CURRENT_USER,
        LR"(Software\Microsoft\Windows\CurrentVersion\Themes\Personalize)",
        L"EnableTransparency", RRF_RT_REG_DWORD, nullptr, &enabled, &size);
    return preference != ERROR_SUCCESS || enabled != 0;
}

bool applySystemBackdrop(HWND hwnd, int material) {
    const MARGINS wholeClient{-1, -1, -1, -1};
    return SUCCEEDED(DwmSetWindowAttribute(hwnd, DwmSystemBackdrop, &material, sizeof(material)))
        && SUCCEEDED(DwmExtendFrameIntoClientArea(hwnd, &wholeClient));
}

bool applyLegacyBlur(HWND hwnd, bool acrylic) {
    // The legacy accent policy is only used for classic blur and pre-22621 Windows.
    constexpr int AccentPolicyAttribute = 19;
    struct AccentPolicy { int state; int flags; DWORD color; int animation; };
    struct CompositionData { int attribute; void* data; UINT size; };
    using SetCompositionAttribute = BOOL (WINAPI*)(HWND, const CompositionData*);
    static const auto apply = reinterpret_cast<SetCompositionAttribute>(GetProcAddress(
        GetModuleHandleW(L"user32.dll"), "SetWindowCompositionAttribute"));
    if (!apply) return false;

    constexpr int AccentBlur = 3;
    constexpr int AccentAcrylic = 4;
    AccentPolicy policy{acrylic ? AccentAcrylic : AccentBlur, 0, acrylic ? 0x48251a10UL : 0UL, 0};
    const CompositionData composition{AccentPolicyAttribute, &policy, sizeof(policy)};
    return apply(hwnd, &composition);
}

HRGN shardRegion(const QList<QPolygonF>& shards, qreal scale, int fringe = 0) {
    HRGN combined = CreateRectRgn(0, 0, 0, 0);
    if (!combined) return nullptr;
    for (const auto& shard : shards) {
        QList<POINT> points;
        points.reserve(shard.size());
        for (const auto& point : shard) {
            points.append(POINT{qRound(point.x() * scale), qRound(point.y() * scale)});
        }
        HRGN polygon = CreatePolygonRgn(points.constData(), static_cast<int>(points.size()), WINDING);
        const bool valid = polygon && CombineRgn(combined, combined, polygon, RGN_OR) != ERROR;
        if (polygon) DeleteObject(polygon);
        if (!valid) {
            DeleteObject(combined);
            return nullptr;
        }
    }

    // Preserve the antialiased Qt outline while making the desktop gaps click-through.
    if (fringe) {
        HRGN outline = CreateRectRgn(0, 0, 0, 0);
        if (outline) {
            CombineRgn(outline, combined, nullptr, RGN_COPY);
            OffsetRgn(outline, -fringe, 0);
            CombineRgn(combined, combined, outline, RGN_OR);
            OffsetRgn(outline, fringe * 2, 0);
            CombineRgn(combined, combined, outline, RGN_OR);
            OffsetRgn(outline, -fringe, -fringe);
            CombineRgn(combined, combined, outline, RGN_OR);
            OffsetRgn(outline, 0, fringe * 2);
            CombineRgn(combined, combined, outline, RGN_OR);
            DeleteObject(outline);
        }
    }
    return combined;
}
#endif
}

WinWindowHelper::WinWindowHelper(QObject* parent) : QObject(parent) {
    QCoreApplication::instance()->installNativeEventFilter(this);
}

WinWindowHelper::~WinWindowHelper() {
    destroyBackdrop();
    unregisterGlobalHotkeys();
    if (QCoreApplication::instance()) {
        QCoreApplication::instance()->removeNativeEventFilter(this);
    }
}

void WinWindowHelper::attachWindow(QQuickWindow* window, bool screenshotNoActivate) {
    if (m_window) {
        unregisterGlobalHotkeys();
        disconnect(m_window, nullptr, this, nullptr);
    }
    destroyBackdrop();
    m_window = window;
    m_hwnd = 0;
    m_backdropUnavailable = false;
    m_inputRegionScale = 0;
    if (!m_window) {
        return;
    }

#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
    if (hwnd) {
        m_hwnd = reinterpret_cast<quintptr>(hwnd);
        applyDwmStyling(m_hwnd);
        if (screenshotNoActivate) {
            LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE);
            SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
        if (m_hotkeysEnabled) {
            registerGlobalHotkeys();
        }
        connect(m_window, &QWindow::visibilityChanged, this, [this] { syncBackdrop(); });
        connect(m_window, &QWindow::screenChanged, this, [this] {
            syncInputRegion();
            syncBackdrop();
        });
        connect(m_window, &QObject::destroyed, this, [this] {
            m_hwnd = 0;
            m_hotkeysRegistered = false;
            destroyBackdrop();
        });
        syncInputRegion();
        syncBackdrop();
    }
#else
    Q_UNUSED(screenshotNoActivate)
#endif
}

void WinWindowHelper::applyDwmStyling(quintptr hwndPtr) {
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(hwndPtr);
    if (!hwnd) return;

    // The transparent Qt window has no rectangular frame or system backdrop.
    removeDwmDecorations(hwnd);
    const BOOL darkMode = TRUE;
    DwmSetWindowAttribute(hwnd, DwmDarkMode, &darkMode, sizeof(darkMode));
    const DWMNCRENDERINGPOLICY noFrame = DWMNCRP_DISABLED;
    DwmSetWindowAttribute(hwnd, DWMWA_NCRENDERING_POLICY, &noFrame, sizeof(noFrame));
    const MARGINS margins{0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(hwnd, &margins);

    // Ensure WS_THICKFRAME is present so Win32 edge resize + Aero Snap work smoothly
    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    style |= WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
    SetWindowLongPtrW(hwnd, GWL_STYLE, style);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
#else
    Q_UNUSED(hwndPtr)
#endif
}

void WinWindowHelper::setShardGeometry(const QVariantList& polygons, const QString& material) {
    QList<QPolygonF> shards;
    for (auto value : polygons) {
        if (value.metaType().id() == qMetaTypeId<QJSValue>()) {
            value = value.value<QJSValue>().toVariant();
        }
        QPolygonF polygon;
        for (const auto& vertex : value.toList()) {
            if (!vertex.canConvert<QPointF>()) continue;
            const auto point = vertex.toPointF();
            if (qIsFinite(point.x()) && qIsFinite(point.y())) polygon.append(point);
        }
        if (polygon.size() >= 3) shards.append(polygon);
    }

    Backdrop next = Backdrop::None;
    const auto name = material.toLower();
    if (name == QLatin1String("acrylic") || name == QLatin1String("frosted")) {
        next = Backdrop::Acrylic;
    } else if (name == QLatin1String("mica")) {
        next = Backdrop::Mica;
    } else if (name == QLatin1String("blurred")) {
        next = Backdrop::Blur;
    }

    if (m_backdrop != next) {
        destroyBackdrop();
        m_backdrop = next;
        m_backdropUnavailable = false;
    }
    if (m_shardPolygons != shards) {
        m_shardPolygons = shards;
        m_backdropScale = 0;
        m_inputRegionScale = 0;
    }
    syncInputRegion();
    syncBackdrop();
}

void WinWindowHelper::syncInputRegion() {
#ifdef Q_OS_WIN
    const auto main = reinterpret_cast<HWND>(m_hwnd);
    if (!main || m_shardPolygons.isEmpty()) return;
    const qreal scale = m_window->devicePixelRatio();
    if (m_inputRegionScale == scale) return;

    HRGN region = shardRegion(m_shardPolygons, scale, qCeil(1.5 * scale));
    if (!region) return;
    if (SetWindowRgn(main, region, TRUE)) {
        m_inputRegionScale = scale;
    } else {
        DeleteObject(region);
    }
#endif
}

bool WinWindowHelper::createBackdrop() {
#ifdef Q_OS_WIN
    if (!systemTransparencyEnabled() || !registerBackdropClass()) return false;

    const auto instance = GetModuleHandleW(nullptr);
    HWND backdrop = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT,
        BackdropClass, L"", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, instance, nullptr);
    if (!backdrop) return false;

    m_backdropHwnd = reinterpret_cast<quintptr>(backdrop);
    removeDwmDecorations(backdrop);
    const BOOL darkMode = TRUE;
    DwmSetWindowAttribute(backdrop, DwmDarkMode, &darkMode, sizeof(darkMode));
    DwmSetWindowAttribute(backdrop, DWMWA_EXCLUDED_FROM_PEEK, &darkMode, sizeof(darkMode));

    bool applied = false;
    if (m_backdrop == Backdrop::Mica) {
        applied = applySystemBackdrop(backdrop, MicaBackdrop);
    } else if (m_backdrop == Backdrop::Acrylic) {
        applied = applySystemBackdrop(backdrop, AcrylicBackdrop) || applyLegacyBlur(backdrop, true);
    } else if (m_backdrop == Backdrop::Blur) {
        applied = applyLegacyBlur(backdrop, false) || applySystemBackdrop(backdrop, AcrylicBackdrop);
    }
    if (!applied) destroyBackdrop();
    return applied;
#else
    return false;
#endif
}

void WinWindowHelper::destroyBackdrop() {
#ifdef Q_OS_WIN
    if (m_backdropHwnd) DestroyWindow(reinterpret_cast<HWND>(m_backdropHwnd));
#endif
    m_backdropHwnd = 0;
    m_backdropScale = 0;
}

void WinWindowHelper::syncBackdrop() {
#ifdef Q_OS_WIN
    const auto main = reinterpret_cast<HWND>(m_hwnd);
    if (!main || m_backdrop == Backdrop::None || m_shardPolygons.isEmpty()
            || !IsWindowVisible(main) || IsIconic(main)) {
        if (m_backdropHwnd) ShowWindow(reinterpret_cast<HWND>(m_backdropHwnd), SW_HIDE);
        return;
    }
    if (m_backdropUnavailable) return;
    if (!m_backdropHwnd && !createBackdrop()) {
        m_backdropUnavailable = true;
        return;
    }

    const auto backdrop = reinterpret_cast<HWND>(m_backdropHwnd);
    const qreal scale = m_window->devicePixelRatio();
    if (m_backdropScale != scale) {
        HRGN region = shardRegion(m_shardPolygons, scale);
        if (!region || !SetWindowRgn(backdrop, region, TRUE)) {
            if (region) DeleteObject(region);
            destroyBackdrop();
            return;
        }
        // Windows owns the region after a successful SetWindowRgn.
        m_backdropScale = scale;
    }

    POINT origin{};
    RECT client{};
    if (ClientToScreen(main, &origin) && GetClientRect(main, &client)) {
        SetWindowPos(backdrop, main, origin.x, origin.y, client.right, client.bottom,
                     SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOOWNERZORDER);
    }
#endif
}

void WinWindowHelper::placeBehindOtherWindows() {
#ifdef Q_OS_WIN
    if (!m_window) return;
    HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
    if (hwnd) {
        SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
#endif
}

void WinWindowHelper::setHotkeysEnabled(bool enabled) {
    if (m_hotkeysEnabled == enabled) return;
    m_hotkeysEnabled = enabled;
    if (enabled) {
        registerGlobalHotkeys();
    } else {
        unregisterGlobalHotkeys();
    }
}

void WinWindowHelper::registerGlobalHotkeys() {
#ifdef Q_OS_WIN
    if (m_hotkeysRegistered || !m_window) return;
    HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
    if (!hwnd) return;

    RegisterHotKey(hwnd, HOTKEY_VOL_UP, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_UP);
    RegisterHotKey(hwnd, HOTKEY_VOL_DOWN, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_DOWN);
    RegisterHotKey(hwnd, HOTKEY_TOGGLE, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'B');
    m_hotkeysRegistered = true;
#endif
}

void WinWindowHelper::unregisterGlobalHotkeys() {
#ifdef Q_OS_WIN
    if (!m_hotkeysRegistered || !m_window) return;
    HWND hwnd = reinterpret_cast<HWND>(m_window->winId());
    if (hwnd) {
        UnregisterHotKey(hwnd, HOTKEY_VOL_UP);
        UnregisterHotKey(hwnd, HOTKEY_VOL_DOWN);
        UnregisterHotKey(hwnd, HOTKEY_TOGGLE);
    }
    m_hotkeysRegistered = false;
#endif
}

void WinWindowHelper::setTitleBarHeight(int h) {
    if (m_titleBarHeight == h) return;
    m_titleBarHeight = h;
    emit titleBarHeightChanged();
}

void WinWindowHelper::setCaptionExcludeRight(int w) {
    if (m_captionExcludeRight == w) return;
    m_captionExcludeRight = w;
    emit captionExcludeRightChanged();
}

void WinWindowHelper::startSystemMove() {
    if (m_window) {
        m_window->startSystemMove();
    }
}

void WinWindowHelper::startSystemResize(int edges) {
    if (m_window) {
        m_window->startSystemResize(static_cast<Qt::Edges>(edges));
    }
}

void WinWindowHelper::minimizeWindow() {
    if (m_window) {
        m_window->showMinimized();
    }
}

void WinWindowHelper::toggleMaximize() {
    if (!m_window) return;
    if (m_window->visibility() == QWindow::Maximized) {
        m_window->showNormal();
    } else {
        m_window->showMaximized();
    }
}

bool WinWindowHelper::nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result) {
#ifdef Q_OS_WIN
    if (eventType != "windows_generic_MSG" && eventType != "windows_dispatcher_MSG") {
        return false;
    }
    MSG* msg = static_cast<MSG*>(message);
    if (!msg) return false;

    if (msg->message == WM_HOTKEY) {
        if (msg->wParam == HOTKEY_VOL_UP) {
            emit hotkeyVolumeUp();
            return true;
        } else if (msg->wParam == HOTKEY_VOL_DOWN) {
            emit hotkeyVolumeDown();
            return true;
        } else if (msg->wParam == HOTKEY_TOGGLE) {
            emit hotkeyToggleBoost();
            return true;
        }
    }

    if (!m_window || !m_hwnd || msg->hwnd != reinterpret_cast<HWND>(m_hwnd)) {
        return false;
    }

    if (msg->message == WM_WINDOWPOSCHANGED) {
        syncBackdrop();
    } else if (msg->message == WM_DPICHANGED) {
        QTimer::singleShot(0, this, [this] {
            syncInputRegion();
            syncBackdrop();
        });
    } else if (m_backdrop != Backdrop::None && (msg->message == WM_DWMCOMPOSITIONCHANGED
               || msg->message == WM_SETTINGCHANGE || msg->message == WM_THEMECHANGED)) {
        QTimer::singleShot(0, this, [this] {
            destroyBackdrop();
            m_backdropUnavailable = false;
            syncBackdrop();
        });
    }

    if (msg->message == WM_NCCALCSIZE && msg->wParam == TRUE) {
        // Keep a clean borderless client area while preserving WS_THICKFRAME snapping
        *result = 0;
        return true;
    }

    if (msg->message == WM_NCHITTEST) {
        RECT rect{};
        GetWindowRect(msg->hwnd, &rect);
        const int x = GET_X_LPARAM(msg->lParam);
        const int y = GET_Y_LPARAM(msg->lParam);
        const qreal dpr = m_window->devicePixelRatio();
        const int border = static_cast<int>(8 * dpr);

        const bool left = x >= rect.left && x < rect.left + border;
        const bool right = x < rect.right && x >= rect.right - border;
        const bool top = y >= rect.top && y < rect.top + border;
        const bool bottom = y < rect.bottom && y >= rect.bottom - border;

        if (top && left) { *result = HTTOPLEFT; return true; }
        if (top && right) { *result = HTTOPRIGHT; return true; }
        if (bottom && left) { *result = HTBOTTOMLEFT; return true; }
        if (bottom && right) { *result = HTBOTTOMRIGHT; return true; }
        if (left) { *result = HTLEFT; return true; }
        if (right) { *result = HTRIGHT; return true; }
        if (top) { *result = HTTOP; return true; }
        if (bottom) { *result = HTBOTTOM; return true; }

        const int titlePx = static_cast<int>(m_titleBarHeight * dpr);
        const int exclPx = static_cast<int>(m_captionExcludeRight * dpr);
        if (y >= rect.top && y < rect.top + titlePx && x < rect.right - exclPx) {
            *result = HTCAPTION;
            return true;
        }
    }
#else
    Q_UNUSED(eventType)
    Q_UNUSED(message)
    Q_UNUSED(result)
#endif
    return false;
}

void WinWindowHelper::setWindowsAutostart(bool enabled, const QString& appName, const QString& exePath) {
#ifdef Q_OS_WIN
    const wchar_t* keyPath = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, keyPath, 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
        const std::wstring nameW = appName.toStdWString();
        if (enabled) {
            const std::wstring cmd = L"\"" + exePath.toStdWString() + L"\" --minimized";
            RegSetValueExW(key, nameW.c_str(), 0, REG_SZ,
                           reinterpret_cast<const BYTE*>(cmd.c_str()),
                           static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t)));
        } else {
            RegDeleteValueW(key, nameW.c_str());
        }
        RegCloseKey(key);
    }
#else
    Q_UNUSED(enabled)
    Q_UNUSED(appName)
    Q_UNUSED(exePath)
#endif
}

bool WinWindowHelper::isWindowsAutostartEnabled(const QString& appName) {
#ifdef Q_OS_WIN
    const wchar_t* keyPath = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
    HKEY key = nullptr;
    bool exists = false;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, keyPath, 0, KEY_QUERY_VALUE, &key) == ERROR_SUCCESS) {
        const std::wstring nameW = appName.toStdWString();
        if (RegQueryValueExW(key, nameW.c_str(), nullptr, nullptr, nullptr, nullptr) == ERROR_SUCCESS) {
            exists = true;
        }
        RegCloseKey(key);
    }
    return exists;
#else
    Q_UNUSED(appName)
    return false;
#endif
}
