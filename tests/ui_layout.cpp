#include "layout_verification.h"

#include <QCoreApplication>
#include <QDebug>
#include <QEventLoop>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace {
constexpr auto Appearance = "superBoosterAppearanceShard";
constexpr auto Brand = "superBoosterBrandShard";
constexpr auto Commands = "superBoosterCommandShard";
constexpr auto Gain = "superBoosterGainShard";
constexpr auto Playback = "superBoosterPlaybackShard";
constexpr auto Effects = "superBoosterEffectsShard";
constexpr auto Meter = "superBoosterMeterShard";
constexpr auto Grip = "superBoosterResizeGrip";

void settleLayout() {
    QEventLoop events;
    QTimer::singleShot(70, &events, &QEventLoop::quit);
    events.exec();
}

QQuickItem* visualItem(QQuickItem* parent, QLatin1String name) {
    if (parent->objectName() == name) return parent;
    for (auto* child : parent->childItems()) {
        if (auto* match = visualItem(child, name)) return match;
    }
    return nullptr;
}

QRectF sceneBounds(QQuickItem* item) {
    return item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));
}

#ifdef Q_OS_WIN
bool acceptsNativeMouse(QQuickWindow* window, const QPointF& point) {
    if (QGuiApplication::platformName() != QLatin1String("windows")) return true;

    const auto hwnd = reinterpret_cast<HWND>(window->winId());
    const QPoint pixels = (point * window->devicePixelRatio()).toPoint();
    POINT screenPoint{pixels.x(), pixels.y()};
    RECT rect{};
    if (!ClientToScreen(hwnd, &screenPoint) || !GetWindowRect(hwnd, &rect)) return false;

    const HRGN region = CreateRectRgn(0, 0, 0, 0);
    if (!region) return false;
    const bool inside = GetWindowRgn(hwnd, region) != ERROR &&
        PtInRegion(region, screenPoint.x - rect.left, screenPoint.y - rect.top);
    DeleteObject(region);
    return inside && SendMessageW(hwnd, WM_NCHITTEST, 0, MAKELPARAM(screenPoint.x, screenPoint.y)) == HTCLIENT;
}
#endif

bool clickControl(QQuickWindow* window, const char* name, QQuickItem* hitItem = nullptr) {
    auto* control = visualItem(window->contentItem(), QLatin1String(name));
    if (!control || !control->isVisible() || !control->isEnabled()) {
        qWarning() << "Missing click target:" << name;
        return false;
    }
    const QPointF point = sceneBounds(hitItem ? hitItem : control).center();
#ifdef Q_OS_WIN
    if (!acceptsNativeMouse(window, point)) {
        qWarning() << "Windows intercepted the mouse at the control center:" << name << point;
        return false;
    }
#endif
    const QPointF global = window->mapToGlobal(point.toPoint());
    QMouseEvent press(QEvent::MouseButtonPress, point, point, global,
                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &press);
    QMouseEvent release(QEvent::MouseButtonRelease, point, point, global,
                        Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &release);
    settleLayout();
    return true;
}

bool verifyUpdateSettings(QQuickWindow* window) {
    window->resize(860, 550);
    settleLayout();
    if (!clickControl(window, "superBoosterMainMenu") ||
        !clickControl(window, "superBoosterAppearanceUpdateSettings")) {
        return false;
    }
    auto* viewport = visualItem(window->contentItem(), QLatin1String("superBoosterSettingsScroll"));
    auto* selector = visualItem(window->contentItem(), QLatin1String("superBoosterUpdateNotificationMode"));
    auto* details = window->findChild<QQuickWindow*>(QStringLiteral("superBoosterUpdateDetails"));
    const auto updateControlsInsideViewport = [&] {
        if (!viewport || !viewport->isVisible() || window->property("menuOpen").toBool()) return false;
        for (const auto name : {"superBoosterSettingsAutoInstallUpdates", "superBoosterUpdateNotificationMode",
                                "checkForSuperBoosterUpdates", "openSuperBoosterUpdateDetails"}) {
            auto* control = visualItem(window->contentItem(), QLatin1String(name));
            if (!control || !control->isVisible() ||
                !sceneBounds(viewport).adjusted(-0.5, -0.5, 0.5, 0.5).contains(sceneBounds(control))) {
                qWarning() << "Update settings left a control outside the scroll viewport:" << name
                           << sceneBounds(viewport) << (control ? sceneBounds(control) : QRectF{});
                return false;
            }
        }
        return true;
    };
    if (!updateControlsInsideViewport()) return false;

    if (selector && selector->isEnabled()) {
        auto* popup = selector->property("popup").value<QObject*>();
        auto* indicator = selector->property("indicator").value<QQuickItem*>();
        if (!popup || !indicator || !clickControl(window, "superBoosterUpdateNotificationMode", indicator) ||
            !popup->property("visible").toBool()) {
            qWarning() << "The notification selector must open on a mouse click.";
            return false;
        }
        QMetaObject::invokeMethod(popup, "close");
        settleLayout();
    }

    if (!details || !clickControl(window, "openSuperBoosterUpdateDetails") || !details->isVisible()) {
        qWarning() << "The Details button must open update details on a mouse click.";
        return false;
    }
    details->hide();
    window->setProperty("activeTab", 0);
    settleLayout();

    return clickControl(window, "superBoosterMainMenu") &&
        clickControl(window, "superBoosterAppearanceSettings") &&
        clickControl(window, "jumpToUpdateSettings") && updateControlsInsideViewport();
}

