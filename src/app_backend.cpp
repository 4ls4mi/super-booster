#include "app_backend.h"
#include "audio_ffi.h"
#include "win_window_helper.h"

#include <QAction>
#include <QCoreApplication>
#include <QCursor>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QPolygonF>
#include <QQuickWindow>
#include <QScreen>
#include <QSystemTrayIcon>
#include <QtMath>
#include <algorithm>
#include <cmath>

namespace {
constexpr const char* APP_REG_NAME = "SuperBoosterAudio";
constexpr int SPECTRUM_COUNT = 24;
constexpr auto DIGITAL_SOURCE = "windows-digital";
constexpr float AUDIBLE_PEAK = 0.0001f;
constexpr int DIGITAL_HANDOFF_TIMEOUT_MS = 2500;
}

AppBackend::AppBackend(WinWindowHelper* winHelper, bool screenshotMode, QObject* parent)
    : QObject(parent), m_winHelper(winHelper), m_screenshotMode(screenshotMode),
      m_windowsRoute(QDir(QCoreApplication::applicationDirPath()).filePath("booster_audio_route.json")) {
    sb_init();
    m_spectrum.reserve(SPECTRUM_COUNT);
    for (int i = 0; i < SPECTRUM_COUNT; ++i) {
        m_spectrum.append(0.0);
    }

    loadSettings();
    const bool recoveredRoute = !m_screenshotMode && m_windowsRoute.recover();
    const bool resumeBoost = m_engineActive && !recoveredRoute;
    m_engineActive = false;
    refreshDevices();
    refreshSessions();
    m_masterVolume = std::round(static_cast<double>(sb_get_master_volume(nullptr)) * 100.0);

    if (m_directMode) m_volume = std::max(100.0, m_volume);
    sb_set_gain_percent(static_cast<float>(m_volume));
    sb_set_super_boost(m_superBoost);
    sb_set_limiter(m_limiterEnabled);
    sb_set_bass_boost(static_cast<float>(m_bassBoost));

    if (!m_screenshotMode && resumeBoost) {
        startEngine();
    } else {
        m_statusMessage = m_directMode
            ? QStringLiteral("Ready — System Audio Boost")
            : QStringLiteral("Ready — Device Routing Mode");
    }

    if (m_winHelper) {
        m_winHelper->setHotkeysEnabled(!m_screenshotMode && m_hotkeysEnabled);
        connect(m_winHelper, &WinWindowHelper::hotkeyVolumeUp, this, [this]() {
            setVolume(std::min(500.0, m_volume + 5.0));
        });
        connect(m_winHelper, &WinWindowHelper::hotkeyVolumeDown, this, [this]() {
            setVolume(std::max(0.0, m_volume - 5.0));
        });
        connect(m_winHelper, &WinWindowHelper::hotkeyToggleBoost, this, &AppBackend::toggleEngine);
    }

    if (!m_screenshotMode) {
        setupTray();
    }

    m_meterTimer.setInterval(33);
    connect(&m_meterTimer, &QTimer::timeout, this, &AppBackend::pollMeters);
    m_meterTimer.start();

    m_sessionTimer.setInterval(1200);
    connect(&m_sessionTimer, &QTimer::timeout, this, &AppBackend::pollSessions);
    m_sessionTimer.start();

    m_saveDebounce.setSingleShot(true);
    m_saveDebounce.setInterval(350);
    connect(&m_saveDebounce, &QTimer::timeout, this, &AppBackend::saveSettings);
}

AppBackend::~AppBackend() {
    if (!m_screenshotMode) {
        saveSettings();
    }
    m_windowsRoute.stop();
    sb_shutdown();
}

void AppBackend::setWindows(QQuickWindow* mainWindow, QQuickWindow* popupWindow) {
    m_mainWindow = mainWindow;
    m_popupWindow = popupWindow;

    if (m_mainWindow && m_winW >= 540 && m_winH >= 400) {
        m_mainWindow->resize(m_winW, m_winH);
        if (m_winX >= 0 && m_winY >= 0) {
            m_mainWindow->setPosition(m_winX, m_winY);
        }
    }
}

QString AppBackend::settingsFilePath() const {
    return QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("booster_settings.json"));
}

