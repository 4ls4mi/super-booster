#include "win_window_helper.h"

#include <QCoreApplication>
#include <QQuickWindow>

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
}

WinWindowHelper::WinWindowHelper(QObject* parent) : QObject(parent) {
    QCoreApplication::instance()->installNativeEventFilter(this);
}

WinWindowHelper::~WinWindowHelper() {
    unregisterGlobalHotkeys();
    if (QCoreApplication::instance()) {
        QCoreApplication::instance()->removeNativeEventFilter(this);
    }
}

void WinWindowHelper::attachWindow(QQuickWindow* window, bool screenshotNoActivate) {
    m_window = window;
    m_hwnd = 0;
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
    }
#else
    Q_UNUSED(screenshotNoActivate)
#endif
}

void WinWindowHelper::applyDwmStyling(quintptr hwndPtr) {
#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(hwndPtr);
    if (!hwnd) return;

    // Enable Windows 11 rounded corners and subtle DWM frame shadow on frameless window
    const DWORD cornerPref = 2; // DWMWCP_ROUND
    DwmSetWindowAttribute(hwnd, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, &cornerPref, sizeof(cornerPref));

    const BOOL darkMode = TRUE;
    DwmSetWindowAttribute(hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &darkMode, sizeof(darkMode));

    const MARGINS margins{1, 1, 1, 1};
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