QList<QRectF> visibleSurfaces(QQuickWindow* window) {
    QList<QRectF> bounds;
    for (const auto name : {Brand, Commands, Gain, Playback, Effects, Meter, Grip}) {
        auto* item = visualItem(window->contentItem(), QLatin1String(name));
        if (!item || !item->isVisible()) {
            qWarning() << "Missing visible layout item:" << name;
            return {};
        }
        const QRectF box = sceneBounds(item);
        if (box.width() < 18 || box.height() < 18 || box.x() < -1 || box.y() < -1 ||
            box.right() > window->width() + 1 || box.bottom() > window->height() + 1) {
            qWarning() << "Out-of-bounds layout item:" << name << box << window->size();
            return {};
        }
        bounds.append(box);
    }
    if (bounds[0].height() > window->height() * 0.25 || bounds[2].height() < window->height() * 0.30) {
        qWarning() << "Header or boost panel consumed an unexpected portion of the window:" << bounds;
        return {};
    }
    return bounds;
}
}

int verifyMainLayout(QQuickWindow* window) {
    window->resize(1000, 615);
    window->show();
    settleLayout();
    auto* menu = visualItem(window->contentItem(), QLatin1String(Appearance));
    const auto closedBounds = visibleSurfaces(window);
    if (!menu || menu->isVisible() || window->property("menuOpen").toBool() || closedBounds.isEmpty()) {
        qWarning() << "The app must start with a complete layout and the menu closed.";
        return 1;
    }
    auto* updateNotice = window->findChild<QQuickWindow*>(QStringLiteral("superBoosterUpdateNotice"));
    if (!updateNotice) {
        qWarning() << "The update notice is missing.";
        return 1;
    }
    updateNotice->show();
    settleLayout();
    const QRectF workArea = updateNotice->property("workArea").toRectF();
    const int updateBottom = updateNotice->y() + updateNotice->height();
    if (!updateNotice->isVisible() || !window->screen() || updateNotice->screen() != window->screen() ||
        workArea != QRectF(window->screen()->availableGeometry()) ||
        !workArea.isValid() || updateNotice->y() < workArea.top() ||
        updateBottom > workArea.bottom() - 50 || updateNotice->x() < workArea.left() ||
        qAbs(workArea.right() - (updateNotice->x() + updateNotice->width()) - 16) > 1) {
        qWarning() << "The update notice must reserve space in the lower-right work area."
                   << updateNotice->geometry() << workArea;
        return 1;
    }
    updateNotice->hide();

    window->setProperty("menuOpen", true);
    settleLayout();
    if (!menu->isVisible() || menu->width() < 150 || menu->height() < 200 ||
        visibleSurfaces(window) != closedBounds) {
        qWarning() << "Opening the menu must reveal its pane without moving or resizing the other panes.";
        return 1;
    }

    window->setProperty("menuOpen", false);
    window->resize(1180, 700);
    settleLayout();
    const auto resizedBounds = visibleSurfaces(window);
    if (menu->isVisible() || resizedBounds.isEmpty() || resizedBounds[2].size() == closedBounds[2].size()) {
        qWarning() << "The closed-menu layout must adapt to the new window size.";
        return 1;
    }
    return verifyUpdateSettings(window) ? 0 : 1;
}