void AppBackend::loadSettings() {
    m_autostart = WinWindowHelper::isWindowsAutostartEnabled(QString::fromLatin1(APP_REG_NAME));

    QFile f(settingsFilePath());
    if (!f.open(QIODevice::ReadOnly)) {
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject()) return;
    const QJsonObject obj = doc.object();

    if (obj.contains("volume")) m_volume = std::clamp(obj.value("volume").toDouble(100.0), 0.0, 500.0);
    if (obj.contains("engine_active")) m_engineActive = obj.value("engine_active").toBool(false);
    if (obj.contains("direct_mode")) m_directMode = obj.value("direct_mode").toBool(true);
    if (obj.contains("super_boost")) m_superBoost = obj.value("super_boost").toBool(false);
    if (obj.contains("limiter_enabled")) m_limiterEnabled = obj.value("limiter_enabled").toBool(true);
    if (obj.contains("bass_boost")) m_bassBoost = std::clamp(obj.value("bass_boost").toDouble(0.0), 0.0, 1.0);
    if (obj.contains("show_tray_msg")) m_showTrayMsg = obj.value("show_tray_msg").toBool(true);
    if (obj.contains("hotkeys_enabled")) m_hotkeysEnabled = obj.value("hotkeys_enabled").toBool(true);
    if (obj.contains("out_device")) m_selectedOutDevice = obj.value("out_device").toString();
    if (m_directMode && !obj.contains("output_selection_saved")) m_selectedOutDevice.clear();
    if (obj.contains("in_device")) m_selectedInDevice = obj.value("in_device").toString();
    m_selectedSourceDevice = obj.value("system_audio_source").toString();

    const QString geom = obj.value("window_geometry").toString();
    if (!geom.isEmpty()) {
        // Parse Tk-compatible "WxH+X+Y" or "WxH"
        const QStringList parts = geom.split('+');
        const QStringList wh = parts.value(0).split('x');
        if (wh.size() == 2) {
            bool okW = false, okH = false;
            int w = wh[0].toInt(&okW);
            int h = wh[1].toInt(&okH);
            if (okW && okH && w >= 540 && h >= 400) {
                m_winW = w;
                m_winH = h;
            }
        }
        if (parts.size() >= 3) {
            bool okX = false, okY = false;
            int x = parts[1].toInt(&okX);
            int y = parts[2].toInt(&okY);
            if (okX && okY) {
                m_winX = x;
                m_winY = y;
            }
        }
    }
}

void AppBackend::saveSettings() {
    if (m_screenshotMode) return;

    QString geom = QStringLiteral("%1x%2").arg(m_winW).arg(m_winH);
    if (m_mainWindow && m_mainWindow->isVisible()) {
        m_winW = m_mainWindow->width();
        m_winH = m_mainWindow->height();
        m_winX = m_mainWindow->x();
        m_winY = m_mainWindow->y();
        geom = QStringLiteral("%1x%2+%3+%4").arg(m_winW).arg(m_winH).arg(m_winX).arg(m_winY);
    }

    QJsonObject obj;
    obj["in_device"] = m_selectedInDevice;
    obj["system_audio_source"] = m_selectedSourceDevice;
    obj["out_device"] = m_selectedOutDevice;
    obj["output_selection_saved"] = true;
    obj["volume"] = m_volume;
    obj["autostart"] = m_autostart;
    obj["engine_active"] = engineRequested();
    obj["direct_mode"] = m_directMode;
    obj["super_boost"] = m_superBoost;
    obj["limiter_enabled"] = m_limiterEnabled;
    obj["bass_boost"] = m_bassBoost;
    obj["show_tray_msg"] = m_showTrayMsg;
    obj["hotkeys_enabled"] = m_hotkeysEnabled;
    obj["window_geometry"] = geom;

    QFile f(settingsFilePath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    }
}

void AppBackend::setVolume(double v) {
    const double clamped = std::clamp(v, m_directMode ? 100.0 : 0.0, 500.0);
    if (qFuzzyCompare(m_volume + 1.0, clamped + 1.0)) return;
    m_volume = clamped;
    sb_set_gain_percent(static_cast<float>(m_volume));
    emit volumeChanged();
    m_saveDebounce.start();
}

QString AppBackend::decibelText() const {
    if (m_volume <= 0.5) return QStringLiteral("-∞ dB");
    const double db = 20.0 * std::log10(m_volume / 100.0);
    if (db >= 0.0) {
        return QStringLiteral("+%1 dB").arg(db, 0, 'f', 1);
    }
    return QStringLiteral("%1 dB").arg(db, 0, 'f', 1);
}

