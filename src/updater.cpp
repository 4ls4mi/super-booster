#include "updater.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QVersionNumber>

namespace {
const QUrl ReleaseApi(QStringLiteral("https://api.github.com/repos/4ls4mi/super-booster/releases/latest"));
const QUrl PushUrl(QStringLiteral(SUPER_BOOSTER_PUSH_URL));
constexpr int MaxMetadata = 512 * 1024;
constexpr qint64 MaxInstaller = 256 * 1024 * 1024;
constexpr int CheckInterval = 15 * 60 * 1000;
constexpr int ReminderInterval = 60 * 60 * 1000;
constexpr int HintThrottle = 15 * 1000;

bool newer(const QString& candidate, const QString& installed) {
    static const QRegularExpression stable(QStringLiteral("^(0|[1-9][0-9]{0,8})(\\.(0|[1-9][0-9]{0,8})){2}$"));
    return stable.match(candidate).hasMatch() &&
        QVersionNumber::compare(QVersionNumber::fromString(candidate), QVersionNumber::fromString(installed)) > 0;
}

bool httpsUrl(const QUrl& url) {
    return url.isValid() && url.scheme() == QStringLiteral("https") && url.userInfo().isEmpty() &&
        url.port(443) == 443 && !url.hasFragment();
}

bool validDownloadUrl(const QUrl& url, const QUrl& initial) {
    return httpsUrl(url) && (url == initial || url.host() == QStringLiteral("release-assets.githubusercontent.com"));
}

QNetworkRequest requestFor(const QUrl& url) {
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Super-Booster/" + QCoreApplication::applicationVersion().toUtf8());
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setTransferTimeout(30000);
    return request;
}
}

Updater::Updater(QObject* parent)
    : QObject(parent),
      m_settings(QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("booster_update.ini")),
                 QSettings::IniFormat) {
    m_periodic.setInterval(CheckInterval);
    m_reconnect.setSingleShot(true);
    m_hintCheck.setSingleShot(true);
    m_reminder.setSingleShot(true);
    m_socket.setMaxAllowedIncomingFrameSize(4096);
    m_socket.setMaxAllowedIncomingMessageSize(4096);
    connect(&m_periodic, &QTimer::timeout, this, [this] { checkRelease(false); });
    connect(&m_reconnect, &QTimer::timeout, this, &Updater::connectPush);
    connect(&m_reminder, &QTimer::timeout, this, [this] {
        if (automatic()) {
            m_offeredVersion.clear();
            offerRelease();
        }
    });
    connect(&m_hintCheck, &QTimer::timeout, this, [this] {
        if (!automatic() || m_hintChecks == 0) return;
        if (busy() || m_checkReply) {
            m_hintCheck.start(3000);
            return;
        }
        --m_hintChecks;
        checkRelease(false);
        if (m_hintChecks > 0) m_hintCheck.start(60000);
    });
    connect(&m_socket, &QWebSocket::connected, this, [this] {
        m_reconnectDelay = 2000;
        if (automatic() && (!m_lastCheck.isValid() || m_lastCheck.elapsed() >= 60000)) checkRelease(false);
    });
    connect(&m_socket, &QWebSocket::disconnected, this, &Updater::reconnectPush);
    connect(&m_socket, &QWebSocket::errorOccurred, this, &Updater::reconnectPush);
    connect(&m_socket, &QWebSocket::textMessageReceived, this, &Updater::acceptHint);
}

void Updater::start() {
    m_started = true;
    configureAutomaticChecks();
}

QString Updater::currentVersion() const { return QCoreApplication::applicationVersion(); }
bool Updater::automatic() const { return m_settings.value(QStringLiteral("automatic"), true).toBool(); }

QString Updater::notificationMode() const {
    const QString value = m_settings.value(QStringLiteral("notificationMode"), QStringLiteral("notify")).toString();
    return value == QStringLiteral("quiet") || value == QStringLiteral("toast") || value == QStringLiteral("dialog")
        ? value : QStringLiteral("notify");
}

bool Updater::supported() const {
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}

void Updater::setAutomatic(bool enabled) {
    if (enabled == automatic()) return;
    m_settings.setValue(QStringLiteral("automatic"), enabled);
    emit preferencesChanged();
    configureAutomaticChecks();
}

