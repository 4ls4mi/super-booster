import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

Item {
    id: view

    required property var audio
    required property string material
    required property color accent
    property bool compact: false
    readonly property var shards: [gain, playback, effects, meter]
    signal shardGeometryChanged()
    signal resizeRequested()

    readonly property var playbackDevices: {
        const automatic = audio.automaticPlaybackOutputName
        return [{ id: "", name: automatic || qsTr("Automatic playback unavailable") }]
            .concat(Array.from(audio.outputDevices))
    }

    GlassShard {
        id: gain
        width: (view.width - 12) * (view.compact ? 0.55 : 0.56)
        height: view.height - 121
        material: view.material
        points: [Qt.point(0.002, 0.68), Qt.point(0.055, 0.19), Qt.point(0.17, 0.065),
            Qt.point(0.45, 0.04), Qt.point(0.61, 0.01), Qt.point(0.98, 0.09),
            Qt.point(0.957, 0.32), Qt.point(0.998, 0.57), Qt.point(0.94, 0.9),
            Qt.point(0.85, 0.995), Qt.point(0.48, 0.947), Qt.point(0.22, 0.97),
            Qt.point(0.07, 0.86)]
        onGeometryChanged: view.shardGeometryChanged()

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 38
            anchors.rightMargin: 31
            anchors.topMargin: 24
            anchors.bottomMargin: 27
            spacing: 7

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 100

                Item {
                    id: dial
                    anchors.centerIn: parent
                    width: Math.min(250, parent.width, parent.height * 1.53)
                    height: width * 0.63
                    readonly property real radius: width * 0.415

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: "#5ca8c6cf"
                            strokeWidth: 12
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: dial.width / 2
                                centerY: dial.width * 0.47
                                radiusX: dial.radius
                                radiusY: radiusX
                                startAngle: 160
                                sweepAngle: 220
                            }
                        }
                        ShapePath {
                            strokeColor: view.accent
                            strokeWidth: 12
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                centerX: dial.width / 2
                                centerY: dial.width * 0.47
                                radiusX: dial.radius
                                radiusY: radiusX
                                startAngle: 160
                                sweepAngle: Math.max(2, 220 * view.audio.volume / 500)
                            }
                        }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: parent.height * 0.17
                        spacing: 0

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(view.audio.volume) + "%"
                            color: "#f7fffe"
                            font.pixelSize: Math.min(52, gain.width * 0.17)
                            font.weight: Font.Bold
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: view.audio.decibelText
                            color: "#d2f3f1"
                            font.pixelSize: 12
                        }
                    }
                }
            }

            Label {
                text: qsTr("Boost level")
                color: "#f1fcff"
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            BoostSlider {
                Layout.fillWidth: true
                from: view.audio.directMode ? 100 : 0
                value: view.audio.volume
                accentColor: view.accent
                onMoved: value => view.audio.volume = value
                onReleased: view.audio.applyBoostLevel(view.audio.volume)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 3
                Repeater {
                    model: [100, 150, 200, 300, 400, 500]
                    Button {
                        required property int modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: 25
                        padding: 2
                        text: modelData + "%"
                        font.pixelSize: 10
                        checked: Math.round(view.audio.volume) === modelData
                        onClicked: view.audio.applyBoostLevel(modelData)
                    }
                }
            }

            Button {
                id: power
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.maximumWidth: 240
                implicitHeight: 39
                text: view.audio.engineActive ? qsTr("Pause Boost")
                    : view.audio.engineStarting ? qsTr("Cancel Boost")
                    : view.audio.audioSetupIssue ? qsTr("Set Up Boost") : qsTr("Start Boost")
                onClicked: view.audio.toggleEngine()

                contentItem: Label {
                    text: power.text
                    color: "#062928"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: power.down ? "#5fe1c4" : power.hovered ? "#a0fbe7" : "#76efd3"
                    border.color: power.visualFocus ? "#ffffff" : "#70ffffff"
                    border.width: power.visualFocus ? 2 : 1
                    radius: 8
                }
            }

            Label {
                Layout.fillWidth: true
                text: view.audio.statusMessage
                color: "#d2e5eb"
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                ToolTip.visible: statusHover.hovered && truncated
                ToolTip.text: text
                HoverHandler { id: statusHover }
            }
        }
    }

    GlassShard {
        id: playback
        x: gain.width + 6
        y: 12
        width: view.width - x - 3
        height: 138
        material: view.material
        points: [Qt.point(0.005, 0.35), Qt.point(0.055, 0.18), Qt.point(0.46, 0.012),
            Qt.point(0.961, 0.205), Qt.point(0.992, 0.79), Qt.point(0.76, 0.985),
            Qt.point(0.08, 0.9)]
        onGeometryChanged: view.shardGeometryChanged()

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 25
            anchors.rightMargin: 23
            anchors.topMargin: 20
            anchors.bottomMargin: 19
            spacing: 5

            Label { text: qsTr("Playback"); color: "#f3fbff"; font.pixelSize: 19; font.weight: Font.DemiBold }
            ComboBox {
                id: outputChoice
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
                Accessible.name: qsTr("Playback device")
                onActivated: view.audio.selectedOutDevice = currentValue

                contentItem: Label {
                    leftPadding: 10
                    rightPadding: 27
                    text: outputChoice.displayText
                    color: "#f3fcff"
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                indicator: Text {
                    x: outputChoice.width - width - 12
                    y: (outputChoice.height - height) / 2 - 2
                    text: "⌄"
                    color: "#caecec"
                    font.pixelSize: 20
                }
                background: Rectangle {
                    implicitHeight: 34
                    radius: 7
                    color: outputChoice.hovered ? "#a13d6471" : "#73315365"
                    border.color: outputChoice.visualFocus ? "#a8f0e4" : "#739fc4ce"
                    border.width: outputChoice.visualFocus ? 2 : 1
                }
            }
            Label {
                Layout.fillWidth: true
                text: view.audio.selectedOutDevice === "" ? qsTr("Automatic playback") : qsTr("Selected playback device")
                color: "#c6dfe8"
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }

    GlassShard {
        id: effects
        x: playback.x - 3
        y: playback.y + playback.height + 1
        width: view.width - x
        height: Math.min(287, view.height - y - 14)
        material: view.material
        points: [Qt.point(0.055, 0.15), Qt.point(0.13, 0.012), Qt.point(0.73, 0.061),
            Qt.point(0.94, 0.16), Qt.point(0.991, 0.83), Qt.point(0.93, 0.92),
            Qt.point(0.2, 0.99), Qt.point(0.005, 0.82)]
        onGeometryChanged: view.shardGeometryChanged()

        Label {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 21
            anchors.bottomMargin: 27
            text: "◢"
            color: "#83c0c9"
            Accessible.name: qsTr("Resize window")
            MouseArea {
                anchors.fill: parent
                anchors.margins: -5
                cursorShape: Qt.SizeFDiagCursor
                onPressed: view.resizeRequested()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 27
            anchors.rightMargin: 26
            anchors.topMargin: 21
            anchors.bottomMargin: 23
            spacing: 3

            Label { text: qsTr("Audio effects"); color: "#f3fbff"; font.pixelSize: 19; font.weight: Font.DemiBold }
            GlassSwitch {
                Layout.fillWidth: true
                text: qsTr("Soft limiter")
                checked: view.audio.limiterEnabled
                onToggled: view.audio.limiterEnabled = checked
            }
            GlassSwitch {
                Layout.fillWidth: true
                text: qsTr("SuperBoost Clarity")
                checked: view.audio.superBoost
                onToggled: view.audio.superBoost = checked
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Bass boost"); color: "#f0fbff" }
                Item { Layout.fillWidth: true }
                Label { text: Math.round(view.audio.bassBoost * 100) + "%"; color: "#a2f2de" }
            }
            Slider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: view.audio.bassBoost
                Accessible.name: qsTr("Bass boost")
                onMoved: view.audio.bassBoost = value
            }
            Item { Layout.fillHeight: true }
        }
    }

    GlassShard {
        id: meter
        x: 12
        y: gain.height + 15
        width: gain.width - 6
        height: 105
        material: view.material
        points: [Qt.point(0.005, 0.47), Qt.point(0.08, 0.08), Qt.point(0.38, 0.02),
            Qt.point(0.93, 0.11), Qt.point(0.99, 0.54), Qt.point(0.91, 0.91),
            Qt.point(0.54, 0.89), Qt.point(0.087, 0.982), Qt.point(0.038, 0.82)]
        onGeometryChanged: view.shardGeometryChanged()

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 31
            anchors.rightMargin: 29
            anchors.topMargin: 12
            anchors.bottomMargin: 20
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Output level"); color: "#f3fbff"; font.pixelSize: 14; font.weight: Font.DemiBold }
                Item { Layout.fillWidth: true }
                Label {
                    visible: view.audio.limiterReduction > 0.03
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
                    readonly property real peak: index === 0 ? view.audio.outputPeakL : view.audio.outputPeakR
                    Layout.fillWidth: true
                    Label { text: peakRow.modelData; color: "#d4f3ee"; font.pixelSize: 10 }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: "#527997a4"
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
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2
                Repeater {
                    model: 24
                    Item {
                        required property int index
                        width: (parent.width - 46) / 24
                        height: parent.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(1, parent.height * Math.min(1, view.audio.spectrumBands[index] || 0))
                            color: "#85cad1"
                            radius: 1
                        }
                    }
                }
            }
        }
    }
}
