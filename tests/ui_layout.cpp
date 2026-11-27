#include "layout_verification.h"

#include <QDebug>
#include <QEventLoop>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>

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

QList<QRectF> visibleSurfaces(QQuickWindow* window) {
    QList<QRectF> bounds;
    for (const auto name : {Brand, Commands, Gain, Playback, Effects, Meter, Grip}) {
        auto* item = visualItem(window->contentItem(), QLatin1String(name));
        if (!item || !item->isVisible()) {
            qWarning() << "Missing visible layout item:" << name;
            return {};
        }
        const QRectF box = item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));
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
    return 0;
}
