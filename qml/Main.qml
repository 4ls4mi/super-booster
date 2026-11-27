import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: mainWin
    width: 680
    height: 500
    minimumWidth: 560
    minimumHeight: 430
    visible: false
    color: "#0b0f17"
    title: "Super Booster"
    flags: Qt.Window | Qt.FramelessWindowHint

    onClosing: (close) => {
        if (!screenshotMode) {
            close.accepted = false
            backend.hideMainWindow()
        }
    }

    property int activeTab: 0
    property real shaderTime: 0.0
    property real mouseNormX: 0.5
    property real mouseNormY: 0.5

    property color accentColor: {
        if (!backend.engineActive) return "#38bdf8"
        if (backend.volume > 300) return "#ff6d3b"
        if (backend.volume > 150) return "#38bdf8"
        return "#2ecc71"
    }

    property real avgPeak: Math.min(1.0, Math.max(backend.outputPeakL, backend.outputPeakR))

    FrameAnimation {
        running: mainWin.visible
        onTriggered: mainWin.shaderTime += frameTime
    }

    MiniPopup {
        id: miniPopup
    }

    UpdateNotice {
        id: updateNotice
        anchorWindow: mainWin
        service: updater
    }

    Connections {
        target: backend
        function onAudioSetupRequested() {
            mainWin.activeTab = 2
            settingsScroll.contentItem.contentY = 0
        }
    }

    // Track cursor across main window for subtle glass specular lighting
    HoverHandler {
        onPointChanged: {
            mainWin.mouseNormX = point.position.x / Math.max(1.0, mainWin.width)
            mainWin.mouseNormY = point.position.y / Math.max(1.0, mainWin.height)
        }
    }

    // GPU GLSL Glass & Dynamic Lighting Backdrop
    ShaderEffect {
        id: glassBackdrop
        anchors.fill: parent
        property real u_time: mainWin.shaderTime
        property real u_boostNorm: backend.volume / 500.0
        property real u_peakLevel: mainWin.avgPeak
        property real u_active: backend.engineActive ? 1.0 : 0.0
        property vector2d u_resolution: Qt.vector2d(width, height)
        property vector2d u_mouse: Qt.vector2d(mainWin.mouseNormX, mainWin.mouseNormY)
        fragmentShader: "qrc:/shaders/glass_backdrop.frag.qsb"
    }

    // Crisp outer glass border
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: "#32ffffff"
        border.width: 1
        radius: 12
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // --- Custom Title Bar + Navigation ---
        Item {
            id: titleBar
            Layout.fillWidth: true
            height: 36

            // Keep the navigation and window buttons out of the native drag region.
            Binding {
                target: winHelper
                property: "captionExcludeRight"
                value: mainWin.width - (titleBar.x + navigationTabs.x)
            }

            RowLayout {
                anchors.fill: parent
                spacing: 10

                // Painted speaker emblem
                Rectangle {
                    width: 28; height: 28; radius: 8
                    color: backend.engineActive ? "#282ecc71" : "#2438bdf8"
                    border.color: backend.engineActive ? "#602ecc71" : "#5038bdf8"
                    Canvas {
                        anchors.fill: parent
                        property bool active: backend.engineActive
                        onActiveChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.fillStyle = active ? "#2ecc71" : "#94a3b8"
                            ctx.fillRect(7, 11, 5, 6)
                            ctx.beginPath()
                            ctx.moveTo(11, 11)
                            ctx.lineTo(17, 6)
                            ctx.lineTo(17, 22)
                            ctx.lineTo(11, 17)
                            ctx.closePath()
                            ctx.fill()
                            ctx.strokeStyle = active ? "#2ecc71" : "#ef4444"
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"
                            if (active) {
                                ctx.beginPath()
                                ctx.arc(16, 14, 5, -0.7, 0.7)
                                ctx.stroke()
                            } else {
                                ctx.beginPath()
                                ctx.moveTo(19, 11); ctx.lineTo(23, 17)
                                ctx.moveTo(23, 11); ctx.lineTo(19, 17)
                                ctx.stroke()
                            }
                        }
                    }
                }

                Column {
                    spacing: 0
                    Text {
                        text: "SUPER BOOSTER"
                        color: "#f8fafc"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }
                    Text {
                        text: backend.directMode ? "SYSTEM AUDIO BOOST" : "DEVICE ROUTING MODE"
                        color: "#7dd3fc"
                        font.pixelSize: 9
                        font.letterSpacing: 0.5
                    }
                }

                Item { Layout.fillWidth: true }

                // Segmented Navigation Tabs
                Rectangle {
                    id: navigationTabs
                    height: 30
                    width: tabRow.width + 8
                    radius: 9
                    color: "#22000000"
                    border.color: "#20ffffff"

                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: ["Boost", "App Mixer", "Settings"]
                            Rectangle {
                                height: 24
                                width: tabLbl.implicitWidth + 18
                                radius: 6
                                color: mainWin.activeTab === index ? "#38ffffff"
                                    : tabMouse.containsMouse ? "#20ffffff" : "transparent"
                                Text {
                                    id: tabLbl
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 11
                                    font.weight: mainWin.activeTab === index ? Font.DemiBold : Font.Normal
                                    color: mainWin.activeTab === index ? "#ffffff" : "#cbd5e1"
                                }
                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mainWin.activeTab = index
                                }
                            }
                        }
                    }
                }

                // Window Control Buttons (Minimize, Maximize, Hide to Tray)
                Row {
                    spacing: 6
                    Repeater {
                        model: [
                            { sym: "—", tip: "Minimize", act: "min" },
                            { sym: "□", tip: "Maximize", act: "max" },
                            { sym: "✕", tip: "Hide to Tray", act: "close" }
                        ]
                        Rectangle {
                            width: 26; height: 26; radius: 7
                            color: winBtnMa.containsMouse ? (modelData.act === "close" ? "#55ef4444" : "#28ffffff") : "#14ffffff"
                            Text {
                                anchors.centerIn: parent
                                text: modelData.sym
                                color: "#e2e8f0"
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: winBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.act === "min") winHelper.minimizeWindow()
                                    else if (modelData.act === "max") winHelper.toggleMaximize()
                                    else backend.hideMainWindow()
                                }
                            }
                        }
                    }
                }
            }
        }

        // ==================== TAB 0: BOOST ====================
        ColumnLayout {
            visible: mainWin.activeTab === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // Left Card: Hero GLSL Orb + Big Gain Readout + Power Button
                GlassCard {
                    Layout.preferredWidth: 235
                    Layout.fillHeight: true
                    borderTint: backend.engineActive ? "#452ecc71" : "#28ffffff"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // GPU GLSL Volumetric Audio Orb
                            ShaderEffect {
                                anchors.centerIn: parent
                                width: Math.min(parent.width, parent.height)
                                height: width
                                property real u_time: mainWin.shaderTime
                                property real u_boostNorm: backend.volume / 500.0
                                property real u_peakLevel: mainWin.avgPeak
                                property real u_active: backend.engineActive ? 1.0 : 0.0
                                property real u_superBoost: backend.superBoost ? 1.0 : 0.0
                                fragmentShader: "qrc:/shaders/audio_orb.frag.qsb"
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Math.round(backend.volume) + "%"
                                    color: "#ffffff"
                                    font.pixelSize: 38
                                    font.weight: Font.Bold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: backend.decibelText
                                    color: mainWin.accentColor
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: backend.volume > 300 ? "SUPER OVERDRIVE" : (backend.volume > 100 ? "BOOST" : (backend.volume < 100 ? "ATTENUATION" : "UNITY LEVEL"))
                                    color: "#94a3b8"
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.0
                                }
                            }
                        }

                        // Main Power Toggle Button
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            radius: 10
                            color: backend.engineActive ? (pwrMa.containsMouse ? "#16a34a" : "#22c55e") : (pwrMa.containsMouse ? "#2563eb" : "#1d4ed8")
                            border.color: "#40ffffff"

                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                Rectangle {
                                    width: 9; height: 9; radius: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: backend.engineActive ? "#bbf7d0" : "#bfdbfe"
                                }
                                Text {
                                    text: backend.engineActive ? "BOOST ON — PAUSE"
                                        : backend.engineStarting ? "CONNECTING — CANCEL"
                                        : backend.audioSetupIssue ? "SET UP BOOST" : "START BOOST"
                                    color: "#ffffff"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.6
                                }
                            }
                            MouseArea {
                                id: pwrMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.toggleEngine()
                            }
                        }
                    }
                }

                // Right Column: Slider + Presets + DSP Controls + Live Meters
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    GlassCard {
                        Layout.fillWidth: true
                        implicitHeight: 132

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Amplification Gain"
                                    color: "#f1f5f9"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Hotkeys: Ctrl+Alt+↑/↓/B"
                                    color: "#64748b"
                                    font.pixelSize: 10
                                }
                            }

                            BoostSlider {
                                from: backend.directMode ? 100 : 0
                                Layout.fillWidth: true
                                value: backend.volume
                                accentColor: mainWin.accentColor
                                onMoved: (v) => backend.volume = v
                                onReleased: backend.applyBoostLevel(backend.volume)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: [100, 150, 200, 300, 400, 500]
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 24
                                        radius: 6
                                        color: Math.abs(backend.volume - modelData) < 8 ? "#3538bdf8" : "#16ffffff"
                                        border.color: Math.abs(backend.volume - modelData) < 8 ? "#8038bdf8" : "#22ffffff"
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData + "%"
                                            color: "#e2e8f0"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: backend.applyBoostLevel(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // DSP Toggles: SuperBoost, Soft Limiter, Bass Enhance
                    GlassCard {
                        Layout.fillWidth: true
                        implicitHeight: 92

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 14

                            ColumnLayout {
                                spacing: 10
                                Layout.preferredWidth: 196

                                // Custom Glass Toggle: SuperBoost Clarity
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Rectangle {
                                        width: 34; height: 18; radius: 9
                                        color: backend.superBoost ? "#22c55e" : "#26ffffff"
                                        border.color: backend.superBoost ? "#604ade80" : "#35ffffff"
                                        Rectangle {
                                            width: 14; height: 14; radius: 7
                                            y: 2
                                            x: backend.superBoost ? parent.width - width - 2 : 2
                                            color: "#f8fafc"
                                            Behavior on x { NumberAnimation { duration: 120 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: backend.superBoost = !backend.superBoost
                                        }
                                    }
                                    Text {
                                        text: "SuperBoost Clarity"
                                        color: "#e2e8f0"
                                        font.pixelSize: 11
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: backend.superBoost = !backend.superBoost
                                        }
                                    }
                                }

                                // Custom Glass Toggle: Anti-Clip Soft Limiter
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Rectangle {
                                        width: 34; height: 18; radius: 9
                                        color: backend.limiterEnabled ? "#38bdf8" : "#26ffffff"
                                        border.color: backend.limiterEnabled ? "#707dd3fc" : "#35ffffff"
                                        Rectangle {
                                            width: 14; height: 14; radius: 7
                                            y: 2
                                            x: backend.limiterEnabled ? parent.width - width - 2 : 2
                                            color: "#f8fafc"
                                            Behavior on x { NumberAnimation { duration: 120 } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: backend.limiterEnabled = !backend.limiterEnabled
                                        }
                                    }
                                    Text {
                                        text: "Anti-Clip Soft Limiter"
                                        color: "#e2e8f0"
                                        font.pixelSize: 11
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: backend.limiterEnabled = !backend.limiterEnabled
                                        }
                                    }
                                }
                            }

                            Rectangle { width: 1; Layout.fillHeight: true; color: "#22ffffff" }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Bass Depth"
                                        color: "#e2e8f0"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: Math.round(backend.bassBoost * 100) + "%"
                                        color: "#38bdf8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // Sleek custom Bass Depth slider
                                Item {
                                    Layout.fillWidth: true
                                    height: 22
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 6
                                        radius: 3
                                        color: "#2cffffff"
                                        Rectangle {
                                            height: parent.height
                                            width: Math.max(6, parent.width * backend.bassBoost)
                                            radius: 3
                                            color: "#38bdf8"
                                        }
                                    }
                                    Rectangle {
                                        width: 16; height: 16; radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Math.max(0, Math.min(parent.width - width, backend.bassBoost * (parent.width - width)))
                                        color: "#f8fafc"
                                        border.color: "#38bdf8"
                                        border.width: 2
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        function setBass(mx) {
                                            backend.bassBoost = Math.max(0.0, Math.min(1.0, mx / Math.max(1.0, width)))
                                        }
                                        onPressed: (m) => setBass(m.x)
                                        onPositionChanged: (m) => { if (pressed) setBass(m.x) }
                                    }
                                }
                            }
                        }
                    }

                    // GPU GLSL Spectrum + Stereo Peak Meter
                    GlassCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "LIVE SPECTRUM & OUTPUT PEAK"
                                    color: "#94a3b8"
                                    font.pixelSize: 10
                                    font.letterSpacing: 0.6
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: backend.limiterReduction > 0.03 ? "LIMITER ENGAGED" : (mainWin.avgPeak > 0.002 ? "SIGNAL" : "STANDBY")
                                    color: backend.limiterReduction > 0.03 ? "#fb923c" : "#4ade80"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }

                            // 24-Band Live Spectrum Bars with GLSL bloom backdrop
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ShaderEffect {
                                    anchors.fill: parent
                                    property real u_time: mainWin.shaderTime
                                    property real u_boostNorm: backend.volume / 500.0
                                    property real u_peakLevel: mainWin.avgPeak
                                    property real u_active: backend.engineActive ? 1.0 : 0.0
                                    property real u_limiterHit: Math.min(1.0, backend.limiterReduction * 3.0)
                                    fragmentShader: "qrc:/shaders/spectrum_glow.frag.qsb"
                                }

                                Row {
                                    anchors.fill: parent
                                    spacing: 4
                                    Repeater {
                                        model: 24
                                        Item {
                                            width: Math.max(4, (parent.width - 23 * 4) / 24)
                                            height: parent.height
                                            property real val: {
                                                var arr = backend.spectrumBands
                                                return arr && index < arr.length ? arr[index] : 0
                                            }
                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                width: parent.width
                                                height: Math.max(4, parent.height * Math.min(1.0, parent.val))
                                                radius: 3
                                                gradient: Gradient {
                                                    GradientStop { position: 0.0; color: backend.volume > 300 ? "#fb923c" : "#38bdf8" }
                                                    GradientStop { position: 1.0; color: "#2ecc71" }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Stereo L/R Peak Bars
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text { text: "L"; color: "#94a3b8"; font.pixelSize: 10; font.weight: Font.DemiBold }
                                Rectangle {
                                    Layout.fillWidth: true; height: 5; radius: 2.5; color: "#20ffffff"
                                    Rectangle {
                                        height: parent.height; radius: 2.5
                                        width: parent.width * Math.min(1.0, backend.outputPeakL)
                                        color: backend.outputPeakL > 0.9 ? "#f97316" : "#2ecc71"
                                    }
                                }
                                Text { text: "R"; color: "#94a3b8"; font.pixelSize: 10; font.weight: Font.DemiBold }
                                Rectangle {
                                    Layout.fillWidth: true; height: 5; radius: 2.5; color: "#20ffffff"
                                    Rectangle {
                                        height: parent.height; radius: 2.5
                                        width: parent.width * Math.min(1.0, backend.outputPeakR)
                                        color: backend.outputPeakR > 0.9 ? "#f97316" : "#2ecc71"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ==================== TAB 1: APP MIXER ====================
        GlassCard {
            visible: mainWin.activeTab === 1
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Column {
                        Text {
                            text: "Active Windows Audio Sessions"
                            color: "#f8fafc"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                        Text {
                            text: "Balance individual apps directly through Windows WASAPI (no virtual cable required)"
                            color: "#94a3b8"
                            font.pixelSize: 11
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: "Refresh"
                        onClicked: backend.refreshSessions()
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: backend.audioSessions

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 54
                        radius: 10
                        color: "#1cffffff"
                        border.color: "#22ffffff"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Column {
                                Layout.preferredWidth: 160
                                Text {
                                    text: modelData.name || "Audio App"
                                    color: "#f1f5f9"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Rectangle {
                                    width: 120; height: 4; radius: 2; color: "#20ffffff"
                                    Rectangle {
                                        height: 4; radius: 2
                                        width: parent.width * Math.min(1.0, modelData.peak || 0)
                                        color: "#2ecc71"
                                    }
                                }
                            }

                            Slider {
                                Layout.fillWidth: true
                                from: 0.0; to: 1.0
                                value: modelData.volume !== undefined ? modelData.volume : 1.0
                                onMoved: backend.setSessionVolume(modelData.pid, value)
                            }

                            Text {
                                Layout.preferredWidth: 42
                                text: Math.round((modelData.volume || 0) * 100) + "%"
                                color: "#cbd5e1"
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignRight
                            }

                            Button {
                                text: modelData.muted ? "Unmute" : "Mute"
                                onClicked: backend.setSessionMute(modelData.pid, !modelData.muted)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: parent.count === 0
                        text: "No active audio apps detected right now.\nPlay audio in a browser, game, or media player to see it here."
                        color: "#64748b"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        // ==================== TAB 2: SETTINGS ====================
        GlassCard {
            visible: mainWin.activeTab === 2
            Layout.fillWidth: true
            Layout.fillHeight: true

            ScrollView {
                id: settingsScroll
                anchors.fill: parent
                anchors.margins: 16
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "Audio Engine & Device Setup"
                            color: "#f8fafc"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                        Button {
                            objectName: "jumpToUpdateSettings"
                            text: qsTr("Updates")
                            onClicked: {
                                const view = settingsScroll.contentItem
                                view.contentY = Math.min(updateSettings.y,
                                                         Math.max(0, view.contentHeight - view.height))
                            }
                        }
                    }

                    Text {
                        visible: backend.audioSetupIssue !== ""
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: backend.audioSetupIssue
                        color: "#fbbf24"
                        font.pixelSize: 12
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        RadioButton {
                            checked: backend.directMode
                            text: "System Audio Boost"
                            palette.windowText: "#e2e8f0"
                            onClicked: backend.directMode = true
                        }
                        RadioButton {
                            checked: !backend.directMode
                            text: "Device Routing (Input → Output)"
                            palette.windowText: "#e2e8f0"
                            onClicked: backend.directMode = false
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            text: "Playback Speakers:"
                            color: "#cbd5e1"
                            Layout.preferredWidth: 130
                        }
                        ComboBox {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            model: {
                                const name = backend.automaticPlaybackOutputName
                                const devices = [{ id: "", name: name
                                    ? "Automatic playback (" + name + ")"
                                    : "Automatic playback (no suitable device)" }]
                                for (const device of backend.outputDevices) devices.push(device)
                                return devices
                            }
                            textRole: "name"
                            valueRole: "id"
                            currentIndex: {
                                for (var i = 0; i < model.length; ++i) {
                                    if (model[i].id === backend.selectedOutDevice) return i
                                }
                                return -1
                            }
                            displayText: currentIndex < 0
                                ? (backend.automaticPlaybackOutputName
                                    ? "Using " + backend.automaticPlaybackOutputName + " (saved device unavailable)"
                                    : "Saved device unavailable")
                                : currentText
                            ToolTip.visible: hovered && displayText !== ""
                            ToolTip.text: displayText
                            onActivated: backend.selectedOutDevice = currentValue
                        }
                        Button {
                            text: "Refresh"
                            onClicked: backend.refreshDevices()
                        }
                    }

                    Text {
                        visible: backend.selectedOutDevice !== ""
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: backend.windowsOutputName
                            ? "Windows default output is " + backend.windowsOutputName
                            : "Windows has no default playback device."
                        color: "#cbd5e1"
                        font.pixelSize: 12
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: backend.directMode
                        spacing: 10
                        Text {
                            text: "Silent Audio Source:"
                            color: "#cbd5e1"
                            Layout.preferredWidth: 130
                        }
                        ComboBox {
                            Layout.fillWidth: true
                            model: {
                                const digital = backend.digitalSourceName
                                const devices = [{ id: "", name: "Choose a source" },
                                                 { id: "windows-digital", name: digital
                                                     ? "Automatic Digital Output (" + digital + ")"
                                                     : "Automatic Digital Output (unavailable)" }]
                                for (const device of backend.outputDevices) devices.push(device)
                                return devices
                            }
                            textRole: "name"
                            valueRole: "id"
                            currentIndex: {
                                for (let i = 0; i < model.length; i++) {
                                    if (model[i].id === backend.selectedSourceDevice) return i
                                }
                                return -1
                            }
                            displayText: currentIndex < 0 ? "Saved source unavailable" : currentText
                            ToolTip.visible: hovered && displayText !== ""
                            ToolTip.text: displayText
                            onActivated: backend.selectedSourceDevice = currentValue
                        }
                    }

                    Text {
                        visible: backend.directMode
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: "#cbd5e1"
                        font.pixelSize: 12
                        text: backend.selectedSourceDevice === "windows-digital"
                            ? "Use this if nothing is plugged into your PC’s digital audio port. Boost routes Windows’ default media audio through that output and plays it through your speakers or headphones. Pausing restores the previous Windows outputs. Apps with their own output setting may need to use Windows default."
                            : "Choose Automatic Digital Output to use an unused digital audio port with no install. For a manually selected source, assign your apps to that device in Windows Volume Mixer."
                    }

                    RowLayout {
                        visible: backend.directMode
                        Button {
                            text: "Open Windows Volume Mixer"
                            onClicked: Qt.openUrlExternally("ms-settings:apps-volume")
                        }
                        Button {
                            text: backend.engineActive ? "Pause Boost"
                                : backend.engineStarting ? "Cancel Boost" : "Start Boost"
                            enabled: backend.audioSetupIssue === "" || backend.engineActive || backend.engineStarting
                            onClicked: backend.toggleEngine()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: !backend.directMode
                        spacing: 10
                        Text {
                            text: "Capture Input:"
                            color: "#cbd5e1"
                            Layout.preferredWidth: 130
                        }
                        ComboBox {
                            Layout.fillWidth: true
                            model: backend.inputDevices
                            textRole: "name"
                            valueRole: "id"
                            currentIndex: {
                                for (var i = 0; i < backend.inputDevices.length; ++i) {
                                    if (backend.inputDevices[i].id === backend.selectedInDevice) return i
                                }
                                return 0
                            }
                            onActivated: backend.selectedInDevice = currentValue
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            text: "Windows Master:"
                            color: "#cbd5e1"
                            Layout.preferredWidth: 130
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: backend.masterVolume
                            onMoved: backend.setMasterVolume(value)
                        }
                        Text {
                            text: Math.round(backend.masterVolume) + "%"
                            color: "#38bdf8"
                            Layout.preferredWidth: 42
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#20ffffff" }

                    Text {
                        text: "Windows Integration"
                        color: "#f8fafc"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }

                    CheckBox {
                        checked: backend.autostart
                        text: "Start automatically with Windows (minimized to tray)"
                        palette.windowText: "#e2e8f0"
                        onClicked: backend.autostart = checked
                    }
                    CheckBox {
                        checked: backend.hotkeysEnabled
                        text: "Enable global Windows hotkeys (Ctrl+Alt+Up, Ctrl+Alt+Down, Ctrl+Alt+B)"
                        palette.windowText: "#e2e8f0"
                        onClicked: backend.hotkeysEnabled = checked
                    }
                    CheckBox {
                        checked: backend.showTrayMsg
                        text: "Show tray notification when minimized"
                        palette.windowText: "#e2e8f0"
                        onClicked: backend.showTrayMsg = checked
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        Button {
                            text: "Open Mini Tray Slider"
                            onClicked: backend.togglePopup()
                        }
                        Button {
                            text: "Quit Completely"
                            onClicked: backend.quitApp()
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#20ffffff" }

                    ColumnLayout {
                        id: updateSettings
                        objectName: "superBoosterUpdateSettings"
                        Layout.fillWidth: true
                        spacing: 9

                        Text {
                            text: qsTr("Updates")
                            color: "#f8fafc"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Installed version %1 · %2").arg(updater.currentVersion).arg(updateNotice.statusText)
                            color: "#a7b8ce"
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                        }
                        CheckBox {
                            objectName: "superBoosterAutomaticUpdateChecks"
                            enabled: updater.supported
                            checked: updater.automatic
                            text: qsTr("Check for updates automatically")
                            palette.windowText: "#e2e8f0"
                            onToggled: updater.automatic = checked
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Label {
                                text: qsTr("Notify me using")
                                color: "#cbd5e1"
                            }
                            ComboBox {
                                objectName: "superBoosterUpdateNotificationMode"
                                Layout.fillWidth: true
                                enabled: updater.supported && updater.automatic
                                textRole: "label"
                                valueRole: "id"
                                model: [
                                    { label: qsTr("Quiet · check without a notification"), id: "quiet" },
                                    { label: qsTr("Corner popup"), id: "toast" },
                                    { label: qsTr("Windows notification and corner popup"), id: "notify" },
                                    { label: qsTr("Update details window"), id: "dialog" }
                                ]
                                currentIndex: Math.max(0, indexOfValue(updater.notificationMode))
                                onActivated: updater.notificationMode = currentValue
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                objectName: "checkForSuperBoosterUpdates"
                                text: qsTr("Check now")
                                enabled: updater.supported && !updateNotice.busy
                                onClicked: updateNotice.checkNow()
                            }
                            Button {
                                objectName: "openSuperBoosterUpdateDetails"
                                text: updateNotice.busy ? qsTr("View progress") : qsTr("Details")
                                enabled: updater.supported
                                onClicked: updateNotice.showDetails()
                            }
                            Button {
                                text: qsTr("GitHub releases")
                                onClicked: updateNotice.openReleases()
                            }
                        }
                    }
                }
            }
        }

        // --- Bottom Status Bar + Resize Grip ---
        RowLayout {
            Layout.fillWidth: true
            height: 20
            spacing: 8

            Rectangle {
                width: 7; height: 7; radius: 4
                color: backend.engineActive ? "#2ecc71" : "#64748b"
            }
            Text {
                text: backend.statusMessage
                color: "#94a3b8"
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            // Subtle bottom-right resize handle indicator
            Text {
                text: "◢"
                color: "#5094a3b8"
                font.pixelSize: 11
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeFDiagCursor
                    onPressed: winHelper.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
                }
            }
        }
    }
}