void Updater::setNotificationMode(const QString& mode) {
    if (mode != QStringLiteral("quiet") && mode != QStringLiteral("toast") &&
        mode != QStringLiteral("notify") && mode != QStringLiteral("dialog")) return;
    if (mode == notificationMode()) return;
    m_settings.setValue(QStringLiteral("notificationMode"), mode);
    emit preferencesChanged();
    m_offeredVersion.clear();
    offerRelease();
}

void Updater::configureAutomaticChecks() {
    if (m_started && automatic() && supported()) {
        m_periodic.start();
        QTimer::singleShot(700, this, [this] {
            if (!automatic()) return;
            checkRelease(false);
            connectPush();
        });
        scheduleReminder();
        return;
    }
    m_periodic.stop();
    m_reconnect.stop();
    m_hintCheck.stop();
    m_reminder.stop();
    m_socket.abort();
    m_hintVersion.clear();
    m_hintChecks = 0;
}

void Updater::connectPush() {
    if (m_started && automatic() && PushUrl.scheme() == QStringLiteral("wss") &&
        m_socket.state() == QAbstractSocket::UnconnectedState) {
        m_socket.open(PushUrl);
    }
}

void Updater::reconnectPush() {
    if (!m_started || !automatic() || PushUrl.scheme() != QStringLiteral("wss") || m_reconnect.isActive()) return;
    m_reconnect.start(m_reconnectDelay);
    m_reconnectDelay = qMin(m_reconnectDelay * 2, 5 * 60 * 1000);
}

void Updater::acceptHint(const QString& text) {
    if (!automatic()) return;
    const auto message = QJsonDocument::fromJson(text.toUtf8()).object();
    if (message.value(QStringLiteral("type")).toString() != QStringLiteral("release")) return;
    const QString hint = message.value(QStringLiteral("version")).toString();
    if (!newer(hint, version().isEmpty() ? currentVersion() : version()) || !newer(hint, m_hintVersion)) return;
    // A push is only a wake-up hint. Download details always come from GitHub.
    m_hintVersion = hint;
    m_hintChecks = 2;
    const auto elapsed = m_lastCheck.isValid() ? m_lastCheck.elapsed() : HintThrottle;
    m_hintCheck.start(static_cast<int>(qMax<qint64>(150, HintThrottle - elapsed)));
}

Updater::Release Updater::parseRelease(const QByteArray& payload, const QString& installed, bool& valid) {
    valid = false;
    const auto json = QJsonDocument::fromJson(payload).object();
    if (json.value(QStringLiteral("draft")) != QJsonValue(false) ||
        json.value(QStringLiteral("prerelease")) != QJsonValue(false)) return {};
    const QString tag = json.value(QStringLiteral("tag_name")).toString();
    if (!tag.startsWith(QLatin1Char('v')) || !newer(tag.mid(1), QStringLiteral("0.0.0"))) return {};
    const QString version = tag.mid(1);
    if (!newer(version, installed)) {
        valid = true;
        return {};
    }
    const QString file = QStringLiteral("SuperBooster-%1-windows-x64-setup.exe").arg(version);
    const QUrl expected(QStringLiteral("https://github.com/4ls4mi/super-booster/releases/download/%1/%2").arg(tag, file));
    static const QRegularExpression digestPattern(QStringLiteral("^sha256:([a-f0-9]{64})$"));
    for (const auto& entry : json.value(QStringLiteral("assets")).toArray()) {
        const auto asset = entry.toObject();
        if (asset.value(QStringLiteral("name")).toString() != file ||
            asset.value(QStringLiteral("state")).toString() != QStringLiteral("uploaded") ||
            QUrl(asset.value(QStringLiteral("browser_download_url")).toString(), QUrl::StrictMode) != expected) continue;
        const auto digest = digestPattern.match(asset.value(QStringLiteral("digest")).toString());
        const qint64 size = asset.value(QStringLiteral("size")).toInteger();
        if (!digest.hasMatch() || size < 1024 || size > MaxInstaller) continue;
        valid = true;
        return {version, file, json.value(QStringLiteral("body")).toString().left(16000), expected,
                QByteArray::fromHex(digest.captured(1).toLatin1()), size};
    }
    return {};
}

void Updater::check() { checkRelease(true); }

