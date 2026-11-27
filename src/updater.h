#pragma once

#include <QCryptographicHash>
#include <QElapsedTimer>
#include <QNetworkAccessManager>
#include <QObject>
#include <QSaveFile>
#include <QSettings>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>
#include <QWebSocket>

#include <memory>

class Updater : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString version READ version NOTIFY releaseChanged)
    Q_PROPERTY(QString notes READ notes NOTIFY releaseChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(bool automatic READ automatic WRITE setAutomatic NOTIFY preferencesChanged)
    Q_PROPERTY(QString notificationMode READ notificationMode WRITE setNotificationMode NOTIFY preferencesChanged)
    Q_PROPERTY(bool supported READ supported CONSTANT)

public:
    explicit Updater(QObject* parent = nullptr);
    void start();
    QString currentVersion() const;
    QString version() const { return m_release.version; }
    QString notes() const { return m_release.notes; }
    QString state() const { return m_state; }
    QString error() const { return m_error; }
    double progress() const { return m_progress; }
    bool automatic() const;
    QString notificationMode() const;
    bool supported() const;
    void setAutomatic(bool enabled);
    void setNotificationMode(const QString& mode);

    Q_INVOKABLE void check();
    Q_INVOKABLE void download();
    Q_INVOKABLE void install();
    Q_INVOKABLE void remindLater();
    Q_INVOKABLE void dismiss();

signals:
    void releaseChanged();
    void stateChanged();
    void progressChanged();
    void preferencesChanged();
    void offerAvailable();
    void nativeNotificationRequested(const QString& version);
    void showDetailsRequested();
    void installReady();

private:
    struct Release {
        QString version;
        QString file;
        QString notes;
        QUrl url;
        QByteArray sha256;
        qint64 size = 0;
    };

    void configureAutomaticChecks();
    void connectPush();
    void reconnectPush();
    void acceptHint(const QString& text);
    void checkRelease(bool manual);
    static Release parseRelease(const QByteArray& payload, const QString& installed, bool& valid);
    void offerRelease();
    void scheduleReminder();
    void requestInstaller(const QUrl& url, int redirects);
    void discardDownload();
    void setState(const QString& state, const QString& error = {});
    void setProgress(double progress);
    bool busy() const;

    QSettings m_settings;
    QNetworkAccessManager m_network;
    QWebSocket m_socket;
    QTimer m_periodic;
    QTimer m_reconnect;
    QTimer m_hintCheck;
    QTimer m_reminder;
    QElapsedTimer m_lastCheck;
    QNetworkReply* m_checkReply = nullptr;
    Release m_release;
    QString m_state = QStringLiteral("idle");
    QString m_error;
    QString m_offeredVersion;
    QString m_hintVersion;
    int m_hintChecks = 0;
    int m_reconnectDelay = 2000;
    bool m_started = false;
    bool m_handoffStarted = false;
    double m_progress = 0;
    std::unique_ptr<QTemporaryDir> m_staging;
    std::unique_ptr<QSaveFile> m_installer;
    QCryptographicHash m_hasher{QCryptographicHash::Sha256};
    qint64 m_received = 0;
};
