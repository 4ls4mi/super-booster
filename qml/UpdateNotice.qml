pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: notice
    objectName: "superBoosterUpdateNotice"

    required property var service
    required property Window anchorWindow
    readonly property string updateState: service?.state ?? "idle"
    readonly property bool busy: updateState === "checking" || updateState === "downloading"
                                 || updateState === "installing"
    readonly property bool canOffer: Boolean(service?.automatic) && Boolean(service?.supported)
                                     && !service.autoInstallUpdates
                                     && service.notificationMode !== "quiet"
                                     && (updateState === "available" || updateState === "ready")
    readonly property bool detailsVisible: details.visible && details.visibility !== Window.Minimized
    readonly property string statusText: {
        if (!service?.supported)
            return qsTr("In-app updates are unavailable for this copy.")
        switch (updateState) {
        case "checking": return qsTr("Checking for updates…")
        case "current": return qsTr("Super Booster is up to date.")
        case "available": return qsTr("Version %1 is available.").arg(service.version)
        case "downloading": return qsTr("Downloading version %1…").arg(service.version)
        case "ready": return service.autoInstallUpdates
            ? qsTr("Version %1 will install when Super Booster is idle.").arg(service.version)
            : qsTr("Version %1 is ready to install.").arg(service.version)
        case "installing": return qsTr("Installing the update…")
        case "error": return qsTr("The update could not be completed.")
        default: return qsTr("Ready to check for updates.")
        }
    }

    readonly property color textColor: "#f1f5f9"
    readonly property color mutedColor: "#a7b8ce"
    readonly property color accentColor: "#7dd3fc"

    title: qsTr("Super Booster update available")
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    modality: Qt.NonModal
    transientParent: null
    screen: anchorWindow.screen
    color: "transparent"
    visible: false
    width: Math.min(400, (Screen.width || 420) - 24)
    height: popupContent.implicitHeight + 32
    x: Screen.virtualX + Math.min(Screen.width, Screen.desktopAvailableWidth || Screen.width) - width - 16
    y: Math.max(Screen.virtualY + 12, Screen.virtualY
        + Math.min(Screen.height, Screen.desktopAvailableHeight || Screen.height) - height - 22)

    onCanOfferChanged: if (!canOffer) hide()

    function openReleases() {
        Qt.openUrlExternally("https://github.com/4ls4mi/super-booster/releases/latest")
    }

    function showDetails() {
        hide()
        if (!details.visible) {
            const targetX = anchorWindow.visible ? anchorWindow.x + (anchorWindow.width - details.width) / 2
                                                : Screen.virtualX + (Screen.width - details.width) / 2
            const targetY = anchorWindow.visible ? anchorWindow.y + (anchorWindow.height - details.height) / 2
                                                : Screen.virtualY + (Screen.height - details.height) / 2
            details.x = Math.round(Math.max(Screen.virtualX, Math.min(targetX, Screen.virtualX + Screen.width - details.width)))
            details.y = Math.round(Math.max(Screen.virtualY, Math.min(targetY, Screen.virtualY + Screen.height - details.height)))
        }
        if (details.visibility === Window.Minimized)
            details.showNormal()
        else
            details.show()
        details.raise()
        details.requestActivate()
    }

    function checkNow() {
        showDetails()
        if (service?.supported && !busy)
            service.check()
    }

    Connections {
        target: notice.service
        function onShowDetailsRequested() { notice.showDetails() }
        function onOfferAvailable() {
            if (!notice.canOffer || details.visible)
                return
            switch (notice.service.notificationMode) {
            case "dialog":
                notice.showDetails()
                break
            case "toast":
            case "notify":
                notice.show()
                break
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 13
        color: "#131c2b"
        border.color: "#465c76"

        ColumnLayout {
            id: popupContent
            anchors.fill: parent
            anchors.margins: 16
            spacing: 9

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 8
                    color: "#21364e"

                    Text {
                        anchors.centerIn: parent
                        text: "⬇"
                        color: notice.accentColor
                        font.pixelSize: 17
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Super Booster update available")
                        wrapMode: Text.WordWrap
                        color: notice.textColor
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    Label {
                        Layout.fillWidth: true
                        text: notice.statusText
                        wrapMode: Text.WordWrap
                        color: notice.mutedColor
                        font.pixelSize: 12
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                UpdateButton {
                    objectName: "viewSuperBoosterUpdate"
                    text: qsTr("View update")
                    highlighted: true
                    onClicked: notice.showDetails()
                }
                UpdateButton {
                    objectName: "remindSuperBoosterUpdate"
                    text: qsTr("Remind me")
                    onClicked: {
                        notice.hide()
                        notice.service.remindLater()
                    }
                }
                UpdateButton {
                    objectName: "dismissSuperBoosterUpdate"
                    text: qsTr("Dismiss")
                    onClicked: {
                        notice.hide()
                        notice.service.dismiss()
                    }
                }
            }
        }
    }

    Window {
        id: details
        objectName: "superBoosterUpdateDetails"
        screen: notice.anchorWindow.screen
        transientParent: null
        modality: Qt.NonModal
        width: Math.min(548, (Screen.width || 568) - 24)
        height: Math.min(386, (Screen.height || 406) - 38)
        color: "#101723"
        title: qsTr("Super Booster Update")
        visible: false

        Shortcut { sequence: "Escape"; onActivated: details.hide() }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 17
            spacing: 12

            Label {
                Layout.fillWidth: true
                text: notice.statusText
                color: notice.textColor
                wrapMode: Text.WordWrap
                font.pixelSize: 19
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Installed version %1").arg(notice.service?.currentVersion ?? "")
                color: notice.mutedColor
                font.pixelSize: 12
            }

            ProgressBar {
                Layout.fillWidth: true
                visible: notice.busy
                from: 0
                to: 1
                value: notice.service?.progress ?? 0
                indeterminate: notice.updateState !== "downloading"
                palette.highlight: "#38bdf8"
                Accessible.name: qsTr("Update progress")
            }
            Label {
                Layout.fillWidth: true
                visible: notice.updateState === "downloading"
                text: qsTr("%1% downloaded").arg(Math.floor((notice.service?.progress ?? 0) * 100))
                color: notice.mutedColor
            }

            Label {
                Layout.fillWidth: true
                visible: notice.updateState === "error"
                text: notice.service?.error ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: "#fda4af"
            }
            Label {
                visible: notesView.visible
                text: qsTr("Release notes")
                color: notice.textColor
                font.weight: Font.DemiBold
            }
            ScrollView {
                id: notesView
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Boolean(notice.service?.notes) && !notice.busy
                contentWidth: availableWidth
                clip: true

                TextArea {
                    text: notice.service?.notes ?? ""
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    readOnly: true
                    selectByMouse: true
                    color: notice.textColor
                    padding: 10
                    background: Rectangle {
                        radius: 8
                        color: "#182334"
                        border.color: "#304259"
                    }
                }
            }
            Item { Layout.fillHeight: true; visible: !notesView.visible }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#344258"
            }

            Flow {
                Layout.fillWidth: true
                layoutDirection: Qt.RightToLeft
                spacing: 8

                UpdateButton {
                    text: notice.busy ? qsTr("Hide") : qsTr("Close")
                    onClicked: details.hide()
                }
                UpdateButton {
                    objectName: "downloadSuperBoosterUpdate"
                    visible: notice.updateState === "available"
                    highlighted: true
                    text: qsTr("Download update")
                    onClicked: notice.service.download()
                }
                UpdateButton {
                    objectName: "installSuperBoosterUpdate"
                    visible: notice.updateState === "ready"
                    highlighted: true
                    text: qsTr("Install update")
                    onClicked: notice.service.install()
                }
                UpdateButton {
                    visible: notice.updateState === "error" && Boolean(notice.service?.supported)
                    highlighted: true
                    text: qsTr("Check again")
                    onClicked: notice.checkNow()
                }
                UpdateButton {
                    text: qsTr("GitHub releases")
                    onClicked: notice.openReleases()
                }
            }
        }
    }

    component UpdateButton: Button {
        id: action

        implicitHeight: 33
        leftPadding: 12
        rightPadding: 12
        font.pixelSize: 12

        contentItem: Text {
            text: action.text
            font: action.font
            color: action.highlighted ? "#e0f2fe" : "#e2e8f0"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 7
            color: action.highlighted
                ? (action.down ? "#195484" : action.hovered ? "#206ca0" : "#1b557e")
                : (action.down ? "#1d3049" : action.hovered ? "#2b415c" : "#202f43")
            border.color: action.activeFocus ? "#7dd3fc" : action.highlighted ? "#3d90c0" : "#3b4e67"
        }
    }
}
