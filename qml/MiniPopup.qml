import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: popup
    objectName: "miniPopupWindow"
    width: 204
    height: 336
    visible: false
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

    onActiveChanged: {
        if (!active && visible) {
            hide()
        }
    }

    property color accentColor: {
        if (!backend.engineActive) return "#64748b"
        if (backend.volume > 300) return "#ff7043"
        if (backend.volume > 150) return "#38bdf8"
        return "#2ecc71"
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: "#ee0d131f"
        border.color: "#38ffffff"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: backend.engineActive ? "#2ecc71" : "#ef4444"
                }
                Text {
                    text: "Super Booster"
                    color: "#f1f5f9"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                Text {
                    text: backend.decibelText
                    color: "#94a3b8"
                    font.pixelSize: 10
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Math.round(backend.volume) + "%"
                color: popup.accentColor
                font.pixelSize: 26
                font.weight: Font.Bold
            }

            // Vertical 0-500% boost slider + peak bar
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                // Vertical Peak Meter
                Rectangle {
                    width: 8
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    radius: 4
                    color: "#20ffffff"
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        radius: 4
                        height: Math.max(4, parent.height * Math.min(1.0, Math.max(backend.outputPeakL, backend.outputPeakR)))
                        color: popup.accentColor
                    }
                }

                // Vertical Boost Slider
                Item {
                    id: boostTrack
                    readonly property real lower: backend.directMode ? 100 : 0
                    readonly property real norm: (backend.volume - lower) / (500 - lower)
                    width: 36
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        width: 8
                        radius: 4
                        color: "#30ffffff"

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            radius: 4
                            height: parent.height * boostTrack.norm
                            color: popup.accentColor
                        }
                    }

                    Rectangle {
                        width: 20; height: 20; radius: 10
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: (parent.height - 20) * (1.0 - boostTrack.norm)
                        color: "#ffffff"
                        border.color: popup.accentColor
                        border.width: 2.5
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function updateY(my) {
                            var t = 1.0 - Math.max(0.0, Math.min(1.0, my / Math.max(1.0, height)))
                            backend.volume = Math.round(boostTrack.lower + t * (500 - boostTrack.lower))
                        }
                        onPressed: (m) => updateY(m.y)
                        onReleased: backend.applyBoostLevel(backend.volume)
                        onPositionChanged: (m) => { if (pressed) updateY(m.y) }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [100, 200, 350]
                    Rectangle {
                        Layout.fillWidth: true
                        height: 22
                        radius: 6
                        color: Math.abs(backend.volume - modelData) < 8 ? "#3538bdf8" : "#18ffffff"
                        border.color: "#22ffffff"
                        Text {
                            anchors.centerIn: parent
                            text: modelData + "%"
                            color: "#e2e8f0"
                            font.pixelSize: 10
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: backend.applyBoostLevel(modelData)
                        }
                    }
                }
            }

            CheckBox {
                checked: backend.autostart
                text: "Start on Boot"
                font.pixelSize: 11
                palette.windowText: "#cbd5e1"
                onClicked: backend.autostart = checked
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 8
                    color: backend.engineActive ? "#dc2626" : "#16a34a"
                    Text {
                        anchors.centerIn: parent
                        text: backend.engineActive ? "Pause"
                            : backend.engineStarting ? "Connecting — Cancel"
                            : backend.audioSetupIssue ? "Set Up Boost" : "Boost"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: backend.toggleEngine()
                    }
                }

                Rectangle {
                    width: 62
                    height: 30
                    radius: 8
                    color: "#22ffffff"
                    border.color: "#30ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: "Full UI"
                        color: "#e2e8f0"
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: backend.showMainWindow()
                    }
                }
            }
        }
    }
}
