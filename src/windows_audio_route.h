#pragma once

#include <QLockFile>
#include <QString>

class WindowsAudioRoute {
public:
    enum class Recovery { None, Restored, Unavailable };

    explicit WindowsAudioRoute(const QString& recoveryPath);
    Recovery recover();
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
