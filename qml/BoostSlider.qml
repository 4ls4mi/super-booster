import QtQuick
import QtQuick.Controls

Item {
    id: root
    property real value: 100.0
    property real from: 0.0
    property real to: 500.0
    property color accentColor: "#2ecc71"
    signal moved(real newValue)
    signal released()

    implicitHeight: 42
    implicitWidth: 320

    property real norm: Math.max(0.0, Math.min(1.0, (value - from) / Math.max(1.0, to - from)))

    // Tick labels below track
    Item {
        id: trackArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 24

        // Background glass groove
        Rectangle {
            id: groove
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            height: 8
            radius: 4
            color: "#30ffffff"
            border.color: "#18ffffff"
            border.width: 1

            // Unity 100% marker line
            Rectangle {
                x: groove.width * ((100.0 - root.from) / (root.to - root.from)) - 1
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 2
                color: "#90ffffff"
                z: 2
            }

            // Active glowing fill gradient
            Rectangle {
                height: parent.height
                width: Math.max(8, groove.width * root.norm)
                radius: 4
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#2ecc71" }
                    GradientStop { position: 0.45; color: "#29b6f6" }
                    GradientStop { position: 1.0; color: root.accentColor }
                }
            }
        }

        // Thumb knob
        Rectangle {
            id: handle
            width: 20
            height: 20
            radius: 10
            anchors.verticalCenter: groove.verticalCenter
            x: Math.max(0, Math.min(trackArea.width - width, root.norm * (trackArea.width - width)))
            color: "#f8fafc"
            border.color: root.accentColor
            border.width: 2.5

            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: root.accentColor
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            function updateFromX(mx) {
                var t = Math.max(0.0, Math.min(1.0, mx / Math.max(1.0, trackArea.width)))
                var v = Math.round(root.from + t * (root.to - root.from))
                root.moved(v)
            }

            onPressed: (mouse) => updateFromX(mouse.x)
            onPositionChanged: (mouse) => {
                if (pressed) updateFromX(mouse.x)
            }
            onReleased: root.released()
        }
    }

    // Position tick labels along the selected range.
    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        Repeater {
            model: root.from === 0 ? [0, 100, 200, 300, 400, 500] : [100, 200, 300, 400, 500]
            Item {
                width: root.width / (root.from === 0 ? 6 : 5)
                height: 14
                Text {
                    anchors.horizontalCenter: index === 0 ? undefined : (modelData === root.to ? undefined : parent.horizontalCenter)
                    anchors.left: index === 0 ? parent.left : undefined
                    anchors.right: modelData === root.to ? parent.right : undefined
                    text: modelData + "%"
                    font.pixelSize: 10
                    font.weight: modelData === 100 ? Font.DemiBold : Font.Normal
                    color: modelData === 100 ? "#b8e9d4" : "#7a8aa6"
                }
            }
        }
    }
}