void AppBackend::setDirectMode(bool d) {
    if (m_directMode == d) return;
    m_directMode = d;
    setVolume(m_volume);
    emit directModeChanged();
    emit audioSetupIssueChanged();
    if (engineRequested()) {
        startEngine();
    } else {
        m_statusMessage = m_directMode
            ? QStringLiteral("Ready — System Audio Boost")
            : QStringLiteral("Ready — Device Routing Mode");
        emit statusMessageChanged();
    }
    m_saveDebounce.start();
}

void AppBackend::setSuperBoost(bool s) {
    if (m_superBoost == s) return;
    m_superBoost = s;
    sb_set_super_boost(s);
    emit superBoostChanged();
    m_saveDebounce.start();
}

void AppBackend::setLimiterEnabled(bool l) {
    if (m_limiterEnabled == l) return;
    m_limiterEnabled = l;
    sb_set_limiter(l);
    emit limiterEnabledChanged();
    m_saveDebounce.start();
}

void AppBackend::setBassBoost(double b) {
    const double clamped = std::clamp(b, 0.0, 1.0);
    if (qFuzzyCompare(m_bassBoost + 1.0, clamped + 1.0)) return;
    m_bassBoost = clamped;
    sb_set_bass_boost(static_cast<float>(clamped));
    emit bassBoostChanged();
    m_saveDebounce.start();
}

void AppBackend::setAutostart(bool a) {
    if (m_autostart == a) return;
    m_autostart = a;
    WinWindowHelper::setWindowsAutostart(a, QString::fromLatin1(APP_REG_NAME),
                                         QCoreApplication::applicationFilePath());
    emit autostartChanged();
    m_saveDebounce.start();
}

void AppBackend::setShowTrayMsg(bool s) {
    if (m_showTrayMsg == s) return;
    m_showTrayMsg = s;
    emit showTrayMsgChanged();
    m_saveDebounce.start();
}

void AppBackend::setHotkeysEnabled(bool h) {
    if (m_hotkeysEnabled == h) return;
    m_hotkeysEnabled = h;
    if (m_winHelper) {
        m_winHelper->setHotkeysEnabled(!m_screenshotMode && h);
    }
    emit hotkeysEnabledChanged();
    m_saveDebounce.start();
}

void AppBackend::setSelectedOutDevice(const QString& id) {
    if (m_selectedOutDevice == id) return;
    m_selectedOutDevice = id;
    emit selectedOutDeviceChanged();
    emit audioSetupIssueChanged();
    if (engineRequested()) startEngine();
    m_saveDebounce.start();
}

void AppBackend::setSelectedInDevice(const QString& id) {
    if (m_selectedInDevice == id) return;
    m_selectedInDevice = id;
    emit selectedInDeviceChanged();
    if (engineRequested() && !m_directMode) startEngine();
    m_saveDebounce.start();
}

void AppBackend::setSelectedSourceDevice(const QString& id) {
    if (m_selectedSourceDevice == id) return;
    m_selectedSourceDevice = id;
    emit selectedSourceDeviceChanged();
    emit audioSetupIssueChanged();
    if (engineRequested() && m_directMode) startEngine();
    m_saveDebounce.start();
}

void AppBackend::startEngine() {
    if (engineRequested() && !stopEngine()) return;
    if (m_directMode) refreshDevices();
    const QString issue = audioSetupIssue();
    if (!issue.isEmpty()) {
        m_statusMessage = issue;
        setEngineState(false, false);
        emit statusMessageChanged();
        m_saveDebounce.start();
        return;
    }

    m_pendingDigitalSource = m_directMode && m_selectedSourceDevice == DIGITAL_SOURCE
        ? digitalSourceId() : QString();
    const QByteArray inUtf8 = (m_directMode
        ? (m_pendingDigitalSource.isEmpty() ? m_selectedSourceDevice : m_pendingDigitalSource)
        : m_selectedInDevice).toUtf8();
    m_activeDirectOutput = m_directMode ? directOutputId() : QString();
    const QByteArray outUtf8 = (m_directMode ? m_activeDirectOutput : m_selectedOutDevice).toUtf8();
    const bool starting = sb_start_engine(m_directMode, inUtf8.constData(), outUtf8.constData());

    char* rawStatus = sb_get_status_message();
    if (rawStatus) {
        m_statusMessage = QString::fromUtf8(rawStatus);
        sb_free_string(rawStatus);
    }

    setEngineState(false, starting);
    emit statusMessageChanged();
    m_saveDebounce.start();
}

