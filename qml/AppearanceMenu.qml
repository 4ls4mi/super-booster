pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GlassShard {
    id: menu

    required property var pane
    required property var updateService
    required property string layoutMode
    signal layoutSelected(string layout)
    signal materialSelected(string id)
    signal audioSettingsRequested()
    signal updateSettingsRequested()

    x: pane.x
    y: pane.y
    width: pane.width
    height: pane.height
    points: pane.points

    component SectionLabel: RowLayout {
        id: section
        required property string iconName
        required property string text
        property int textSize: 17

        spacing: 6

        LineIcon {
            name: section.iconName
            implicitWidth: 19
            implicitHeight: 19
        }
        Label {
            text: section.text
            color: "#f8f5fc"
            font.pixelSize: section.textSize
            font.weight: Font.DemiBold
        }
    }

    ColumnLayout {
        x: menu.pane.content.x
        y: menu.pane.content.y
        width: menu.pane.content.width
        height: menu.pane.content.height
        spacing: 6

        SectionLabel {
            iconName: "appearance"
            text: qsTr("Appearance")
            textSize: 20
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: [
                    { id: "glass", label: qsTr("Glass Panels") },
                    { id: "classic", label: qsTr("Classic Acrylic") }
                ]

                Button {
                    id: layoutChoice
                    required property var modelData

                    objectName: "superBoosterLayout_" + modelData.id
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    implicitHeight: 28
                    text: modelData.label
                    checked: menu.layoutMode === modelData.id
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: checked
                    onClicked: menu.layoutSelected(modelData.id)

                    contentItem: Label {
                        text: layoutChoice.text
                        color: layoutChoice.checked ? "#a9ffe4" : "#f5f0f9"
                        font.pixelSize: 12
                        font.weight: layoutChoice.checked ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    background: Rectangle {
                        radius: 6
                        color: layoutChoice.checked ? "#48699b99"
                            : layoutChoice.hovered ? "#40756891" : "#22121224"
                        border.color: layoutChoice.visualFocus || layoutChoice.checked ? "#a1f7df" : "#656e607d"
                    }
                }
            }
        }

        Label {
            visible: menu.layoutMode === "glass"
            text: qsTr("Material")
            color: "#e9ddec"
            font.pixelSize: 12
        }

        GridLayout {
            visible: menu.layoutMode === "glass"
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 5
            columnSpacing: 7
            uniformCellWidths: true

            Repeater {
                model: [
                    { id: "clear", label: qsTr("Clear"), light: "#38cec2e8", dark: "#0974678d" },
                    { id: "acrylic", label: qsTr("Acrylic"), light: "#a6b7aacb", dark: "#4e77709b" },
                    { id: "mica", label: qsTr("Mica"), light: "#d0cec5db", dark: "#8069568a" },
                    { id: "blurred", label: qsTr("Blurred"), light: "#498f7aa7", dark: "#baada2bf" },
                    { id: "frosted", label: qsTr("Frosted"), light: "#cfb1d5dd", dark: "#91726a9c" },
                    { id: "glassy", label: qsTr("Glassy"), light: "#aaac95be", dark: "#4a89779e" }
                ]

                Button {
                    id: choice
                    required property var modelData

                    objectName: "superBoosterMaterial_" + modelData.id
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(39, Math.min(58, menu.height * 0.125))
                    padding: 3
                    text: modelData.label
                    checked: menu.material === modelData.id
                    onClicked: menu.materialSelected(modelData.id)

                    contentItem: Column {
                        spacing: 2

                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(choice.width - 12, choice.height - 23, 24)
                            height: width

                            component Swatch: Rectangle {
                                radius: 4
                                border.color: "#61ffffff"
                                gradient: Gradient {
                                    GradientStop { position: 0; color: choice.modelData.light }
                                    GradientStop { position: 1; color: choice.modelData.dark }
                                }
                            }

                            Swatch {
                                anchors.centerIn: parent
                                width: choice.modelData.id === "acrylic" ? parent.width * 0.73 : parent.width
                                height: width
                                anchors.horizontalCenterOffset: choice.modelData.id === "acrylic" ? -3 : 0
                                anchors.verticalCenterOffset: choice.modelData.id === "acrylic" ? 3 : 0
                                border.color: choice.modelData.id === "clear" ? "#c9ffffff" : "#61ffffff"

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: 3
                                    radius: 1.5
                                    rotation: -45
                                    color: "#61ffffff"
                                    visible: choice.modelData.id === "glassy"
                                }
                            }

                            Swatch {
                                visible: choice.modelData.id === "acrylic"
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 3
                                anchors.verticalCenterOffset: -3
                                width: parent.width * 0.73
                                height: width
                            }
                        }

                        Label {
                            width: parent.width
                            text: choice.text
                            color: choice.checked ? "#96f9d6" : "#f5f0f9"
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                    background: Rectangle {
                        radius: 9
                        color: choice.checked ? "#42699b99" : choice.hovered ? "#40756891" : "#176d587f"
                        border.color: choice.visualFocus || choice.checked ? "#a1f7df" : "#656e607d"
                        border.width: choice.visualFocus || choice.checked ? 2 : 1
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 3
            implicitHeight: 1
            color: "#65dcd1e5"
        }

        Button {
            id: updateSettingsButton
            objectName: "superBoosterAppearanceUpdateSettings"
            Layout.alignment: Qt.AlignLeft
            implicitWidth: updateSettingsContents.implicitWidth + 12
            implicitHeight: 26
            leftPadding: 5
            rightPadding: 5
            topPadding: 2
            bottomPadding: 2
            text: qsTr("Update settings")
            onClicked: menu.updateSettingsRequested()

            contentItem: SectionLabel {
                id: updateSettingsContents
                iconName: "updates"
                text: updateSettingsButton.text
            }
            background: Rectangle {
                radius: 6
                color: updateSettingsButton.down ? "#40ffffff"
                    : updateSettingsButton.hovered ? "#25ffffff" : "transparent"
                border.color: updateSettingsButton.visualFocus ? "#98f5dc" : "transparent"
            }
        }

        GlassSwitch {
            objectName: "superBoosterSilentAutomaticUpdates"
            Layout.fillWidth: true
            Layout.topMargin: -5
            enabled: menu.updateService.supported
            checked: menu.updateService.autoInstallUpdates
            text: qsTr("Automatically install updates")
            font.pixelSize: menu.pane.content.width < 210 ? 11 : 12
            wrapLabel: true
            Accessible.description: qsTr("Downloads and installs silently")
            onToggled: menu.updateService.autoInstallUpdates = checked
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#65dcd1e5" }

        Button {
            id: settingsButton
            objectName: "superBoosterAppearanceSettings"
            Layout.alignment: Qt.AlignLeft
            implicitWidth: settingsContents.implicitWidth + 12
            implicitHeight: 32
            text: qsTr("Settings")
            padding: 5
            onClicked: menu.audioSettingsRequested()

            contentItem: SectionLabel {
                id: settingsContents
                iconName: "settings"
                text: settingsButton.text
            }
            background: Rectangle {
                radius: 6
                color: settingsButton.hovered ? "#25ffffff" : "transparent"
                border.color: settingsButton.visualFocus ? "#98f5dc" : "transparent"
            }
        }

        Item { Layout.fillHeight: true }
    }
}
