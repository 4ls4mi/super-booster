pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "FractureLayout.js" as FractureLayout

Window {
    id: mainWin
    width: Math.min(1020, Screen.desktopAvailableWidth)
    height: Math.min(610, Screen.desktopAvailableHeight)
    minimumWidth: Math.min(classic ? 560 : 860, Screen.desktopAvailableWidth)
    minimumHeight: Math.min(classic ? 430 : 550, Screen.desktopAvailableHeight)
    visible: false
    color: "transparent"
    title: "Super Booster"
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint

    property int activeTab: 0
    property bool menuOpen: screenshotMenuOpen
    readonly property string layoutMode: screenshotMode && screenshotLayout.length > 0
        ? screenshotLayout : backend.appearanceLayout
    readonly property bool classic: layoutMode === "classic"
    readonly property var panelLayout: FractureLayout.arrange(width, height)
    readonly property string material: classic ? "acrylic" : screenshotMode && screenshotMaterial.length > 0
        ? screenshotMaterial : backend.appearanceMaterial
    readonly property rect classicBodyBounds: Qt.rect(14, 62, width - 28, height - 104)
    readonly property var classicPagePane: classicPane(classicBodyBounds, 14)
    readonly property var classicMenuPane: classicPane(Qt.rect(width - 252, 61, 238, 225), 13)
    property size glassWindowSize: Qt.size(1020, 610)
    property size classicWindowSize: Qt.size(680, 500)
    readonly property bool resizeEnabled: visibility === Window.Windowed
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
        const surface = classic ? [classicSurface]
            : [brandShard, commandShard, mixer, settings, appearance].concat(boost.shards)
        const polygons = surface.filter(shard => shard.visible && shard.width > 0 && shard.height > 0)
            .map(shard => shard.windowPolygon())
        winHelper.setShardGeometry(polygons)
    }

    function queueGeometry() {
        Qt.callLater(updateShardGeometry)
    }

    function roundedPoints(width, height, radius) {
        if (width <= 2 || height <= 2)
            return []
        radius = Math.min(radius, (width - 2) / 2, (height - 2) / 2)
        const centers = [[width - 2 - radius, radius], [width - 2 - radius, height - 2 - radius],
                         [radius, height - 2 - radius], [radius, radius]]
        const points = []
        for (let corner = 0; corner < centers.length; ++corner) {
            const center = centers[corner]
            for (let step = 0; step <= 4; ++step) {
                const angle = (corner - 1 + step / 4) * Math.PI / 2
                points.push(Qt.point((center[0] + Math.cos(angle) * radius) / (width - 2),
                                     (center[1] + Math.sin(angle) * radius) / (height - 2)))
            }
        }
        return points
    }

    function classicPane(bounds, inset) {
        return {
            x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height,
            points: roundedPoints(bounds.width, bounds.height, 12),
            content: Qt.rect(inset, inset, bounds.width - 2 * inset, bounds.height - 2 * inset)
        }
    }

    function selectLayout(layout) {
        if (layout === layoutMode)
            return

        const windowed = visibility === Window.Windowed
        if (windowed) {
            const currentSize = Qt.size(width, height)
            if (classic)
                classicWindowSize = currentSize
            else
                glassWindowSize = currentSize
        }

        menuOpen = false
        backend.appearanceLayout = layout
        if (windowed) Qt.callLater(restoreLayoutSize)
    }

    function restoreLayoutSize() {
        if (visibility === Window.Windowed) {
            const size = classic ? classicWindowSize : glassWindowSize
            const workArea = backend.mainWindowWorkArea
            width = Math.min(size.width, workArea.width)
            height = Math.min(size.height, workArea.height)
            x = Math.max(workArea.x, Math.min(x, workArea.x + workArea.width - width))
            y = Math.max(workArea.y, Math.min(y, workArea.y + workArea.height - height))
        }
    }

    function openSettings(showUpdates) {
        activeTab = 2
        menuOpen = false
        if (showUpdates)
            Qt.callLater(settingsScroll.showUpdateSettings)
        else
            settingsScroll.scrollTo(0)
    }

    Component.onCompleted: {
        winHelper.titleBarHeight = 0
        if (classic) {
            width = Math.min(classicWindowSize.width, Screen.desktopAvailableWidth)
            height = Math.min(classicWindowSize.height, Screen.desktopAvailableHeight)
        }
        queueGeometry()
    }
    onVisibleChanged: queueGeometry()
    onActiveTabChanged: queueGeometry()
    onMenuOpenChanged: queueGeometry()
    onLayoutModeChanged: queueGeometry()
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

    Binding {
        target: winHelper
        property: "wallpaperSamplingEnabled"
        value: mainWin.material === "blurred" || mainWin.material === "acrylic" || mainWin.material === "mica"
    }

    Connections {
        target: backend
        function onAudioSetupRequested() { mainWin.openSettings(false) }
    }

    Shortcut {
        sequence: "Escape"
        enabled: mainWin.menuOpen
        onActivated: mainWin.menuOpen = false
    }

    component Pane: GlassShard {
        id: paneSurface
        required property var pane
        property bool classicCard: false
        x: pane.x
        y: pane.y
        width: pane.width
        height: pane.height
        points: pane.points
        material: mainWin.material
        paintFace: !classicCard
        onGeometryChanged: mainWin.queueGeometry()

        Rectangle {
            anchors.fill: parent
            visible: paneSurface.classicCard
            radius: 14
            color: "#50202838"
            border.color: "#407c9eb0"
        }
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

    component SettingCheckBox: CheckBox {
        id: control

        Layout.fillWidth: true
        Layout.minimumWidth: 0
        palette.windowText: "#e2e8f0"

        contentItem: Label {
            leftPadding: control.mirrored ? 0 : control.indicator.width + control.spacing
            rightPadding: control.mirrored ? control.indicator.width + control.spacing : 0
            text: control.text
            font: control.font
            color: control.palette.windowText
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    component ClassicHeaderButton: ToolButton {
        id: control

        property string iconName: ""
        property bool windowCommand: false

        implicitWidth: iconName.length ? 26 : implicitContentWidth + 14
        implicitHeight: windowCommand ? 26 : 24
        horizontalPadding: 7
        verticalPadding: 3
        font.pixelSize: 11
        font.weight: checked ? Font.DemiBold : Font.Normal

        contentItem: Item {
            implicitWidth: caption.implicitWidth

            Label {
                id: caption
                anchors.centerIn: parent
                text: control.text
                font: control.font
                color: control.checked ? "#ffffff" : "#dbeaf3"
                visible: !control.iconName.length
            }

            LineIcon {
                anchors.centerIn: parent
                width: 14
                height: 14
                name: control.iconName
                color: "#dbeaf3"
                visible: control.iconName.length > 0
            }
        }

        background: Rectangle {
            radius: 6
            color: control.iconName === "close" && control.hovered ? "#55ef4444"
                : control.down || control.checked ? "#42ffffff"
                : control.hovered ? "#27ffffff" : control.windowCommand ? "#16ffffff" : "transparent"
            border.color: control.visualFocus ? "#a4e6fa" : "transparent"
        }
    }

    GlassShard {
        id: classicSurface
        objectName: "superBoosterClassicSurface"
        anchors.fill: parent
        visible: mainWin.classic
        material: mainWin.material
        points: mainWin.roundedPoints(width, height, 13)
        onGeometryChanged: mainWin.queueGeometry()
    }

    RowLayout {
        id: classicHeader
        visible: mainWin.classic
        x: 14
        y: 14
        width: mainWin.width - 28
        height: 36
        spacing: 8

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 8
                    color: backend.engineActive ? "#282ecc71" : "#2438bdf8"
                    border.color: backend.engineActive ? "#602ecc71" : "#5038bdf8"

                    LineIcon {
                        anchors.centerIn: parent
                        width: 21
                        height: 21
                        name: backend.engineActive ? "output" : "muted"
                        color: backend.engineActive ? "#2ecc71" : "#a8c5d6"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("SUPER BOOSTER")
                        color: "#f8fafc"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: backend.directMode ? qsTr("SYSTEM AUDIO BOOST") : qsTr("DEVICE ROUTING MODE")
                        color: "#9bdef9"
                        font.pixelSize: 9
                        font.letterSpacing: 0.5
                        elide: Text.ElideRight
                    }
                }
            }

            DragHandler {
                target: null
                onActiveChanged: if (active) winHelper.startSystemMove()
            }
            TapHandler { onDoubleTapped: winHelper.toggleMaximize() }
        }

        Rectangle {
            Layout.preferredWidth: classicTabs.implicitWidth + 8
            Layout.preferredHeight: 30
            radius: 9
            color: "#22000000"
            border.color: "#38c2e0ec"

            Row {
                id: classicTabs
                anchors.centerIn: parent
                spacing: 3

                ClassicHeaderButton {
                    text: qsTr("Boost")
                    checked: mainWin.activeTab === 0
                    onClicked: {
                        mainWin.menuOpen = false
                        mainWin.activeTab = 0
                    }
                }
                ClassicHeaderButton {
                    text: qsTr("App Mixer")
                    checked: mainWin.activeTab === 1
                    onClicked: {
                        mainWin.menuOpen = false
                        mainWin.activeTab = 1
                    }
                }
                ClassicHeaderButton {
                    text: qsTr("Settings")
                    checked: mainWin.activeTab === 2
                    onClicked: mainWin.openSettings(false)
                }
            }
        }

        ClassicHeaderButton {
            objectName: "superBoosterClassicMenu"
            text: qsTr("Appearance")
            windowCommand: true
            checked: mainWin.menuOpen
            onClicked: mainWin.menuOpen = !mainWin.menuOpen
        }

        Row {
            spacing: 5

            ClassicHeaderButton {
                iconName: "minimize"
                windowCommand: true
                Accessible.name: qsTr("Minimize")
                onClicked: winHelper.minimizeWindow()
            }
            ClassicHeaderButton {
                iconName: mainWin.visibility === Window.Maximized ? "restore" : "maximize"
                windowCommand: true
                Accessible.name: mainWin.visibility === Window.Maximized ? qsTr("Restore") : qsTr("Maximize")
                onClicked: winHelper.toggleMaximize()
            }
            ClassicHeaderButton {
                iconName: "close"
                windowCommand: true
                Accessible.name: qsTr("Hide to tray")
                onClicked: mainWin.close()
            }
        }
    }

    ClassicBoostView {
        visible: mainWin.classic && mainWin.activeTab === 0
        x: mainWin.classicBodyBounds.x
        y: mainWin.classicBodyBounds.y
        width: mainWin.classicBodyBounds.width
        height: mainWin.classicBodyBounds.height
        audio: backend
    }

    RowLayout {
        x: 14
        y: mainWin.height - 31
        width: mainWin.width - 28
        height: 20
        spacing: 8
        visible: mainWin.classic

        Rectangle {
            implicitWidth: 7
            implicitHeight: 7
            radius: 4
            color: backend.engineActive ? "#2ecc71" : "#8daabb"
        }
        Label {
            Layout.fillWidth: true
            color: "#b4cbd8"
            text: backend.statusMessage
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        MouseArea {
            id: classicGrip
            objectName: "superBoosterClassicResizeGrip"
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            enabled: mainWin.resizeEnabled
            cursorShape: Qt.SizeFDiagCursor

            property point dragOrigin
            property size windowSizeAtPress

            onPressed: mouse => {
                dragOrigin = mapToGlobal(mouse.x, mouse.y)
                windowSizeAtPress = Qt.size(mainWin.width, mainWin.height)
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return
                const position = mapToGlobal(mouse.x, mouse.y)
                winHelper.resizeFromGrip(Math.round(windowSizeAtPress.width + position.x - dragOrigin.x),
                                         Math.round(windowSizeAtPress.height + position.y - dragOrigin.y))
            }

            LineIcon {
                anchors.centerIn: parent
                width: 13
                height: 13
                name: "resize"
                color: "#94b1c0"
                visible: classicGrip.enabled
            }
        }
    }

    Pane {
        id: brandShard
        objectName: "superBoosterBrandShard"
        visible: !mainWin.classic
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
        visible: !mainWin.classic
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
        visible: !mainWin.classic && mainWin.activeTab === 0
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
        pane: mainWin.classic ? mainWin.classicPagePane : mainWin.panelLayout.pages
        classicCard: mainWin.classic

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
        pane: mainWin.classic ? mainWin.classicPagePane : mainWin.panelLayout.pages
        classicCard: mainWin.classic

        ScrollView {
            id: settingsScroll
            objectName: "superBoosterSettingsScroll"
            x: settings.pane.content.x
            y: settings.pane.content.y
            width: settings.pane.content.width
            height: settings.pane.content.height
            clip: true
            leftPadding: mirrored ? effectiveScrollBarWidth + 6 : 0
            rightPadding: mirrored ? 0 : effectiveScrollBarWidth + 6
            contentWidth: availableWidth
            contentHeight: Math.max(settingsContent.implicitHeight, updateSettings.y + updateSettings.height) + 8
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            function scrollTo(y) {
                const view = contentItem as Flickable
                if (!view)
                    return
                view.cancelFlick()
                view.contentY = view.originY + Math.min(y, Math.max(0, view.contentHeight - view.height))
            }

            function showUpdateSettings() {
                scrollTo(contentHeight)
            }

            ColumnLayout {
                id: settingsContent
                width: settingsScroll.availableWidth
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Audio Engine & Device Setup"
                        color: "#f8fafc"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }
                    Button {
                        objectName: "jumpToUpdateSettings"
                        text: qsTr("Updates")
                        onClicked: settingsScroll.showUpdateSettings()
                    }
                }

                Text {
                    visible: backend.audioSetupIssue !== ""
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    text: backend.audioSetupIssue
                    color: "#fbbf24"
                    font.pixelSize: 12
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 12
                    RadioButton {
                        Layout.minimumWidth: 0
                        checked: backend.directMode
                        text: "System Audio Boost"
                        palette.windowText: "#e2e8f0"
                        onClicked: backend.directMode = true
                    }
                    RadioButton {
                        Layout.minimumWidth: 0
                        checked: !backend.directMode
                        text: "Device Routing (Input → Output)"
                        palette.windowText: "#e2e8f0"
                        onClicked: backend.directMode = false
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    text: backend.windowsOutputName
                        ? "Windows default output is " + backend.windowsOutputName
                        : "Windows has no default playback device."
                    color: "#cbd5e1"
                    font.pixelSize: 12
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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
                        Layout.minimumWidth: 0
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
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    color: "#cbd5e1"
                    font.pixelSize: 12
                    text: backend.selectedSourceDevice === "windows-digital"
                        ? "Use this if nothing is plugged into your PC’s digital audio port. Boost routes Windows’ default media audio through that output and plays it through your speakers or headphones. Pausing restores the previous Windows outputs. Apps with their own output setting may need to use Windows default."
                        : "Choose Automatic Digital Output to use an unused digital audio port with no install. For a manually selected source, assign your apps to that device in Windows Volume Mixer."
                }

                RowLayout {
                    visible: backend.directMode
                    Layout.minimumWidth: 0
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
                    Layout.minimumWidth: 0
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
                        Layout.minimumWidth: 0
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
                    Layout.minimumWidth: 0
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

                SettingCheckBox {
                    checked: backend.autostart
                    text: "Start automatically with Windows (minimized to tray)"
                    onClicked: backend.autostart = checked
                }
                SettingCheckBox {
                    checked: backend.hotkeysEnabled
                    text: "Enable global Windows hotkeys (Ctrl+Alt+Up, Ctrl+Alt+Down, Ctrl+Alt+B)"
                    onClicked: backend.hotkeysEnabled = checked
                }
                SettingCheckBox {
                    checked: backend.showTrayMsg
                    text: "Show tray notification when minimized"
                    onClicked: backend.showTrayMsg = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: settingsScroll.availableWidth
                    spacing: 9

                    Text {
                        text: qsTr("Updates")
                        color: "#f8fafc"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: qsTr("Installed version %1 · %2").arg(updater.currentVersion).arg(updateNotice.statusText)
                        color: "#a7b8ce"
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                    }
                    SettingCheckBox {
                        objectName: "superBoosterSettingsAutoInstallUpdates"
                        enabled: updater.supported
                        checked: updater.autoInstallUpdates
                        text: qsTr("Automatically install updates")
                        onToggled: updater.autoInstallUpdates = checked
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: updater.supported && (updater.autoInstallUpdates || !updater.automatic)
                        text: updater.autoInstallUpdates
                            ? qsTr("Silent installation checks for updates automatically. Turn it off to change when you’re notified.")
                            : qsTr("Turn on automatic checks to choose a notification.")
                        color: "#a7b8ce"
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                    }
                    SettingCheckBox {
                        objectName: "superBoosterAutomaticUpdateChecks"
                        enabled: updater.supported && !updater.autoInstallUpdates
                        checked: updater.automatic || updater.autoInstallUpdates
                        text: qsTr("Check for updates automatically")
                        onClicked: updater.automatic = checked
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 10

                        Label {
                            text: qsTr("Notify me using")
                            color: "#cbd5e1"
                        }
                        ComboBox {
                            objectName: "superBoosterUpdateNotificationMode"
                            popup.popupType: Popup.Window
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
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
                        Layout.minimumWidth: 0
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

    MouseArea {
        z: 1
        y: mainWin.classicMenuPane.y
        width: mainWin.width
        height: mainWin.height - y
        visible: mainWin.classic && mainWin.menuOpen
        onClicked: mainWin.menuOpen = false
    }

    AppearanceMenu {
        id: appearance
        objectName: "superBoosterAppearanceShard"
        z: 2
        visible: mainWin.menuOpen
        pane: mainWin.classic ? mainWin.classicMenuPane : mainWin.panelLayout.appearance
        material: mainWin.material
        layoutMode: mainWin.layoutMode
        updateService: updater
        onGeometryChanged: mainWin.queueGeometry()
        onLayoutSelected: layout => mainWin.selectLayout(layout)
        onMaterialSelected: materialId => backend.appearanceMaterial = materialId
        onAudioSettingsRequested: mainWin.openSettings(false)
        onUpdateSettingsRequested: mainWin.openSettings(true)
    }
}