bool AppBackend::stopEngine() {
    const bool usedDigitalRoute = m_windowsRoute.active();
    const bool restored = m_windowsRoute.stop();
    m_pendingDigitalSource.clear();
    m_digitalSignalWait.invalidate();
    sb_stop();
    m_statusMessage = !restored
        ? QStringLiteral("Windows could not restore playback. Select your speakers in Windows Sound settings.")
        : usedDigitalRoute ? QStringLiteral("Boost paused — Windows playback restored")
        : m_directMode ? QStringLiteral("Boost paused — routed playback stopped")
        : QStringLiteral("Boost paused");
    setEngineState(false, false);
    if (usedDigitalRoute) refreshDevices();
    emit statusMessageChanged();
    m_saveDebounce.start();
    return restored;
}

void AppBackend::toggleEngine() {
    if (engineRequested()) {
        stopEngine();
    } else {
        startEngine();
        if (!audioSetupIssue().isEmpty()) {
            emit audioSetupRequested();
            showMainWindow();
        }
    }
}

void AppBackend::setEngineState(bool active, bool starting) {
    const bool activeChanged = m_engineActive != active;
    const bool startingChanged = m_engineStarting != starting;
    m_engineActive = active;
    m_engineStarting = starting;
    if (activeChanged || startingChanged) updateTrayIcon();
    if (activeChanged) emit engineActiveChanged();
    if (startingChanged) emit engineStartingChanged();
}

void AppBackend::refreshDevices() {
    char* raw = sb_list_devices_json();
    if (!raw) return;
    const QJsonDocument doc = QJsonDocument::fromJson(QByteArray(raw));
    sb_free_string(raw);
    if (!doc.isObject()) return;

    const QJsonObject obj = doc.object();
    const auto outputs = obj.value("outputs").toArray().toVariantList();
    const auto inputs = obj.value("inputs").toArray().toVariantList();
    if (m_outputDevices != outputs || m_inputDevices != inputs) {
        m_outputDevices = outputs;
        m_inputDevices = inputs;
        m_windowsOutput.clear();
        for (const auto& entry : m_outputDevices) {
            const auto device = entry.toMap();
            if (device.value("isDefault").toBool()) {
                m_windowsOutput = device;
                break;
            }
        }
        emit devicesChanged();
        emit audioSetupIssueChanged();
    }
    if (m_selectedInDevice.isEmpty() && !m_inputDevices.isEmpty()) {
        m_selectedInDevice = m_inputDevices.first().toMap().value("id").toString();
        emit selectedInDeviceChanged();
    }
}

QString AppBackend::directOutputId() const {
    if (!m_selectedOutDevice.isEmpty()) return m_selectedOutDevice;
    if (m_windowsRoute.active()) return m_activeDirectOutput;
    return m_windowsOutput.value("id").toString();
}

QString AppBackend::windowsOutputName() const {
    if (m_windowsRoute.active() && m_selectedOutDevice.isEmpty()) {
        for (const auto& entry : m_outputDevices) {
            const auto device = entry.toMap();
            if (device.value("id").toString() == m_activeDirectOutput)
                return device.value("name").toString();
        }
    }
    return m_windowsOutput.value("name").toString();
}

QString AppBackend::digitalSourceId() const {
    if (m_windowsRoute.active()) return m_windowsRoute.source();
    const QString output = directOutputId();
    const QString currentDefault = m_windowsOutput.value("id").toString();
    for (const QVariant& entry : m_outputDevices) {
        const auto device = entry.toMap();
        const auto id = device.value("id").toString();
        if (device.value("isDigital").toBool() && !id.isEmpty() && id != output && id != currentDefault)
            return id;
    }
    return {};
}

QString AppBackend::digitalSourceName() const {
    const QString source = digitalSourceId();
    for (const QVariant& entry : m_outputDevices) {
        const auto device = entry.toMap();
        if (device.value("id").toString() == source) return device.value("name").toString();
    }
    return {};
}

QByteArray AppBackend::masterOutputId() const {
    return m_directMode ? directOutputId().toUtf8() : QByteArray();
}