void Updater::checkRelease(bool manual) {
    if (!m_started || !supported() || (!manual && !automatic()) || m_checkReply || busy()) return;
    m_lastCheck.start();
    if (manual || (version().isEmpty() && m_state != QStringLiteral("current"))) setState(QStringLiteral("checking"));
    auto request = requestFor(ReleaseApi);
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setRawHeader("X-GitHub-Api-Version", "2022-11-28");
    auto* reply = m_network.get(request);
    m_checkReply = reply;
    auto bytes = std::make_shared<QByteArray>();
    auto read = [reply, bytes] {
        const auto chunk = reply->read(MaxMetadata + 1 - bytes->size());
        bytes->append(chunk);
        if (bytes->size() > MaxMetadata) reply->abort();
    };
    connect(reply, &QNetworkReply::readyRead, this, read);
    connect(reply, &QNetworkReply::finished, this, [this, reply, bytes, read, manual] {
        m_checkReply = nullptr;
        reply->deleteLater();
        bool valid = false;
        Release next;
        if (reply->error() == QNetworkReply::NoError && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 200) {
            read();
            if (bytes->size() <= MaxMetadata) next = parseRelease(*bytes, currentVersion(), valid);
        }
        if (!valid) {
            if (manual) setState(QStringLiteral("error"), tr("Could not verify the latest release on GitHub. Try again or open the releases page."));
            else if (m_state == QStringLiteral("checking")) setState(QStringLiteral("idle"));
            return;
        }
        if (next.version != m_release.version || next.sha256 != m_release.sha256) discardDownload();
        m_release = std::move(next);
        emit releaseChanged();
        setState(version().isEmpty() ? QStringLiteral("current") :
            m_staging ? QStringLiteral("ready") : QStringLiteral("available"));
        if (!m_hintVersion.isEmpty() && !newer(m_hintVersion, version())) {
            m_hintVersion.clear();
            m_hintChecks = 0;
            m_hintCheck.stop();
        }
        if (automatic()) offerRelease();
    });
}

void Updater::offerRelease() {
    if (!automatic() || version().isEmpty() || notificationMode() == QStringLiteral("quiet") ||
        version() == m_offeredVersion || version() == m_settings.value(QStringLiteral("dismissedVersion")).toString()) return;
    if (version() == m_settings.value(QStringLiteral("reminderVersion")).toString() &&
        m_settings.value(QStringLiteral("remindAfter")).toLongLong() > QDateTime::currentMSecsSinceEpoch()) {
        scheduleReminder();
        return;
    }
    m_offeredVersion = version();
    if (notificationMode() == QStringLiteral("notify")) emit nativeNotificationRequested(version());
    emit offerAvailable();
}

void Updater::scheduleReminder() {
    const auto remaining = m_settings.value(QStringLiteral("remindAfter")).toLongLong() - QDateTime::currentMSecsSinceEpoch();
    if (remaining > 0) m_reminder.start(static_cast<int>(qMin<qint64>(remaining, ReminderInterval)));
}

void Updater::remindLater() {
    if (version().isEmpty()) return;
    m_settings.setValue(QStringLiteral("reminderVersion"), version());
    m_settings.setValue(QStringLiteral("remindAfter"), QDateTime::currentMSecsSinceEpoch() + ReminderInterval);
    scheduleReminder();
}

void Updater::dismiss() {
    if (version().isEmpty()) return;
    m_settings.setValue(QStringLiteral("dismissedVersion"), version());
    m_settings.remove(QStringLiteral("reminderVersion"));
    m_settings.remove(QStringLiteral("remindAfter"));
    m_reminder.stop();
}

void Updater::download() {
    if (!m_started || busy() || m_checkReply || version().isEmpty()) return;
    discardDownload();
    const QDir temp(QStandardPaths::writableLocation(QStandardPaths::TempLocation));
    m_staging = std::make_unique<QTemporaryDir>(temp.filePath(QStringLiteral("super-booster-update-XXXXXX")));
    m_installer = std::make_unique<QSaveFile>(m_staging->filePath(m_release.file));
    if (!m_staging->isValid() || !m_installer->open(QIODevice::WriteOnly)) {
        discardDownload();
        setState(QStringLiteral("error"), tr("Could not create a temporary installer file."));
        return;
    }
    m_received = 0;
    m_hasher.reset();
    m_handoffStarted = false;
    setProgress(0);
    setState(QStringLiteral("downloading"));
    requestInstaller(m_release.url, 0);
}

