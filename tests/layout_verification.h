#pragma once

class QQuickWindow;
class QString;

int verifyMainLayout(QQuickWindow* window, const QString& settingsPath, const QString& expectedStartupLayout);
