#pragma once

#include <QAbstractNativeEventFilter>
#include <QObject>
#include <QPointer>
#include <QPolygonF>
#include <QVariant>

class QQuickWindow;

class WinWindowHelper : public QObject, public QAbstractNativeEventFilter {
    Q_OBJECT
    Q_PROPERTY(int titleBarHeight READ titleBarHeight WRITE setTitleBarHeight NOTIFY titleBarHeightChanged)
    Q_PROPERTY(int captionExcludeRight READ captionExcludeRight WRITE setCaptionExcludeRight NOTIFY captionExcludeRightChanged)

public:
    explicit WinWindowHelper(QObject* parent = nullptr);
    ~WinWindowHelper() override;

    void attachWindow(QQuickWindow* window, bool screenshotNoActivate);
    void setHotkeysEnabled(bool enabled);

    int titleBarHeight() const { return m_titleBarHeight; }
    void setTitleBarHeight(int h);

    int captionExcludeRight() const { return m_captionExcludeRight; }
    void setCaptionExcludeRight(int w);

    Q_INVOKABLE void startSystemMove();
    Q_INVOKABLE void startSystemResize(int edges);
    Q_INVOKABLE void minimizeWindow();
    Q_INVOKABLE void toggleMaximize();
    Q_INVOKABLE void placeBehindOtherWindows();
    Q_INVOKABLE void setShardGeometry(const QVariantList& polygons, const QString& material);

    static void setWindowsAutostart(bool enabled, const QString& appName, const QString& exePath);
    static bool isWindowsAutostartEnabled(const QString& appName);

    bool nativeEventFilter(const QByteArray& eventType, void* message, qintptr* result) override;

signals:
    void hotkeyVolumeUp();
    void hotkeyVolumeDown();
    void hotkeyToggleBoost();
    void titleBarHeightChanged();
    void captionExcludeRightChanged();

private:
    enum class Backdrop { None, Acrylic, Mica, Blur };

    void registerGlobalHotkeys();
    void unregisterGlobalHotkeys();
    void applyDwmStyling(quintptr hwnd);
    bool createBackdrop();
    void destroyBackdrop();
    void syncBackdrop();
    void syncInputRegion();

    QPointer<QQuickWindow> m_window;
    quintptr m_hwnd = 0;
    quintptr m_backdropHwnd = 0;
    QList<QPolygonF> m_shardPolygons;
    Backdrop m_backdrop = Backdrop::None;
    qreal m_backdropScale = 0;
    qreal m_inputRegionScale = 0;
    bool m_backdropUnavailable = false;
    bool m_hotkeysEnabled = true;
    bool m_hotkeysRegistered = false;
    int m_titleBarHeight = 44;
    int m_captionExcludeRight = 132;
};