void Updater::requestInstaller(const QUrl& url, int redirects) {
    const auto fail = [this] {
        discardDownload();
        setState(QStringLiteral("error"), tr("The installer could not be downloaded and verified. Try again or open the releases page."));
    };
    if (redirects > 3 || !validDownloadUrl(url, m_release.url)) {
        fail();
        return;
    }
    auto* reply = m_network.get(requestFor(url));
    reply->setReadBufferSize(256 * 1024);
    auto read = [this, reply] {
        if (reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() != 200) {
            reply->readAll();
            return;
        }
        const QByteArray chunk = reply->readAll();
        if (chunk.size() > m_release.size - m_received || m_installer->write(chunk) != chunk.size()) {
            reply->abort();
            return;
        }
        m_hasher.addData(chunk);
        m_received += chunk.size();
        setProgress(static_cast<double>(m_received) / m_release.size);
    };
    connect(reply, &QNetworkReply::readyRead, this, read);
    connect(reply, &QNetworkReply::finished, this, [this, reply, url, redirects, read, fail] {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() != QNetworkReply::NoError) { fail(); return; }
        if (status >= 300 && status < 400) {
            const QUrl target = reply->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl();
            if (target.isEmpty()) { fail(); return; }
            requestInstaller(url.resolved(target), redirects + 1);
            return;
        }
        if (status != 200) { fail(); return; }
        read();
        if (m_received != m_release.size || m_hasher.result() != m_release.sha256 || !m_installer->commit()) {
            fail();
            return;
        }
        m_installer.reset();
        setState(QStringLiteral("ready"));
    });
}

void Updater::install() {
    if (m_state != QStringLiteral("ready") || !m_staging || m_handoffStarted) return;
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString helper = m_staging->filePath(QStringLiteral("super_booster_update_helper.exe"));
    if (!QFile::copy(QDir(appDir).filePath(QStringLiteral("super_booster_update_helper.exe")), helper)) {
        setState(QStringLiteral("error"), tr("The update helper is missing. Install from the releases page."));
        return;
    }
    const auto arguments = QStringList{QString::number(QCoreApplication::applicationPid()), appDir,
        m_staging->filePath(m_release.file), QString::fromLatin1(m_release.sha256.toHex()),
        QString::number(m_release.size), version()};
    if (!QProcess::startDetached(helper, arguments, m_staging->path())) {
        setState(QStringLiteral("error"), tr("Could not start the update installer. Try again or open the releases page."));
        return;
    }
    m_handoffStarted = true;
    m_staging->setAutoRemove(false);
    setState(QStringLiteral("installing"));
    auto* wait = new QTimer(this);
    wait->setInterval(100);
    QElapsedTimer deadline;
    deadline.start();
    connect(wait, &QTimer::timeout, this, [this, wait, deadline] {
        const auto error = m_staging->filePath(QStringLiteral("update-error.txt"));
        if (QFile::exists(error) || deadline.elapsed() >= 15000) {
            wait->deleteLater();
            setState(QStringLiteral("error"), tr("Could not prepare the in-place update. You can install it from the releases page."));
        } else if (QFile::exists(m_staging->filePath(QStringLiteral("update-ready")))) {
            wait->deleteLater();
            QSaveFile confirmation(m_staging->filePath(QStringLiteral("update-confirm")));
            if (!confirmation.open(QIODevice::WriteOnly) || confirmation.write("confirmed\n") != 10 || !confirmation.commit()) {
                setState(QStringLiteral("error"), tr("Could not confirm the update. You can install it from the releases page."));
                return;
            }
            emit installReady();
        }
    });
    wait->start();
}

void Updater::discardDownload() {
    m_installer.reset();
    m_staging.reset();
    m_handoffStarted = false;
    setProgress(0);
}

bool Updater::busy() const {
    return m_state == QStringLiteral("downloading") || m_state == QStringLiteral("installing");
}

void Updater::setState(const QString& state, const QString& error) {
    if (m_state == state && m_error == error) return;
    m_state = state;
    m_error = error;
    emit stateChanged();
}

void Updater::setProgress(double progress) {
    if (qFuzzyCompare(m_progress, progress)) return;
    m_progress = progress;
    emit progressChanged();
}
