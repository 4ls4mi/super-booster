#include "app_backend.h"
#include "updater.h"
#include "win_window_helper.h"
#ifdef SUPER_BOOSTER_TEST_LAYOUT
#include "../tests/layout_verification.h"
#endif

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
#include <QSize>
#include <QTimer>
#ifdef SUPER_BOOSTER_TEST_LAYOUT
#include <QTemporaryDir>
#include <optional>
#endif

int main(int argc, char* argv[]) {
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QApplication app(argc, argv);
    QQuickWindow::setDefaultAlphaBuffer(true);
    app.setApplicationName(QStringLiteral("Super Booster"));
    app.setApplicationVersion(QStringLiteral(SUPER_BOOSTER_VERSION));
    app.setOrganizationName(QStringLiteral("SuperBooster"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/super-booster.ico")));

    QString screenshotPath;
    QString screenshotLayout;
    QString screenshotMaterial;
    QSize screenshotSize;
    bool screenshotMenuOpen = false;
    bool startMinimized = false;
    QString verificationSettingsPath;
#ifdef SUPER_BOOSTER_TEST_LAYOUT
    const bool verifyLayout = app.arguments().contains(QStringLiteral("--verify-layout"));
    QString expectedStartupLayout;
    std::optional<QTemporaryDir> verificationSettingsDirectory;
#else
    constexpr bool verifyLayout = false;
#endif
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        if (args[i] == QLatin1String("--screenshot") && i + 1 < args.size()) {
            screenshotPath = args[++i];
        } else if (args[i].startsWith(QLatin1String("--screenshot="))) {
            screenshotPath = args[i].mid(13);
        } else if (args[i] == QLatin1String("--screenshot-menu")) {
            screenshotMenuOpen = true;
        } else if (args[i] == QLatin1String("--screenshot-layout") && i + 1 < args.size()) {
            screenshotLayout = args[++i];
            if (screenshotLayout != QLatin1String("glass") && screenshotLayout != QLatin1String("classic")) return 1;
        } else if (args[i] == QLatin1String("--screenshot-material") && i + 1 < args.size()) {
            screenshotMaterial = args[++i];
        } else if (args[i] == QLatin1String("--screenshot-size") && i + 1 < args.size()) {
            const QStringList dimensions = args[++i].split(QLatin1Char('x'));
            if (dimensions.size() != 2) return 1;
            screenshotSize = QSize(dimensions[0].toInt(), dimensions[1].toInt());
            if (screenshotSize.isEmpty() || screenshotSize.width() > 4096 || screenshotSize.height() > 4096) return 1;
        } else if (args[i] == QLatin1String("--minimized")) {
            startMinimized = true;
#ifdef SUPER_BOOSTER_TEST_LAYOUT
        } else if (verifyLayout && args[i] == QLatin1String("--verify-settings-file") && i + 1 < args.size()) {
            verificationSettingsPath = args[++i];
        } else if (verifyLayout && args[i] == QLatin1String("--verify-startup-layout") && i + 1 < args.size()) {
            expectedStartupLayout = args[++i];
#endif
        }
    }

#ifdef SUPER_BOOSTER_TEST_LAYOUT
    if (verifyLayout && verificationSettingsPath.isEmpty()) {
        verificationSettingsDirectory.emplace();
        if (!verificationSettingsDirectory->isValid()) return 1;
        verificationSettingsPath = verificationSettingsDirectory->filePath(QStringLiteral("booster_settings.json"));
    }
#endif

    const bool screenshotMode = !screenshotPath.isEmpty() || verifyLayout;
    app.setQuitOnLastWindowClosed(screenshotMode);

    WinWindowHelper winHelper;
    AppBackend backend(&winHelper, screenshotMode, nullptr, verificationSettingsPath);
    Updater updater;
    QObject::connect(&updater, &Updater::installReady, &backend, &AppBackend::quitApp);
    QObject::connect(&updater, &Updater::nativeNotificationRequested, &backend, &AppBackend::notifyUpdate);
    QObject::connect(&backend, &AppBackend::updateNotificationClicked, &updater, &Updater::showDetailsRequested);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("updater"), &updater);
    engine.rootContext()->setContextProperty(QStringLiteral("winHelper"), &winHelper);
    engine.rootContext()->setContextProperty(QStringLiteral("screenshotMode"), screenshotMode);
    engine.rootContext()->setContextProperty(QStringLiteral("screenshotMenuOpen"), screenshotMenuOpen);
    engine.rootContext()->setContextProperty(QStringLiteral("screenshotLayout"), screenshotMode ? screenshotLayout : QString());
    engine.rootContext()->setContextProperty(QStringLiteral("screenshotMaterial"), screenshotMaterial);
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
#ifdef SUPER_BOOSTER_TEST_LAYOUT
    if (verifyLayout) {
        if (!mainWindow) return 1;
        if (QGuiApplication::platformName() == QLatin1String("windows")) {
            winHelper.attachWindow(mainWindow, false);
        }
        return verifyMainLayout(mainWindow, verificationSettingsPath, expectedStartupLayout);
    }
#endif
    if (mainWindow) {
        if (screenshotMode) {
            mainWindow->setFlag(Qt::WindowDoesNotAcceptFocus, true);
            winHelper.attachWindow(mainWindow, true);
            mainWindow->show();
            winHelper.placeBehindOtherWindows();
            if (screenshotSize.isValid()) {
                QTimer::singleShot(150, mainWindow, [mainWindow, screenshotSize]() {
                    mainWindow->resize(screenshotSize);
                });
            }

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
