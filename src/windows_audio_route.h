#pragma once

#include <QLockFile>
#include <QString>

class WindowsAudioRoute {
public:
    explicit WindowsAudioRoute(const QString& recoveryPath);
    bool recover();
    bool start(const QString& source);
    bool stop();
    bool active() const { return !m_source.isEmpty(); }
    QString source() const { return m_source; }

private:
    bool restore();

    QString m_recoveryPath;
    QLockFile m_lock;
    QString m_source;
};
