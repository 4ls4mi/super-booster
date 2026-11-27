pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

Item {
    id: view

    required property var panelLayout
    required property var audio
    required property string material
    required property color accent
    required property bool resizeEnabled
    readonly property var shards: [gain, playback, effects, meter]
    signal shardGeometryChanged()
    signal resizeRequested(int width, int height)

    readonly property var playbackDevices: {
        const automatic = audio.automaticPlaybackOutputName
        return [{ id: "", name: automatic || qsTr("Automatic playback unavailable") }]
            .concat(Array.from(audio.outputDevices))
    }

    component Pane: GlassShard {
        required property var pane
        x: pane.x
        y: pane.y
        width: pane.width
        height: pane.height
        points: pane.points
        material: view.material
        onGeometryChanged: view.shardGeometryChanged()
    }

    component PanelTitle: RowLayout {
        id: title
        required property string iconName
        required property string text
        property int textSize: 19

        spacing: 9
        LineIcon {
            name: title.iconName
            implicitWidth: title.textSize + 3
            implicitHeight: implicitWidth
        }
        Label {
            text: title.text
            color: "#f8f5fc"
            font.pixelSize: title.textSize
            font.weight: Font.DemiBold
        }
    }

    Pane {
        id: gain
        objectName: "superBoosterGainShard"
        pane: view.panelLayout.gain

        ColumnLayout {
            x: gain.pane.content.x
            y: gain.pane.content.y
            width: gain.pane.content.width
            height: gain.pane.content.height
            spacing: 6

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: dial
                    anchors.centerIn: parent
                    width: Math.min(285, parent.width, parent.height / 0.78)
                    height: width * 0.78
                    readonly property real radius: width * 0.425
                    readonly property real stroke: Math.max(8, width * 0.059)

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        component DialArc: ShapePath {
                            id: arc
                            required property real sweep
                            fillColor: "transparent"
                            strokeWidth: dial.stroke
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: dial.width * 0.5
                                centerY: dial.width * 0.5
                                radiusX: dial.radius
                                radiusY: dial.radius
                                startAngle: 155
                                sweepAngle: arc.sweep
                            }
                        }

                        DialArc { strokeColor: "#55d6cbe5"; sweep: 230 }
                        DialArc { strokeColor: view.accent; sweep: Math.max(2, 230 * view.audio.volume / 500) }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: parent.height * 0.33
                        spacing: 0

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(view.audio.volume) + "%"
                            color: "#fcf9ff"
                            font.pixelSize: Math.min(58, dial.width * 0.26)
                            font.weight: Font.Bold
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("Boost level")
                            color: "#f8f3fa"
                            font.pixelSize: 14
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: view.audio.decibelText
                            color: "#d8cfe5"
                            font.pixelSize: 10
                        }
                    }
                }
            }

            BoostSlider {
                Layout.fillWidth: true
                from: view.audio.directMode ? 100 : 0
                value: view.audio.volume
                accentColor: view.accent
                Accessible.name: qsTr("Boost level")
                onMoved: {
                    view.audio.volume = value
                    if (!pressed) view.audio.applyBoostLevel(value)
                }
                onPressedChanged: if (!pressed) view.audio.applyBoostLevel(value)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: [100, 150, 200, 300, 400, 500]

                    Button {
                        id: preset
                        required property int modelData

                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: 22
                        padding: 1
                        text: modelData + "%"
                        checked: Math.round(view.audio.volume) === modelData
                        onClicked: view.audio.applyBoostLevel(modelData)

                        contentItem: Label {
                            text: preset.text
                            color: preset.checked ? view.accent : "#f0e9f5"
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 4
                            color: preset.checked ? "#4d7b9e96" : preset.hovered ? "#26ffffff" : "transparent"
                            border.color: preset.visualFocus ? view.accent : "transparent"
                        }
                    }
                }
            }

            Button {
                id: power
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(214, parent.width * 0.84)
                implicitHeight: 36
                text: view.audio.engineActive ? qsTr("Pause Boost")
                    : view.audio.engineStarting ? qsTr("Cancel Boost")
                    : view.audio.audioSetupIssue ? qsTr("Set Up Boost") : qsTr("Start Boost")
                onClicked: view.audio.toggleEngine()

                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        LineIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: (view.audio.engineActive || view.audio.engineStarting) ? "pause" : "play"
                            color: "#102c24"
                            width: 17
                            height: width
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: power.text
                            color: "#102c24"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }
                    }
                }
                background: Rectangle {
                    color: power.down ? "#71d9b4" : power.hovered ? "#adffe1" : "#8ffbd0"
                    border.color: power.visualFocus ? "#ffffff" : "#70ffffff"
                    border.width: power.visualFocus ? 2 : 1
                    radius: 9
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width * 0.82
                text: view.audio.statusMessage
                color: "#e1d8ea"
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                ToolTip.visible: statusHover.hovered && truncated
                ToolTip.text: text
                HoverHandler { id: statusHover }
            }
        }
    }

    Pane {
        id: playback
        objectName: "superBoosterPlaybackShard"
        pane: view.panelLayout.playback

        ColumnLayout {
            x: playback.pane.content.x
            y: playback.pane.content.y + (playback.pane.content.height - implicitHeight) * 0.5
            width: playback.pane.content.width
            spacing: 7

            PanelTitle { iconName: "playback"; text: qsTr("Playback") }

            ComboBox {
                id: outputChoice
                readonly property string compactDeviceName: {
                    const description = /^.+? \((.+)\)$/.exec(displayText)
                    return description ? description[1] : displayText
                }

                Layout.fillWidth: true
                Layout.minimumWidth: 0
                model: view.playbackDevices
                textRole: "name"
                valueRole: "id"
                currentIndex: {
                    const i = view.playbackDevices.findIndex(device => device.id === view.audio.selectedOutDevice)
                    return Math.max(i, 0)
                }
                popup.popupType: Popup.Window
                Accessible.name: qsTr("Playback device: %1").arg(displayText)
                ToolTip.visible: hovered && (compactDeviceName !== displayText || playbackName.truncated)
                ToolTip.text: displayText
                onActivated: view.audio.selectedOutDevice = currentValue

                contentItem: Label {
                    id: playbackName

                    leftPadding: 10
                    rightPadding: 23
                    text: outputChoice.compactDeviceName
                    color: "#f8f5fc"
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                indicator: LineIcon {
                    x: outputChoice.width - width - 10
                    y: (outputChoice.height - height) / 2
                    name: "expand"
                    width: 13
                    height: width
                }
                background: Rectangle {
                    implicitHeight: 34
                    radius: 7
                    color: outputChoice.hovered ? "#53746687" : "#42302548"
                    border.color: outputChoice.visualFocus ? "#a9f5de" : "#91c8bbd8"
                    border.width: outputChoice.visualFocus ? 2 : 1
                }
            }

            Label {
                Layout.fillWidth: true
                text: view.audio.selectedOutDevice === "" ? qsTr("Automatic playback") : qsTr("Selected playback device")
                color: "#ddd4e8"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }
    }

    Pane {
        id: effects
        objectName: "superBoosterEffectsShard"
        pane: view.panelLayout.effects

        ColumnLayout {
            x: effects.pane.content.x
            y: effects.pane.content.y
            width: effects.pane.content.width
            height: effects.pane.content.height
            spacing: 1

            PanelTitle {
                iconName: "effects"
                text: qsTr("Audio effects")
                Layout.bottomMargin: 4
            }

            GlassSwitch {
                Layout.fillWidth: true
                implicitHeight: 27
                text: qsTr("Soft limiter")
                checked: view.audio.limiterEnabled
                onToggled: view.audio.limiterEnabled = checked
            }
            GlassSwitch {
                Layout.fillWidth: true
                implicitHeight: 27
                text: qsTr("SuperBoost Clarity")
                checked: view.audio.superBoost
                onToggled: view.audio.superBoost = checked
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Bass boost"); color: "#f8f5fc" }
                Item { Layout.fillWidth: true }
                Label { text: Math.round(view.audio.bassBoost * 100) + "%"; color: "#a2f5d8" }
            }
            BoostSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                stepSize: 0
                accentColor: view.accent
                value: view.audio.bassBoost
                Accessible.name: qsTr("Bass boost")
                onMoved: view.audio.bassBoost = value
            }
            Item { Layout.fillHeight: true }
        }

        Item {
            id: grip
            objectName: "superBoosterResizeGrip"
            x: view.panelLayout.grip.x
            y: view.panelLayout.grip.y
            width: view.panelLayout.grip.width
            height: view.panelLayout.grip.height
            Accessible.name: qsTr("Resize window")

            LineIcon {
                anchors.centerIn: parent
                name: "resize"
                color: gripArea.containsMouse ? view.accent : "#ece3f6"
                width: Math.min(27, parent.width)
                height: width
            }

            MouseArea {
                id: gripArea

                property point dragOrigin
                property size windowSizeAtPress

                anchors.fill: parent
                enabled: view.resizeEnabled
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SizeFDiagCursor
                onPressed: mouse => {
                    dragOrigin = mapToItem(null, mouse.x, mouse.y)
                    windowSizeAtPress = Qt.size(view.width, view.height)
                }
                onPositionChanged: mouse => {
                    if (!pressed) return
                    const position = mapToItem(null, mouse.x, mouse.y)
                    view.resizeRequested(Math.round(windowSizeAtPress.width + position.x - dragOrigin.x),
                                         Math.round(windowSizeAtPress.height + position.y - dragOrigin.y))
                }
            }
        }
    }

    Pane {
        id: meter
        objectName: "superBoosterMeterShard"
        pane: view.panelLayout.meter
        readonly property bool showMeterValues: visible && view.Window.window?.visibility !== Window.Minimized
        readonly property var spectrumBands: showMeterValues ? view.audio.spectrumBands : []

        ColumnLayout {
            x: meter.pane.content.x
            y: meter.pane.content.y
            width: meter.pane.content.width
            height: meter.pane.content.height
            spacing: 2

            RowLayout {
                Layout.fillWidth: true

                PanelTitle {
                    iconName: "output"
                    text: qsTr("Output level")
                    textSize: 14
                }
                Item { Layout.fillWidth: true }
                Label {
                    visible: meter.showMeterValues && view.audio.limiterReduction > 0.03
                    text: qsTr("Limiter active")
                    color: "#ffd4ad"
                    font.pixelSize: 10
                }
            }
            Repeater {
                model: ["L", "R"]

                RowLayout {
                    id: peakRow
                    required property int index
                    required property string modelData
                    readonly property real peak: meter.showMeterValues
                        ? (index === 0 ? view.audio.outputPeakL : view.audio.outputPeakR) : 0
                    Layout.fillWidth: true
                    spacing: 5

                    Label { text: peakRow.modelData; color: "#e3dceb"; font.pixelSize: 9 }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: "#58ded4e9"

                        Rectangle {
                            width: parent.width * Math.min(1, peakRow.peak)
                            height: parent.height
                            radius: 3
                            color: peakRow.peak > 0.9 ? "#fbac70" : view.accent
                        }
                    }
                }
            }
            Row {
                id: spectrum
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 12
                spacing: 2

                Repeater {
                    model: 24

                    Item {
                        required property int index
                        width: (spectrum.width - 23 * spectrum.spacing) / 24
                        height: parent.height

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.min(parent.height,
                                             Math.max(1, parent.height * (meter.spectrumBands[index] || 0)))
                            color: "#9bbfb3cf"
                            radius: 1
                        }
                    }
                }
            }
        }
    }
}
