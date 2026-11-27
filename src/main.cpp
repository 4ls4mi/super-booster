#include "app_backend.h"
#include "win_window_helper.h"

#include <QApplication>
#include <QDir>
#include <QSaveFile>
#include <QFileInfo>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

int main(int argc, char* argv[]) {
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Super Booster"));
    app.setOrganizationName(QStringLiteral("SuperBooster"));

    QString screenshotPath;
    bool startMinimized = false;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args[i] == QLatin1String("--screenshot") && i + 1 < args.size()) {
            screenshotPath = args[++i];
        } else if (args[i].startsWith(QLatin1String("--screenshot="))) {
            screenshotPath = args[i].mid(13);
        } else if (args[i] == QLatin1String("--minimized")) {
            startMinimized = true;
        }
    }

    const bool screenshotMode = !screenshotPath.isEmpty();
    app.setQuitOnLastWindowClosed(screenshotMode);

    WinWindowHelper winHelper;
    AppBackend backend(&winHelper, screenshotMode);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("winHelper"), &winHelper);
    engine.rootContext()->setContextProperty(QStringLiteral("screenshotMode"), screenshotMode);
    engine.rootContext()->setContextProperty(QStringLiteral("startMinimized"), startMinimized);

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    engine.loadFromModule(QStringLiteral("SuperBoosterUI"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    auto* mainWindow = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
    QQuickWindow* popupWindow = mainWindow ? mainWindow->findChild<QQuickWindow*>(QStringLiteral("miniPopupWindow")) : nullptr;

    backend.setWindows(mainWindow, popupWindow);
    if (mainWindow) {
        if (screenshotMode) {
            mainWindow->setFlag(Qt::WindowDoesNotAcceptFocus, true);
#ifdef Q_OS_WIN
            mainWindow->create();
            winHelper.attachWindow(mainWindow, true);
            HWND hwnd = reinterpret_cast<HWND>(mainWindow->winId());
            if (hwnd) {
                ShowWindow(hwnd, SW_SHOWNOACTIVATE);
                SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0,
                             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
#else
            mainWindow->show();
            winHelper.attachWindow(mainWindow, true);
#endif

            auto* pump = new QTimer(mainWindow);
            pump->setInterval(16);
            QObject::connect(pump, &QTimer::timeout, mainWindow, [mainWindow, &winHelper]() {
                winHelper.placeBehindOtherWindows();
                mainWindow->requestUpdate();
            });
            pump->start();

            QTimer::singleShot(15000, &app, [&app]() { app.exit(1); });
            QObject::connect(mainWindow, &QQuickWindow::frameSwapped, mainWindow,
                [mainWindow, pump, frames = 0, screenshotPath, &app]() mutable {
                    if (++frames != 120) return;
                    pump->stop();

                    const QFileInfo output(screenshotPath);
                    QSaveFile file(screenshotPath);
                    const bool saved = output.dir().mkpath(QStringLiteral("."))
                        && file.open(QIODevice::WriteOnly)
                        && mainWindow->grabWindow().save(&file, "PNG")
                        && file.commit();
                    app.exit(saved ? 0 : 1);
                });
        } else {
            winHelper.attachWindow(mainWindow, false);
            if (!startMinimized) {
                mainWindow->show();
            }
        }
    }

    return app.exec();
}