QString AppBackend::audioSetupIssue() const {
    if (!m_directMode) return {};
    const auto isAvailable = [this](const QString& id) {
        return !id.isEmpty() && std::any_of(m_outputDevices.cbegin(), m_outputDevices.cend(),
            [&id](const QVariant& entry) { return entry.toMap().value("id").toString() == id; });
    };
    const QString outputId = directOutputId();
    if (!isAvailable(outputId))
        return m_selectedOutDevice.isEmpty()
            ? QStringLiteral("Windows has no default playback device. Connect or select your speakers or headphones.")
            : QStringLiteral("Your saved playback device is unavailable. Choose Windows default or another device.");
    if (m_selectedSourceDevice.isEmpty())
        return QStringLiteral("Choose Automatic Digital Output or another silent audio source.");
    if (m_selectedSourceDevice == DIGITAL_SOURCE)
        return digitalSourceId().isEmpty()
            ? QStringLiteral("Automatic routing needs an enabled digital audio output and separate speakers or headphones.")
            : QString();
    if (!isAvailable(m_selectedSourceDevice))
        return QStringLiteral("Your saved audio source is unavailable. Choose a silent audio source.");
    if (outputId == m_selectedSourceDevice)
        return QStringLiteral("Choose different devices for the silent source and playback.");
    return {};
}

void AppBackend::refreshSessions() {
    char* raw = sb_list_sessions_json();
    if (!raw) return;
    const QJsonDocument doc = QJsonDocument::fromJson(QByteArray(raw));
    sb_free_string(raw);
    if (!doc.isArray()) return;
    m_audioSessions = doc.array().toVariantList();
    emit sessionsChanged();
}

void AppBackend::setSessionVolume(int pid, double vol) {
    sb_set_session_volume(static_cast<uint32_t>(pid), static_cast<float>(std::clamp(vol, 0.0, 1.0)));
    refreshSessions();
}

void AppBackend::setSessionMute(int pid, bool mute) {
    sb_set_session_mute(static_cast<uint32_t>(pid), mute);
    refreshSessions();
}

void AppBackend::setMasterVolume(double pct) {
    const double clamped = std::clamp(pct, 0.0, 100.0);
    sb_set_master_volume(masterOutputId().constData(), static_cast<float>(clamped / 100.0));
    m_masterVolume = clamped;
    emit masterVolumeChanged();
}

void AppBackend::applyBoostLevel(double pct) {
    setVolume(pct);
    if (m_volume > 100.0 && !engineRequested()) {
        toggleEngine();
    }
}

void AppBackend::dismissStartupNotice(bool dontShowAgain) {
    m_startupNoticeVisible = false;
    emit startupNoticeVisibleChanged();
    if (dontShowAgain) {
        setShowTrayMsg(false);
    }
}

