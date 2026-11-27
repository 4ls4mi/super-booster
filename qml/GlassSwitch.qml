import QtQuick
import QtQuick.Controls

Switch {
    id: toggle

    property bool wrapLabel: false

    implicitHeight: 32
    spacing: 10
    leftPadding: 0
    rightPadding: 0

    contentItem: Text {
        leftPadding: 0
        rightPadding: toggle.indicator.width + toggle.spacing
        text: toggle.text
        color: toggle.enabled ? "#f8f5fc" : "#c1b8cd"
        font: toggle.font
        verticalAlignment: Text.AlignVCenter
        wrapMode: toggle.wrapLabel ? Text.WordWrap : Text.NoWrap
        elide: toggle.wrapLabel ? Text.ElideNone : Text.ElideRight
    }

    indicator: Rectangle {
        x: toggle.width - width
        y: (toggle.height - height) / 2
        width: 42
        height: 23
        radius: height / 2
        color: toggle.checked ? "#8af4cd" : "#6c8e7b9f"
        border.color: toggle.visualFocus ? "#ffffff" : toggle.checked ? "#acfadd" : "#75bbadc9"
        border.width: toggle.visualFocus ? 2 : 1
        opacity: toggle.enabled ? 1 : 0.6

        Rectangle {
            x: toggle.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 17
            height: width
            radius: width / 2
            color: "#f7fffd"
        }
    }
}
