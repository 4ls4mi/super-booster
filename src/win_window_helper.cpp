#include "win_window_helper.h"

#include <QCoreApplication>
#include <QFutureWatcher>
#include <QImageReader>
#include <QJSValue>
#include <QPainter>
#include <QPromise>
#include <QQuickWindow>
#include <QScreen>
#include <QScopeGuard>
#include <QThreadPool>
#include <QtMath>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>
#include <shobjidl.h>
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
constexpr DWORD DwmNoCorners = 1;             // DWMWCP_DONOTROUND
constexpr COLORREF DwmNoBorder = 0xfffffffe;  // DWMWA_COLOR_NONE

void removeDwmDecorations(HWND hwnd) {
    DwmSetWindowAttribute(hwnd, DwmCornerPreference, &DwmNoCorners, sizeof(DwmNoCorners));
    DwmSetWindowAttribute(hwnd, DwmBorderColor, &DwmNoBorder, sizeof(DwmNoBorder));
}

QRect fromNativeRect(const RECT& rect) {
    return QRect(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top);
}

struct WallpaperSettings {
    QString filename;
    COLORREF background = RGB(21, 23, 33);
    DESKTOP_WALLPAPER_POSITION position = DWPOS_FILL;
};

WallpaperSettings desktopWallpaperSettings(const QRect& monitor) {
    const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(com) && com != RPC_E_CHANGED_MODE) return {};
    const auto uninitialize = qScopeGuard([com] {
        if (SUCCEEDED(com)) CoUninitialize();
    });

    IDesktopWallpaper* wallpaper = nullptr;
    if (FAILED(CoCreateInstance(__uuidof(DesktopWallpaper), nullptr, CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER,
                                 __uuidof(IDesktopWallpaper), reinterpret_cast<void**>(&wallpaper)))) return {};
    const auto release = qScopeGuard([wallpaper] { wallpaper->Release(); });

    WallpaperSettings settings;
    wallpaper->GetBackgroundColor(&settings.background);
    wallpaper->GetPosition(&settings.position);
    UINT monitorCount = 0;
    if (FAILED(wallpaper->GetMonitorDevicePathCount(&monitorCount))) return {};
    for (UINT index = 0; index < monitorCount; ++index) {
        LPWSTR device = nullptr;
        if (FAILED(wallpaper->GetMonitorDevicePathAt(index, &device))) continue;
        const auto freeDevice = qScopeGuard([device] { CoTaskMemFree(device); });
        RECT nativeMonitor{};
        if (FAILED(wallpaper->GetMonitorRECT(device, &nativeMonitor))
                || fromNativeRect(nativeMonitor) != monitor) continue;

        LPWSTR path = nullptr;
        if (SUCCEEDED(wallpaper->GetWallpaper(device, &path)) && path) {
            settings.filename = QString::fromWCharArray(path);
        }
        CoTaskMemFree(path);
        break;
    }
    return settings;
}

QImage blurredWallpaperForMonitor(const QRect& monitor, bool primary) {
    if (monitor.isEmpty()) return {};

    WallpaperSettings settings = desktopWallpaperSettings(monitor);
    if (settings.filename.isEmpty() && primary) {
        // Some desktop sessions only expose the system-wide wallpaper setting.
        wchar_t filename[MAX_PATH]{};
        if (SystemParametersInfoW(SPI_GETDESKWALLPAPER, MAX_PATH, filename, 0)) {
            settings.filename = QString::fromWCharArray(filename);
        }
    }
    if (settings.filename.isEmpty()) return {};

    // Decode only the configured wallpaper file. The renderer never captures the desktop.
    // A small sample with smooth upscaling removes high-frequency detail.
    QImageReader reader(settings.filename);
    const QSize originalSize = reader.size();
    if (originalSize.isEmpty()) return {};
    const QSize decodedSize = originalSize.scaled(QSize(100, 100), Qt::KeepAspectRatio);
    reader.setScaledSize(decodedSize.expandedTo(QSize(1, 1)));
    const QImage source = reader.read();
    if (source.isNull()) return {};

    const QSize sampleSize = monitor.size().scaled(QSize(56, 56), Qt::KeepAspectRatio)
                                           .expandedTo(QSize(1, 1));
    QImage sample(sampleSize, QImage::Format_RGB32);
    sample.fill(QColor(GetRValue(settings.background), GetGValue(settings.background),
                       GetBValue(settings.background)));
    QPainter painter(&sample);
    painter.setRenderHint(QPainter::SmoothPixmapTransform);
    const qreal scaleX = qreal(sampleSize.width()) / monitor.width();
    const qreal scaleY = qreal(sampleSize.height()) / monitor.height();

    if (settings.position == DWPOS_TILE) {
        const QSize tileSize(qMax(1, qRound(originalSize.width() * scaleX)),
                             qMax(1, qRound(originalSize.height() * scaleY)));
        for (int y = 0; y < sample.height(); y += tileSize.height()) {
            for (int x = 0; x < sample.width(); x += tileSize.width()) {
                painter.drawImage(QRect(QPoint(x, y), tileSize), source);
            }
        }
    } else {
        const QRect layout = settings.position == DWPOS_SPAN
            ? QRect(GetSystemMetrics(SM_XVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN),
                    GetSystemMetrics(SM_CXVIRTUALSCREEN), GetSystemMetrics(SM_CYVIRTUALSCREEN))
            : monitor;
        QSize size = originalSize;
        if (settings.position == DWPOS_STRETCH) size = layout.size();
        if (settings.position == DWPOS_FIT) size.scale(layout.size(), Qt::KeepAspectRatio);
        if (settings.position == DWPOS_FILL || settings.position == DWPOS_SPAN) {
            size.scale(layout.size(), Qt::KeepAspectRatioByExpanding);
        }
        QRectF target{QPointF(), QSizeF(size)};
        target.moveCenter(QRectF(layout).center() - QPointF(monitor.topLeft()));
        painter.scale(scaleX, scaleY);
        painter.drawImage(target, source);
    }
    painter.end();
    return sample;
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
    m_wallpaperRefresh.setSingleShot(true);
    connect(&m_wallpaperRefresh, &QTimer::timeout, this, &WinWindowHelper::refreshWallpaper);
    m_gripResize.setSingleShot(true);
    m_gripResize.setTimerType(Qt::PreciseTimer);
    m_gripResize.setInterval(16);
    connect(&m_gripResize, &QTimer::timeout, this, &WinWindowHelper::applyGripSize);
}