void AppBackend::pollMeters() {
    float il = 0, ir = 0, ol = 0, orr = 0, red = 0;
    sb_get_meters(&il, &ir, &ol, &orr, &red);

    m_inL = il;
    m_inR = ir;
    m_outL = ol;
    m_outR = orr;
    m_limRed = red;

    float bands[SPECTRUM_COUNT]{};
    const size_t n = sb_get_spectrum(bands, SPECTRUM_COUNT);
    for (size_t i = 0; i < n; ++i) {
        m_spectrum[static_cast<int>(i)] = static_cast<double>(bands[i]);
    }
    emit metersChanged();

    if (m_screenshotMode || !engineRequested()) return;
    const bool starting = sb_is_starting();
    const bool running = sb_is_running();
    if (char* rawStatus = sb_get_status_message()) {
        QString status = QString::fromUtf8(rawStatus);
        sb_free_string(rawStatus);
        if (running && m_directMode) {
            if (m_engineStarting) {
                status = QStringLiteral("Connecting to Windows audio…");
            } else if (std::max(il, ir) <= AUDIBLE_PEAK) {
                status = m_windowsRoute.active()
                    ? QStringLiteral("Waiting for sound from apps using the Windows default output")
                    : QStringLiteral("Waiting for sound on your selected source. Check Windows Volume Mixer.");
            }
        }
        if (status != m_statusMessage) {
            m_statusMessage = status;
            emit statusMessageChanged();
        }
    }
    if (!running && !starting) {
        if (m_windowsRoute.active()) {
            if (!m_windowsRoute.stop()) {
                m_statusMessage = QStringLiteral("Windows could not restore playback. Select your speakers in Windows Sound settings.");
                emit statusMessageChanged();
            }
            refreshDevices();
        } else if (m_directMode && m_pendingDigitalSource.isEmpty()) {
            refreshDevices();
            if (directOutputId() != m_activeDirectOutput) {
                startEngine();
                return;
            }
        }
        m_pendingDigitalSource.clear();
        m_digitalSignalWait.invalidate();
        setEngineState(false, false);
        m_saveDebounce.start();
    } else if (running && m_engineStarting) {
        if (!m_pendingDigitalSource.isEmpty()) {
            if (!m_windowsRoute.active()) {
                const bool playbackInProgress = sb_output_peak(
                    m_windowsOutput.value("id").toString().toUtf8().constData()) > AUDIBLE_PEAK;
                const bool sourceSilenced = sb_output_is_silenced(m_pendingDigitalSource.toUtf8().constData());
                const bool playbackSilenced = sb_output_is_silenced(m_activeDirectOutput.toUtf8().constData());
                if (sourceSilenced || playbackSilenced || !m_windowsRoute.start(m_pendingDigitalSource)) {
                    stopEngine();
                    refreshDevices();
                    m_statusMessage = sourceSilenced
                        ? QStringLiteral("The digital output is muted or at zero volume. Check Windows Sound settings.")
                        : playbackSilenced
                        ? QStringLiteral("Your playback device is muted or at zero volume. Check Windows Sound settings.")
                        : QStringLiteral("Windows could not switch to the digital output. Check Windows Sound settings.");
                    emit statusMessageChanged();
                    return;
                }
                refreshDevices();
                if (playbackInProgress) {
                    m_digitalSignalWait.start();
                    return;
                }
            } else if (m_digitalSignalWait.isValid() && std::max(ol, orr) <= AUDIBLE_PEAK) {
                if (!m_digitalSignalWait.hasExpired(DIGITAL_HANDOFF_TIMEOUT_MS)) return;
                if (stopEngine()) {
                    m_statusMessage = QStringLiteral("Boost received no sound. Windows playback was restored.");
                    emit statusMessageChanged();
                }
                return;
            }
        }
        m_digitalSignalWait.invalidate();
        setEngineState(true, false);
        m_saveDebounce.start();
    }
}

void AppBackend::pollSessions() {
    if (!m_screenshotMode) {
        refreshDevices();
        if (m_windowsRoute.active()) {
            if (m_windowsOutput.value("id").toString() != m_windowsRoute.source()) stopEngine();
        } else if (m_directMode && engineRequested() && directOutputId() != m_activeDirectOutput) {
            startEngine();
        }
    }
    refreshSessions();
    const double mv = std::round(static_cast<double>(sb_get_master_volume(masterOutputId().constData())) * 100.0);
    if (!qFuzzyCompare(m_masterVolume + 1.0, mv + 1.0)) {
        m_masterVolume = mv;
        emit masterVolumeChanged();
    }
}

QIcon AppBackend::buildSpeakerIcon(bool active) {
    QPixmap pm(64, 64);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing, true);

    const QColor col = active ? QColor(46, 204, 113) : QColor(231, 76, 60);
    p.setPen(Qt::NoPen);
    p.setBrush(col);

    // Speaker box + cone (matching original make_icons.py aesthetic)
    p.drawRoundedRect(12, 22, 13, 20, 2, 2);
    QPolygonF cone;
    cone << QPointF(24, 22) << QPointF(40, 10) << QPointF(40, 54) << QPointF(24, 42);
    p.drawPolygon(cone);

    QPen pen(col, 4.5, Qt::SolidLine, Qt::RoundCap);
    p.setPen(pen);
    p.setBrush(Qt::NoBrush);
    if (active) {
        p.drawArc(33, 18, 18, 28, -50 * 16, 100 * 16);
        p.drawArc(27, 10, 30, 44, -50 * 16, 100 * 16);
    } else {
        p.drawLine(45, 24, 57, 40);
        p.drawLine(57, 24, 45, 40);
    }
    return QIcon(pm);
}

