import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GlassShard {
    id: menu
    required property var updateService
    signal materialSelected(string id)
    signal audioSettingsRequested()

    implicitWidth: 310
    implicitHeight: 389
    points: [Qt.point(0.004, 0.20), Qt.point(0.125, 0.08), Qt.point(0.27, 0.09),
        Qt.point(0.37, 0.01), Qt.point(0.53, 0.084), Qt.point(0.88, 0.041),
        Qt.point(0.997, 0.26), Qt.point(0.96, 0.92), Qt.point(0.15, 0.991),
        Qt.point(0.037, 0.89)]

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 50
        anchors.leftMargin: 25
        anchors.rightMargin: 24
        anchors.bottomMargin: 31
        spacing: 9

        Label { text: qsTr("Appearance"); color: "#f5fcff"; font.pixelSize: 23; font.weight: Font.DemiBold }
        Label { text: qsTr("Material"); color: "#d3e8ef"; font.pixelSize: 13 }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 6
            columnSpacing: 6

            Repeater {
                model: [
                    { id: "clear", label: qsTr("Clear") }, { id: "acrylic", label: qsTr("Acrylic") },
                    { id: "mica", label: qsTr("Mica") }, { id: "blurred", label: qsTr("Blurred") },
                    { id: "frosted", label: qsTr("Frosted") }, { id: "glassy", label: qsTr("Glassy") }
                ]

                Button {
                    id: choice
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 33
                    padding: 5
                    text: modelData.label
                    checked: menu.material === modelData.id
                    onClicked: menu.materialSelected(modelData.id)

                    contentItem: Label {
                        text: choice.text
                        color: choice.checked ? "#e0fffa" : "#e6f5fd"
                        font.pixelSize: 12
                        font.weight: choice.checked ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        radius: 6
                        color: choice.checked ? "#a3116661" : choice.hovered ? "#6b477484" : "#4b2e4b5a"
                        border.color: choice.visualFocus || choice.checked ? "#92f4e5" : "#6085acb9"
                        border.width: choice.visualFocus || choice.checked ? 2 : 1
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 6; height: 1; color: "#6491b6bb" }

        Label { text: qsTr("Updates"); color: "#f5fcff"; font.pixelSize: 18; font.weight: Font.DemiBold }
        GlassSwitch {
            objectName: "superBoosterSilentAutomaticUpdates"
            Layout.fillWidth: true
            enabled: menu.updateService.supported
            checked: menu.updateService.autoInstallUpdates
            text: qsTr("Automatically install updates")
            Accessible.description: qsTr("Downloads and installs silently")
            onToggled: menu.updateService.autoInstallUpdates = checked
        }
        Label {
            Layout.fillWidth: true
            Layout.topMargin: -10
            Layout.rightMargin: 43
            text: qsTr("Downloads and installs silently")
            color: "#d4e7ee"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Button {
            Layout.alignment: Qt.AlignLeft
            text: qsTr("Settings")
            onClicked: menu.audioSettingsRequested()
        }

        Item { Layout.fillHeight: true }
    }
}
