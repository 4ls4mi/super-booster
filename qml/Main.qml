pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "FractureLayout.js" as FractureLayout

Window {
    id: mainWin
    width: Math.min(1020, Screen.desktopAvailableWidth)
    height: Math.min(610, Screen.desktopAvailableHeight)
    minimumWidth: Math.min(860, Screen.desktopAvailableWidth)
    minimumHeight: Math.min(550, Screen.desktopAvailableHeight)
    visible: false
    color: "transparent"
    title: "Super Booster"
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint

    property int activeTab: 0
    property bool menuOpen: screenshotMenuOpen
    readonly property var panelLayout: FractureLayout.arrange(width, height)
    readonly property string material: screenshotMode && screenshotMaterial.length > 0
        ? screenshotMaterial : backend.appearanceMaterial
    readonly property color accentColor: backend.volume > 300 ? "#ff9c76" : "#8ffbd0"
    readonly property bool hiddenForUpdate: (!visible || visibility === Window.Minimized)
        && !miniPopup.visible && !updateNotice.detailsVisible
    readonly property bool silentIdleCandidate: hiddenForUpdate && backend.engineActive
        && Math.max(backend.inputPeakL, backend.inputPeakR, backend.outputPeakL, backend.outputPeakR) < 0.001
    property bool quietForUpdate: false

    onClosing: (close) => {
        if (!screenshotMode) {
            close.accepted = false
            menuOpen = false
            backend.hideMainWindow()
        }
    }

    palette.windowText: "#f3fbff"
    palette.text: "#f3fbff"
    palette.buttonText: "#f3fbff"
    palette.window: "#282238"
    palette.button: "#3d344c"
    palette.base: "#2e263e"
    palette.alternateBase: "#3e3352"
    palette.highlight: "#54d8bd"
    palette.highlightedText: "#052b2a"
    palette.mid: "#746986"
    palette.light: "#a497b1"
    palette.dark: "#211c2d"

    function updateShardGeometry() {
        const surface = [brandShard, commandShard, mixer, settings, appearance].concat(boost.shards)
        const polygons = surface.filter(shard => shard.visible && shard.width > 0 && shard.height > 0)
            .map(shard => shard.windowPolygon())
        winHelper.setShardGeometry(polygons)
    }

    function queueGeometry() {
        Qt.callLater(updateShardGeometry)
    }

    Component.onCompleted: {
        winHelper.titleBarHeight = 0
        queueGeometry()
    }
    onVisibleChanged: queueGeometry()
    onActiveTabChanged: queueGeometry()
    onMenuOpenChanged: queueGeometry()
    onWidthChanged: queueGeometry()
    onHeightChanged: queueGeometry()

    MiniPopup { id: miniPopup }

    UpdateNotice {
        id: updateNotice
        anchorWindow: mainWin
        service: updater
    }

    onSilentIdleCandidateChanged: {
        if (!silentIdleCandidate) quietForUpdate = false
    }

    Timer {
        interval: 30000
        running: mainWin.silentIdleCandidate && updater.autoInstallUpdates
        onTriggered: mainWin.quietForUpdate = true
    }

    Binding {
        target: updater
        property: "backgroundInstallAllowed"
        value: !screenshotMode && mainWin.hiddenForUpdate && !backend.engineStarting
            && (!backend.engineActive || mainWin.quietForUpdate)
    }

    Connections {
        target: backend
        function onAudioSetupRequested() {
            mainWin.activeTab = 2
            mainWin.menuOpen = false
            settingsScroll.contentItem.contentY = 0
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: mainWin.menuOpen
        onActivated: mainWin.menuOpen = false
    }

    component Pane: GlassShard {
        required property var pane
        x: pane.x
        y: pane.y
        width: pane.width
        height: pane.height
        points: pane.points
        material: mainWin.material
        onGeometryChanged: mainWin.queueGeometry()
    }

    component HeaderButton: ToolButton {
        id: control

        required property string iconName
        property bool tabButton: false
        readonly property color foreground: checked ? mainWin.accentColor : "#f8f5fc"

        implicitWidth: text.length ? Math.ceil(buttonContents.implicitWidth + 14) : 32
        implicitHeight: 35
        padding: 7
        font.pixelSize: 16

        contentItem: Item {
            implicitWidth: buttonContents.implicitWidth

            Row {
                id: buttonContents
                anchors.centerIn: parent
                spacing: 7

                LineIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: control.iconName === "close" ? 20 : 18
                    height: width
                    name: control.iconName
                    color: control.foreground
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: control.text.length > 0
                    text: control.text
                    color: control.foreground
                    font: control.font
                }
            }
        }

        background: Rectangle {
            radius: 6
            color: control.down ? "#504b2258" : control.hovered ? "#28ffffff" : "transparent"
            border.color: control.visualFocus ? "#a1fadc" : "transparent"

            Rectangle {
                visible: control.tabButton && control.checked
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 7
                height: 2
                radius: 1
                color: mainWin.accentColor
            }
        }
    }

    Pane {
        id: brandShard
        objectName: "superBoosterBrandShard"
        pane: mainWin.panelLayout.brand

        RowLayout {
            x: brandShard.pane.content.x
            y: brandShard.pane.content.y
            width: brandShard.pane.content.width
            height: brandShard.pane.content.height
            spacing: 12

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Label {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("SUPER BOOSTER")
                    color: "#fcf8ff"
                    font.pixelSize: Math.min(29, mainWin.width * 0.024)
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                DragHandler {
                    target: null
                    onActiveChanged: if (active) winHelper.startSystemMove()
                }
                TapHandler { onDoubleTapped: winHelper.toggleMaximize() }
            }

            HeaderButton {
                text: qsTr("Boost")
                iconName: "boost"
                tabButton: true
                checked: mainWin.activeTab === 0
                onClicked: mainWin.activeTab = 0
            }
            HeaderButton {
                text: qsTr("App Mixer")
                iconName: "mixer"
                tabButton: true
                checked: mainWin.activeTab === 1
                onClicked: mainWin.activeTab = 1
            }
        }
    }

    Pane {
        id: commandShard
        objectName: "superBoosterCommandShard"
        pane: mainWin.panelLayout.commands

        RowLayout {
            x: commandShard.pane.content.x
            y: commandShard.pane.content.y
            width: commandShard.pane.content.width
            height: commandShard.pane.content.height
            spacing: 1

            HeaderButton {
                objectName: "superBoosterMainMenu"
                text: qsTr("Menu")
                iconName: "menu"
                Accessible.name: text
                checked: mainWin.menuOpen
                onClicked: mainWin.menuOpen = !mainWin.menuOpen
            }
            Item { Layout.fillWidth: true }
            HeaderButton {
                iconName: "minimize"
                Accessible.name: qsTr("Minimize")
                onClicked: winHelper.minimizeWindow()
            }
            HeaderButton {
                iconName: mainWin.visibility === Window.Maximized ? "restore" : "maximize"
                Accessible.name: mainWin.visibility === Window.Maximized ? qsTr("Restore") : qsTr("Maximize")
                onClicked: winHelper.toggleMaximize()
            }
            HeaderButton {
                iconName: "close"
                Accessible.name: qsTr("Hide to tray")
                onClicked: mainWin.close()
            }
        }
    }

    BoostView {
        id: boost
        anchors.fill: parent
        visible: mainWin.activeTab === 0
        panelLayout: mainWin.panelLayout
        audio: backend
        material: mainWin.material
        accent: mainWin.accentColor
        resizeEnabled: mainWin.visibility !== Window.Maximized && mainWin.visibility !== Window.FullScreen
        onShardGeometryChanged: mainWin.queueGeometry()
        onResizeRequested: (width, height) => winHelper.resizeFromGrip(width, height)
    }

    Pane {
        id: mixer
        visible: mainWin.activeTab === 1
        pane: mainWin.panelLayout.pages

        ColumnLayout {
            x: mixer.pane.content.x
            y: mixer.pane.content.y
            width: mixer.pane.content.width
            height: mixer.pane.content.height
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
                    id: sessionCard
                    required property var modelData

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
                                text: sessionCard.modelData.name || "Audio App"
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
                                    width: parent.width * Math.min(1.0, sessionCard.modelData.peak || 0)
                                    color: "#2ecc71"
                                }
                            }
                        }

                        Slider {
                            Layout.fillWidth: true
                            from: 0.0; to: 1.0
                            value: sessionCard.modelData.volume ?? 1.0
                            onMoved: backend.setSessionVolume(sessionCard.modelData.pid, value)
                        }

                        Text {
                            Layout.preferredWidth: 42
                            text: Math.round((sessionCard.modelData.volume || 0) * 100) + "%"
                            color: "#cbd5e1"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignRight
                        }

                        Button {
                            text: sessionCard.modelData.muted ? "Unmute" : "Mute"
                            onClicked: backend.setSessionMute(sessionCard.modelData.pid, !sessionCard.modelData.muted)
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

    Pane {
        id: settings
        visible: mainWin.activeTab === 2
        pane: mainWin.panelLayout.pages

        ScrollView {
            id: settingsScroll
            x: settings.pane.content.x
            y: settings.pane.content.y
            width: settings.pane.content.width
            height: settings.pane.content.height
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
                        popup.popupType: Popup.Window
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
                        popup.popupType: Popup.Window
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
                        popup.popupType: Popup.Window
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

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#20ffffff" }

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

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#20ffffff" }

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
                        enabled: updater.supported && !updater.autoInstallUpdates
                        checked: updater.automatic || updater.autoInstallUpdates
                        text: qsTr("Check for updates automatically")
                        palette.windowText: "#e2e8f0"
                        onClicked: updater.automatic = checked
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
                            popup.popupType: Popup.Window
                            Layout.fillWidth: true
                            enabled: updater.supported && updater.automatic && !updater.autoInstallUpdates
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
                            onClicked: Qt.openUrlExternally("https://github.com/4ls4mi/super-booster/releases/latest")
                        }
                    }
                }
            }
        }
    }

    AppearanceMenu {
        id: appearance
        objectName: "superBoosterAppearanceShard"
        visible: mainWin.menuOpen
        pane: mainWin.panelLayout.appearance
        material: mainWin.material
        updateService: updater
        onGeometryChanged: mainWin.queueGeometry()
        onMaterialSelected: materialId => backend.appearanceMaterial = materialId
        onAudioSettingsRequested: {
            mainWin.activeTab = 2
            mainWin.menuOpen = false
            settingsScroll.contentItem.contentY = 0
        }
    }
}
