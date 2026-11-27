import QtQuick

Rectangle {
    id: card
    property color borderTint: "#28ffffff"
    property color fillTint: "#22111827"
    property int cornerRadius: 14

    radius: cornerRadius
    color: fillTint
    border.color: borderTint
    border.width: 1

    // Subtle top specular highlight edge for glass depth
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.cornerRadius * 0.6
        anchors.rightMargin: card.cornerRadius * 0.6
        height: 1
        color: "#38ffffff"
    }
}