WinWindowHelper::~WinWindowHelper() {
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
    m_gripResize.stop();
    m_window = window;
    m_hwnd = 0;
    m_inputRegionScale = 0;
    invalidateWallpaper();
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
        connect(m_window, &QWindow::screenChanged, this, [this] {
            syncInputRegion();
            invalidateWallpaper();
        });
        connect(m_window, &QObject::destroyed, this, [this] {
            m_hwnd = 0;
            m_hotkeysRegistered = false;
            invalidateWallpaper();
        });
        syncInputRegion();
    }
    if (m_wallpaperSamplingEnabled) m_wallpaperRefresh.start();
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

void WinWindowHelper::setShardGeometry(const QVariantList& polygons) {
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

    if (m_shardPolygons != shards) {
        m_shardPolygons = shards;
        m_inputRegionScale = 0;
    }
    syncInputRegion();
}

void WinWindowHelper::syncInputRegion() {
#ifdef Q_OS_WIN
    const auto main = reinterpret_cast<HWND>(m_hwnd);
    if (!main) return;
    const qreal scale = m_window->devicePixelRatio();
    if (m_inputRegionScale == scale) return;

    if (m_shardPolygons.isEmpty()) {
        if (SetWindowRgn(main, nullptr, TRUE)) m_inputRegionScale = scale;
        return;
    }
    HRGN region = shardRegion(m_shardPolygons, scale, qCeil(scale));
    if (!region) return;
    if (SetWindowRgn(main, region, TRUE)) {
        m_inputRegionScale = scale;
    } else {
        DeleteObject(region);
    }
#endif
}

void WinWindowHelper::setWallpaperSamplingEnabled(bool enabled) {
    if (m_wallpaperSamplingEnabled == enabled) return;
    m_wallpaperSamplingEnabled = enabled;
    emit wallpaperSamplingEnabledChanged();
    if (enabled && m_wallpaperDirty && m_hwnd) m_wallpaperRefresh.start();
}

void WinWindowHelper::invalidateWallpaper() {
    ++m_wallpaperRevision;
    m_wallpaperDirty = true;
    if (m_wallpaperSamplingEnabled && m_hwnd) m_wallpaperRefresh.start();
}

void WinWindowHelper::refreshWallpaper() {
#ifdef Q_OS_WIN
    if (!m_wallpaperSamplingEnabled || !m_wallpaperDirty || !m_window || !m_window->screen() || !m_hwnd)
        return;
    m_wallpaperDirty = false;
    const HWND window = reinterpret_cast<HWND>(m_hwnd);
    const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{sizeof(MONITORINFO)};
    const QRect geometry = m_window->screen()->geometry();
    if (m_wallpaperGeometry != geometry) {
        m_wallpaper = {};
        m_wallpaperGeometry = geometry;
        emit wallpaperChanged();
    }
    if (!GetMonitorInfoW(monitor, &info)) return;

    // Shell COM and image-file decoding can block. Keep the glass fallback visible
    // until the worker supplies the current monitor's sample.
    const auto revision = m_wallpaperRevision;
    auto* watcher = new QFutureWatcher<QImage>(this);
    connect(watcher, &QFutureWatcher<QImage>::finished, this, [this, watcher, revision] {
        const QImage wallpaper = watcher->result();
        watcher->deleteLater();
        if (revision != m_wallpaperRevision || m_wallpaper == wallpaper) return;
        m_wallpaper = wallpaper;
        emit wallpaperChanged();
    });
    QPromise<QImage> promise;
    promise.start();
    watcher->setFuture(promise.future());
    QThreadPool::globalInstance()->start([monitorBounds = fromNativeRect(info.rcMonitor),
                                          primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0,
                                          promise = std::move(promise)]() mutable {
        promise.addResult(blurredWallpaperForMonitor(monitorBounds, primary));
        promise.finish();
    });
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

void WinWindowHelper::resizeFromGrip(int width, int height) {
    if (!m_window || m_window->visibility() != QWindow::Windowed) return;
    m_gripSize = QSize(width, height);
    if (!m_gripResize.isActive()) m_gripResize.start();
}

void WinWindowHelper::applyGripSize() {
    if (!m_window || m_window->visibility() != QWindow::Windowed) return;
    m_window->resize(m_gripSize.boundedTo(m_window->maximumSize()).expandedTo(m_window->minimumSize()));
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

    if (msg->message == WM_DPICHANGED) {
        QTimer::singleShot(0, this, &WinWindowHelper::syncInputRegion);
        invalidateWallpaper();
    } else if (msg->message == WM_DISPLAYCHANGE
               || (msg->message == WM_SETTINGCHANGE && msg->wParam == SPI_SETDESKWALLPAPER)) {
        invalidateWallpaper();
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
