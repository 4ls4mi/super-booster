#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QPointer>
#include <QRect>
#include <QTimer>
#include <QVariantList>
#include <QIcon>
#include "windows_audio_route.h"

class QQuickWindow;
class QScreen;
class QSystemTrayIcon;
class QAction;
class WinWindowHelper;

class AppBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(QString decibelText READ decibelText NOTIFY volumeChanged)
    Q_PROPERTY(bool engineActive READ engineActive NOTIFY engineActiveChanged)
    Q_PROPERTY(bool engineStarting READ engineStarting NOTIFY engineStartingChanged)
    Q_PROPERTY(bool directMode READ directMode WRITE setDirectMode NOTIFY directModeChanged)
    Q_PROPERTY(bool superBoost READ superBoost WRITE setSuperBoost NOTIFY superBoostChanged)
    Q_PROPERTY(bool limiterEnabled READ limiterEnabled WRITE setLimiterEnabled NOTIFY limiterEnabledChanged)
    Q_PROPERTY(double bassBoost READ bassBoost WRITE setBassBoost NOTIFY bassBoostChanged)
    Q_PROPERTY(bool autostart READ autostart WRITE setAutostart NOTIFY autostartChanged)
    Q_PROPERTY(bool showTrayMsg READ showTrayMsg WRITE setShowTrayMsg NOTIFY showTrayMsgChanged)
    Q_PROPERTY(bool hotkeysEnabled READ hotkeysEnabled WRITE setHotkeysEnabled NOTIFY hotkeysEnabledChanged)
    Q_PROPERTY(QString selectedOutDevice READ selectedOutDevice WRITE setSelectedOutDevice NOTIFY selectedOutDeviceChanged)
    Q_PROPERTY(QString selectedInDevice READ selectedInDevice WRITE setSelectedInDevice NOTIFY selectedInDeviceChanged)
    Q_PROPERTY(QString selectedSourceDevice READ selectedSourceDevice WRITE setSelectedSourceDevice NOTIFY selectedSourceDeviceChanged)
    Q_PROPERTY(QVariantList outputDevices READ outputDevices NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList inputDevices READ inputDevices NOTIFY devicesChanged)
    Q_PROPERTY(QString windowsOutputName READ windowsOutputName NOTIFY devicesChanged)
    Q_PROPERTY(QString automaticPlaybackOutputName READ automaticPlaybackOutputName NOTIFY audioSetupIssueChanged)
    Q_PROPERTY(QString digitalSourceName READ digitalSourceName NOTIFY audioSetupIssueChanged)
    Q_PROPERTY(QVariantList audioSessions READ audioSessions NOTIFY sessionsChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(QString audioSetupIssue READ audioSetupIssue NOTIFY audioSetupIssueChanged)
    Q_PROPERTY(double inputPeakL READ inputPeakL NOTIFY metersChanged)
    Q_PROPERTY(double inputPeakR READ inputPeakR NOTIFY metersChanged)
    Q_PROPERTY(double outputPeakL READ outputPeakL NOTIFY metersChanged)
    Q_PROPERTY(double outputPeakR READ outputPeakR NOTIFY metersChanged)
    Q_PROPERTY(double limiterReduction READ limiterReduction NOTIFY metersChanged)
    Q_PROPERTY(QVariantList spectrumBands READ spectrumBands NOTIFY metersChanged)
    Q_PROPERTY(double masterVolume READ masterVolume NOTIFY masterVolumeChanged)
    Q_PROPERTY(bool startupNoticeVisible READ startupNoticeVisible NOTIFY startupNoticeVisibleChanged)
    Q_PROPERTY(QString appearanceLayout READ appearanceLayout WRITE setAppearanceLayout NOTIFY appearanceLayoutChanged)
    Q_PROPERTY(QString appearanceMaterial READ appearanceMaterial WRITE setAppearanceMaterial NOTIFY appearanceMaterialChanged)
    Q_PROPERTY(QRect mainWindowWorkArea READ mainWindowWorkArea NOTIFY mainWindowWorkAreaChanged)

public:
    explicit AppBackend(WinWindowHelper* winHelper, bool screenshotMode, QObject* parent = nullptr,
                        const QString& settingsPath = {});
    ~AppBackend() override;

    void setWindows(QQuickWindow* mainWindow, QQuickWindow* popupWindow);
    void saveSettings();

    double volume() const { return m_volume; }
    void setVolume(double v);
    QString decibelText() const;

    bool engineActive() const { return m_engineActive; }
    bool engineStarting() const { return m_engineStarting; }
    bool directMode() const { return m_directMode; }
    void setDirectMode(bool d);

    bool superBoost() const { return m_superBoost; }
    void setSuperBoost(bool s);

    bool limiterEnabled() const { return m_limiterEnabled; }
    void setLimiterEnabled(bool l);

    double bassBoost() const { return m_bassBoost; }
    void setBassBoost(double b);

    bool autostart() const { return m_autostart; }
    void setAutostart(bool a);

    bool showTrayMsg() const { return m_showTrayMsg; }
    void setShowTrayMsg(bool s);

    bool hotkeysEnabled() const { return m_hotkeysEnabled; }
    void setHotkeysEnabled(bool h);

    QString selectedOutDevice() const { return m_selectedOutDevice; }
    void setSelectedOutDevice(const QString& id);

    QString selectedInDevice() const { return m_selectedInDevice; }
    void setSelectedInDevice(const QString& id);

    QString selectedSourceDevice() const { return m_selectedSourceDevice; }
    void setSelectedSourceDevice(const QString& id);

    QVariantList outputDevices() const { return m_outputDevices; }
    QVariantList inputDevices() const { return m_inputDevices; }
    QString windowsOutputName() const;
    QString automaticPlaybackOutputName() const;
    QString digitalSourceName() const;
    QVariantList audioSessions() const { return m_audioSessions; }
    QString statusMessage() const { return m_statusMessage; }
    QString audioSetupIssue() const;

    double inputPeakL() const { return m_inL; }
    double inputPeakR() const { return m_inR; }
    double outputPeakL() const { return m_outL; }
    double outputPeakR() const { return m_outR; }
    double limiterReduction() const { return m_limRed; }
    QVariantList spectrumBands() const { return m_spectrum; }
    double masterVolume() const { return m_masterVolume; }
    bool startupNoticeVisible() const { return m_startupNoticeVisible; }
    QString appearanceLayout() const { return m_appearanceLayout; }
    void setAppearanceLayout(const QString& layout);
    QString appearanceMaterial() const { return m_appearanceMaterial; }
    void setAppearanceMaterial(const QString& material);
    QRect mainWindowWorkArea() const;

    Q_INVOKABLE void toggleEngine();
    Q_INVOKABLE bool stopEngine();
    Q_INVOKABLE void refreshDevices();
    Q_INVOKABLE void refreshSessions();
    Q_INVOKABLE void setSessionVolume(int pid, double vol);
    Q_INVOKABLE void setSessionMute(int pid, bool mute);
    Q_INVOKABLE void setMasterVolume(double pct);
    Q_INVOKABLE void applyBoostLevel(double pct);
    Q_INVOKABLE void dismissStartupNotice(bool dontShowAgain);
    Q_INVOKABLE void showMainWindow();
    Q_INVOKABLE void hideMainWindow();
    Q_INVOKABLE void togglePopup();
    Q_INVOKABLE void quitApp();
    void notifyUpdate(const QString& version);

signals:
    void volumeChanged();
    void engineActiveChanged();
    void engineStartingChanged();
    void directModeChanged();
    void superBoostChanged();
    void limiterEnabledChanged();
    void bassBoostChanged();
    void autostartChanged();
    void showTrayMsgChanged();
    void hotkeysEnabledChanged();
    void selectedOutDeviceChanged();
    void selectedInDeviceChanged();
    void selectedSourceDeviceChanged();
    void devicesChanged();
    void sessionsChanged();
    void statusMessageChanged();
    void audioSetupIssueChanged();
    void audioSetupRequested();
    void metersChanged();
    void masterVolumeChanged();
    void startupNoticeVisibleChanged();
    void appearanceLayoutChanged();
    void appearanceMaterialChanged();
    void mainWindowWorkAreaChanged();
    void updateNotificationClicked();

private slots:
    void pollMeters();
    void pollSessions();

private:
    void watchWorkArea(QScreen* screen);
    void loadSettings();
    void startEngine();
    void setEngineState(bool active, bool starting);
    bool engineRequested() const { return m_engineActive || m_engineStarting; }
    void setupTray();
    void updateTrayIcon();
    QIcon buildSpeakerIcon(bool active);
    QString directOutputId() const;
    QString digitalSourceId() const;
    QByteArray masterOutputId() const;

    WinWindowHelper* m_winHelper = nullptr;
    bool m_screenshotMode = false;
    const bool m_readOnlySettings;
    const QString m_settingsPath;
    WindowsAudioRoute m_windowsRoute;
    QPointer<QQuickWindow> m_mainWindow;
    QPointer<QQuickWindow> m_popupWindow;
    QMetaObject::Connection m_workAreaConnection;
    QSystemTrayIcon* m_trayIcon = nullptr;
    bool m_updateNotificationPending = false;
    QAction* m_trayToggleAction = nullptr;

    double m_volume = 100.0;
    bool m_engineActive = false;
    bool m_engineStarting = false;
    bool m_directMode = true;
    bool m_superBoost = false;
    bool m_limiterEnabled = true;
    double m_bassBoost = 0.0;
    bool m_autostart = false;
    bool m_showTrayMsg = true;
    bool m_hotkeysEnabled = true;
    bool m_startupNoticeVisible = false;
    QString m_appearanceLayout = QStringLiteral("glass");
    QString m_appearanceMaterial = QStringLiteral("frosted");

    QString m_selectedOutDevice;
    QString m_activeDirectOutput;
    QString m_pendingDigitalSource;
    QElapsedTimer m_digitalSignalWait;
    QString m_selectedInDevice;
    QString m_selectedSourceDevice;
    QVariantList m_outputDevices;
    QVariantList m_inputDevices;
    QVariantMap m_windowsOutput;
    QVariantList m_audioSessions;
    QString m_statusMessage;

    double m_inL = 0.0;
    double m_inR = 0.0;
    double m_outL = 0.0;
    double m_outR = 0.0;
    double m_limRed = 0.0;
    QVariantList m_spectrum;
    double m_masterVolume = 100.0;

    QTimer m_meterTimer;
    QTimer m_sessionTimer;
    QTimer m_saveDebounce;
    bool m_hasWindowPosition = false;
    int m_winX = -1;
    int m_winY = -1;
    int m_winW = 1020;
    int m_winH = 610;
};
