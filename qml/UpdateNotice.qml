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
    readonly property color accentColor: "#81f2ce"
    readonly property rect workArea: backend.mainWindowWorkArea
    readonly property real notificationLane: Math.min(152, Math.max(56, workArea.height * 0.18))

    title: qsTr("Super Booster update available")
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    modality: Qt.NonModal
    transientParent: null
    screen: anchorWindow.screen
    color: "transparent"
    visible: false
    width: Math.min(394, Math.max(1, workArea.width - 32))
    height: popupContent.implicitHeight + 40
    x: workArea.x + Math.max(0, workArea.width - width - 16)
    y: workArea.y + Math.max(8, workArea.height - height - notificationLane)

    onCanOfferChanged: if (!canOffer) hide()

    function showDetails() {
        hide()
        if (!details.visible) {
            const targetX = anchorWindow.visible ? anchorWindow.x + (anchorWindow.width - details.width) / 2
                                                : workArea.x + (workArea.width - details.width) / 2
            const targetY = anchorWindow.visible ? anchorWindow.y + (anchorWindow.height - details.height) / 2
                                                : workArea.y + (workArea.height - details.height) / 2
            details.x = Math.round(Math.max(workArea.x, Math.min(targetX, workArea.x + workArea.width - details.width)))
            details.y = Math.round(Math.max(workArea.y, Math.min(targetY, workArea.y + workArea.height - details.height)))
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

    GlassShard {
        anchors.fill: parent
        material: "frosted"
        points: [Qt.point(0.005, 0.245), Qt.point(0.067, 0.037), Qt.point(0.357, 0.065),
            Qt.point(0.62, 0.09), Qt.point(0.955, 0.018), Qt.point(0.993, 0.13),
            Qt.point(0.988, 0.78), Qt.point(0.946, 0.952), Qt.point(0.573, 0.924),
            Qt.point(0.057, 0.993), Qt.point(0.024, 0.822)]

        ColumnLayout {
            id: popupContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 9

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    text: "⇩"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: notice.textColor
                    font.pixelSize: 26
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

                UpdateButton {
                    objectName: "dismissSuperBoosterUpdate"
                    text: "×"
                    Accessible.name: qsTr("Dismiss this version")
                    leftPadding: 8
                    rightPadding: 8
                    onClicked: {
                        notice.hide()
                        notice.service.dismiss()
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                layoutDirection: Qt.RightToLeft
                spacing: 6

                UpdateButton {
                    objectName: "viewSuperBoosterUpdate"
                    text: qsTr("Update")
                    highlighted: true
                    onClicked: notice.showDetails()
                }
                UpdateButton {
                    objectName: "remindSuperBoosterUpdate"
                    text: qsTr("Later")
                    onClicked: {
                        notice.hide()
                        notice.service.remindLater()
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
        width: Math.min(548, Math.max(1, notice.workArea.width - 24))
        height: Math.min(386, Math.max(1, notice.workArea.height - 38))
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
            color: action.highlighted ? "#082b27" : "#edf6ff"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 7
            color: action.highlighted
                ? (action.down ? "#50d1ae" : action.hovered ? "#a2fce2" : "#80efce")
                : (action.down ? "#30344c" : action.hovered ? "#4c4b69" : "#3c3c56")
            border.color: action.activeFocus ? "#afffe8" : action.highlighted ? "#b1f5e0" : "#666480"
        }
    }
}
