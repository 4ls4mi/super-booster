#pragma once

#include <QVariant>
#include <algorithm>

namespace PlaybackSelection {

inline bool available(const QVariantList& outputs, const QString& id) {
    if (id.isEmpty()) return false;
    return std::any_of(outputs.cbegin(), outputs.cend(), [&id](const QVariant& entry) {
        return entry.toMap().value("id").toString() == id;
    });
}

inline QString output(const QVariantList& outputs, const QString& saved, const QString& capture) {
    if (available(outputs, saved)) return saved;

    QString defaultCommunicationsPlayback;
    QString windowsMedia;
    QString windowsConsole;
    QString physical;
    QString other;
    for (const QVariant& entry : outputs) {
        const auto device = entry.toMap();
        const auto id = device.value("id").toString();
        if (id.isEmpty() || id == capture || device.value("isDigital").toBool()) continue;
        const bool media = device.value("isDefault").toBool();
        const bool console = device.value("isConsoleDefault").toBool();
        if (device.value("isCommunicationsDefault").toBool()) {
            if (media || (console && defaultCommunicationsPlayback.isEmpty())) defaultCommunicationsPlayback = id;
            continue;
        }
        if (media) windowsMedia = id;
        if (console) windowsConsole = id;
        if (physical.isEmpty() && device.value("isPhysicalPlayback").toBool()) physical = id;
        if (other.isEmpty()) other = id;
    }
    for (const auto& candidate : {windowsMedia, windowsConsole, physical, defaultCommunicationsPlayback, other}) {
        if (!candidate.isEmpty()) return candidate;
    }
    return {};
}

inline QString digitalSource(const QVariantList& outputs, const QString& playback, bool requireUnique = false) {
    if (!available(outputs, playback)) return {};
    QString first;
    QString windowsDigital;
    for (const QVariant& entry : outputs) {
        const auto device = entry.toMap();
        const auto id = device.value("id").toString();
        if (id.isEmpty() || id == playback || !device.value("isDigital").toBool()) continue;
        if (!first.isEmpty() && requireUnique) return {};
        if (first.isEmpty()) first = id;
        if (device.value("isDefault").toBool() ||
            (windowsDigital.isEmpty() && device.value("isConsoleDefault").toBool())) windowsDigital = id;
    }
    return windowsDigital.isEmpty() ? first : windowsDigital;
}

} // namespace PlaybackSelection