void AppBackend::setupTray() {
    if (!QSystemTrayIcon::isSystemTrayAvailable() || m_trayIcon) return;

    m_trayIcon = new QSystemTrayIcon(buildSpeakerIcon(m_engineActive), this);
    m_trayIcon->setToolTip(QStringLiteral("Super Booster — Volume Overdrive"));

    auto* menu = new QMenu();
    auto* openPopupAct = menu->addAction(QStringLiteral("Open Volume Slider"));
    auto* openSettingsAct = menu->addAction(QStringLiteral("Open Super Booster"));
    m_trayToggleAction = menu->addAction(QStringLiteral("Start Boost"));
    menu->addSeparator();
    auto* quitAct = menu->addAction(QStringLiteral("Quit Completely"));

    connect(openPopupAct, &QAction::triggered, this, &AppBackend::togglePopup);
    connect(openSettingsAct, &QAction::triggered, this, &AppBackend::showMainWindow);
    connect(m_trayToggleAction, &QAction::triggered, this, &AppBackend::toggleEngine);
    connect(quitAct, &QAction::triggered, this, &AppBackend::quitApp);
    connect(m_trayIcon, &QSystemTrayIcon::messageClicked, this, [this] {
        if (!m_updateNotificationPending) return;
        m_updateNotificationPending = false;
        emit updateNotificationClicked();
    });

    connect(m_trayIcon, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick) {
            togglePopup();
        }
    });

    m_trayIcon->setContextMenu(menu);
    updateTrayIcon();
    m_trayIcon->show();
}

void AppBackend::notifyUpdate(const QString& version) {
    if (!m_trayIcon || !QSystemTrayIcon::supportsMessages()) return;
    m_updateNotificationPending = true;
    m_trayIcon->showMessage(tr("Super Booster %1 is available").arg(version),
        tr("Open the update details to download and install it."), QSystemTrayIcon::Information);
}

void AppBackend::updateTrayIcon() {
    if (m_trayIcon) {
        m_trayIcon->setIcon(buildSpeakerIcon(m_engineActive));
        m_trayIcon->setToolTip(
            m_engineActive
                ? QStringLiteral("Super Booster (%1%) — Active").arg(qRound(m_volume))
                : m_engineStarting ? QStringLiteral("Super Booster — Connecting")
                                   : QStringLiteral("Super Booster — Paused"));
    }
    if (m_trayToggleAction) {
        m_trayToggleAction->setText(m_engineActive ? QStringLiteral("Pause Boost")
            : m_engineStarting ? QStringLiteral("Cancel Boost") : QStringLiteral("Start Boost"));
    }
}

void AppBackend::showMainWindow() {
    if (m_popupWindow && m_popupWindow->isVisible()) {
        m_popupWindow->hide();
    }
    if (m_mainWindow) {
        m_mainWindow->show();
        m_mainWindow->raise();
        m_mainWindow->requestActivate();
    }
}

void AppBackend::hideMainWindow() {
    if (m_mainWindow) {
        saveSettings();
        if (QSystemTrayIcon::isSystemTrayAvailable() && m_trayIcon) {
            m_mainWindow->hide();
            if (m_showTrayMsg && !m_startupNoticeVisible) {
                m_updateNotificationPending = false;
                m_trayIcon->showMessage(
                    QStringLiteral("Super Booster"),
                    QStringLiteral("Still boosting in the background. Click the tray icon for quick volume control."),
                    QSystemTrayIcon::Information,
                    2500);
            }
        } else {
            m_mainWindow->showMinimized();
        }
    }
}

void AppBackend::togglePopup() {
    if (!m_popupWindow) return;
    if (m_popupWindow->isVisible()) {
        m_popupWindow->hide();
        return;
    }

    const QPoint cursor = QCursor::pos();
    QScreen* screen = QGuiApplication::screenAt(cursor);
    if (!screen) screen = QGuiApplication::primaryScreen();
    const QRect avail = screen ? screen->availableGeometry() : QRect(0, 0, 1920, 1080);

    const int pw = m_popupWindow->width();
    const int ph = m_popupWindow->height();
    int x = cursor.x() - pw / 2;
    int y = cursor.y() - ph - 14;
    if (x + pw > avail.right()) x = avail.right() - pw - 8;
    if (x < avail.left()) x = avail.left() + 8;
    if (y < avail.top()) y = cursor.y() + 14;
    if (y + ph > avail.bottom()) y = avail.bottom() - ph - 8;

    m_popupWindow->setPosition(x, y);
    m_popupWindow->show();
    m_popupWindow->raise();
    m_popupWindow->requestActivate();
}

void AppBackend::quitApp() {
    saveSettings();
    if (m_trayIcon) m_trayIcon->hide();
    m_windowsRoute.stop();
    sb_shutdown();
    QCoreApplication::quit();
}
