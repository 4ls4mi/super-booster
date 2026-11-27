#include "playback_selection.h"

#include <QDebug>

namespace {
QVariantMap device(const char* id, bool media = false, bool console = false, bool communications = false,
                   bool physical = false, bool digital = false) {
    return {{"id", QString::fromLatin1(id)}, {"isDefault", media}, {"isConsoleDefault", console},
        {"isCommunicationsDefault", communications}, {"isPhysicalPlayback", physical}, {"isDigital", digital}};
}

bool expect(const char* label, const QString& actual, const char* expected) {
    if (actual == QString::fromLatin1(expected)) return true;
    qCritical() << label << "expected" << expected << "got" << actual;
    return false;
}
}

int main() {
    using PlaybackSelection::digitalSource;
    using PlaybackSelection::output;

    const QVariantList normal{device("voice", false, true, true, true), device("game", true, false, false, true),
        device("spdif", false, false, false, false, true)};
    const QVariantList routed{device("hdmi"), device("voice", false, false, true, true),
        device("game", false, false, false, true), device("spdif", true, true, false, false, true)};
    const QVariantList twoDigital{device("game", true, true, false, true),
        device("spdif1", false, false, false, false, true), device("spdif2", false, false, false, false, true)};

    bool ok = true;
    ok &= expect("multimedia playback rather than voice", output(normal, {}, {}), "game");
    ok &= expect("saved device remains preferred", output(normal, "voice", {}), "voice");
    ok &= expect("fallback if saved device unplugged", output(normal, "unplugged", {}), "game");
    ok &= expect("Windows default is a capture sink", output(routed, {}, "spdif"), "game");
    ok &= expect("digital source already Windows default", digitalSource(routed, "game"), "spdif");
    ok &= expect("automatic source is separate", digitalSource(normal, "game", true), "spdif");
    ok &= expect("no default when multiple digital sources", digitalSource(twoDigital, "game", true), "");
    ok &= expect("no automatic playback into the capture sink", output({routed.last()}, {}, "spdif"), "");
    ok &= expect("manual capture endpoint is excluded from automatic playback", output(normal, {}, "game"), "voice");
    return ok ? 0 : 1;
}
