import QtQuick
import QtQuick.Controls

Slider {
    id: slider

    property color accentColor: "#8ffbd0"

    to: 500
    stepSize: 1
    snapMode: Slider.SnapAlways
    implicitHeight: 25
    padding: 0

    background: Rectangle {
        x: slider.leftPadding + thumb.width * 0.5
        y: slider.topPadding + (slider.availableHeight - height) * 0.5
        width: slider.availableWidth - thumb.width
        height: 7
        radius: height * 0.5
        color: "#65c7b7d5"

        Rectangle {
            width: parent.width * slider.visualPosition
            height: parent.height
            radius: height * 0.5
            color: slider.accentColor
        }
    }

    handle: Rectangle {
        id: thumb

        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + (slider.availableHeight - height) * 0.5
        width: 17
        height: width
        radius: width * 0.5
        color: slider.accentColor
        border.color: "#fafffc"
        border.width: slider.visualFocus || slider.pressed ? 3 : 2
    }
}
