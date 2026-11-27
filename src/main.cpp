#include "app_backend.h"
#include "updater.h"
#include "win_window_helper.h"

#include <QApplication>
#include <QDir>
#include <QSaveFile>
#include <QFileInfo>
#include <QIcon>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>

int main(int argc, char* argv[]) {
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QApplication app(argc, argv);
    QQuickWindow::setDefaultAlphaBuffer(true);
    app.setApplicationName(QStringLiteral("Super Booster"));
    app.setApplicationVersion(QStringLiteral(SUPER_BOOSTER_VERSION));
    app.setOrganizationName(QStringLiteral("SuperBooster"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/super-booster.ico")));

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
    Updater updater;
    QObject::connect(&updater, &Updater::installReady, &backend, &AppBackend::quitApp);
    QObject::connect(&updater, &Updater::nativeNotificationRequested, &backend, &AppBackend::notifyUpdate);
    QObject::connect(&backend, &AppBackend::updateNotificationClicked, &updater, &Updater::showDetailsRequested);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("updater"), &updater);
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
            winHelper.attachWindow(mainWindow, true);
            mainWindow->show();
            winHelper.placeBehindOtherWindows();

            QTimer::singleShot(850, mainWindow, [mainWindow, screenshotPath, &app]() {
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
            updater.start();
        }
    }

    return app.exec();
}
