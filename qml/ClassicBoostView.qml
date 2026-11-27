pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: view
    objectName: "superBoosterClassicBoostView"

    required property var audio

    readonly property color cyan: "#38bdf8"
    readonly property color accent: !audio.engineActive ? cyan
        : audio.volume > 300 ? "#ff6d3b" : audio.volume > 150 ? cyan : "#2ecc71"
    readonly property bool showMeters: visible && view.Window.window?.visibility !== Window.Minimized
    readonly property bool useShaders: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property real peak: showMeters ? Math.max(audio.outputPeakL, audio.outputPeakR) : 0
    readonly property var spectrumBands: showMeters ? audio.spectrumBands : []
    property real shaderTime: 0

    FrameAnimation {
        running: view.showMeters && view.useShaders
        onTriggered: view.shaderTime += frameTime
    }

    component Card: Rectangle {
        id: card

        property color edgeColor: "#36d5eefa"

        radius: 14
        border.color: edgeColor
        gradient: Gradient {
            GradientStop { position: 0; color: "#13111c29" }
            GradientStop { position: 1; color: "#42101c30" }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.radius * 0.65
            anchors.rightMargin: anchors.leftMargin
            height: 1
            color: "#38e8f9ff"
        }
    }

    component ClassicSlider: BoostSlider {
        id: slider

        property int thumbSize: 20

        implicitHeight: 24
        background: Rectangle {
            x: slider.leftPadding + thumb.width * 0.5
            y: slider.topPadding + (slider.availableHeight - height) * 0.5
            width: slider.availableWidth - thumb.width
            height: 8
            radius: 4
            color: "#36c8d8e6"
            border.color: "#204c92b3"

            Rectangle {
                width: parent.width * slider.visualPosition
                height: parent.height
                radius: parent.radius
                color: slider.accentColor
            }
        }

        handle: Rectangle {
            id: thumb
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + (slider.availableHeight - height) * 0.5
            width: slider.thumbSize
            height: width
            radius: width * 0.5
            color: "#f8fafc"
            border.color: slider.visualFocus ? "#a3e8ff" : slider.accentColor
            border.width: slider.visualFocus || slider.pressed ? 3 : 2

            Rectangle {
                anchors.centerIn: parent
                width: thumb.width * 0.28
                height: width
                radius: width * 0.5
                color: slider.accentColor
                visible: slider.thumbSize === 20
            }
        }
    }

    component EffectToggle: Switch {
        id: toggle

        required property color checkedColor

        implicitHeight: 23
        padding: 0
        spacing: 10

        indicator: Rectangle {
            y: (toggle.height - height) * 0.5
            width: 34
            height: 18
            radius: height * 0.5
            color: toggle.checked ? toggle.checkedColor : "#36c7d9e7"
            border.color: toggle.visualFocus ? "#b9efff" : "#50dcefff"
            border.width: toggle.visualFocus ? 2 : 1

            Rectangle {
                x: toggle.checked ? parent.width - width - 2 : 2
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: width
                radius: width * 0.5
                color: "#f8fafc"
                Behavior on x { NumberAnimation { duration: 120 } }
            }
        }

        contentItem: Label {
            leftPadding: toggle.indicator.width + toggle.spacing
            text: toggle.text
            color: "#e2e8f0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        Card {
            objectName: "superBoosterClassicHero"
            Layout.preferredWidth: Math.min(235, view.width * 0.385)
            Layout.minimumWidth: 160
            Layout.fillHeight: true
            edgeColor: view.audio.engineActive ? "#572ecc71" : "#36d5eefa"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ShaderEffect {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width
                        visible: view.useShaders
                        property real u_time: view.shaderTime
                        property real u_boostNorm: view.audio.volume / 500
                        property real u_peakLevel: Math.min(1, view.peak)
                        property real u_active: view.audio.engineActive ? 1 : 0
                        property real u_superBoost: view.audio.superBoost ? 1 : 0
                        fragmentShader: "qrc:/shaders/audio_orb.frag.qsb"
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) * 0.66
                        height: width
                        radius: width * 0.5
                        visible: !view.useShaders
                        color: "#101c2b"
                        border.width: 2
                        border.color: view.audio.engineActive ? view.accent : "#658eb3"
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(view.audio.volume) + "%"
                            color: "#ffffff"
                            font.pixelSize: 38
                            font.weight: Font.Bold
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: view.audio.decibelText
                            color: view.accent
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: view.audio.volume > 300 ? qsTr("SUPER OVERDRIVE")
                                : view.audio.volume > 100 ? qsTr("BOOST")
                                : view.audio.volume < 100 ? qsTr("ATTENUATION") : qsTr("UNITY LEVEL")
                            color: "#b3c6d8"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                    }
                }

                Button {
                    id: power
                    Layout.fillWidth: true
                    implicitHeight: 40
                    text: view.audio.engineActive ? qsTr("BOOST ON — PAUSE")
                        : view.audio.engineStarting ? qsTr("CONNECTING — CANCEL")
                        : view.audio.audioSetupIssue ? qsTr("SET UP BOOST") : qsTr("START BOOST")
                    onClicked: view.audio.toggleEngine()

                    contentItem: RowLayout {
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            implicitWidth: 9
                            implicitHeight: 9
                            radius: width * 0.5
                            color: view.audio.engineActive ? "#bbf7d0" : "#bfdbfe"
                        }
                        Label {
                            text: power.text
                            color: "#ffffff"
                            font.pixelSize: power.width < 153 ? 10 : 12
                            font.weight: Font.Bold
                            font.letterSpacing: 0.5
                        }
                        Item { Layout.fillWidth: true }
                    }
                    background: Rectangle {
                        radius: 10
                        color: view.audio.engineActive ? (power.hovered ? "#16a34a" : "#15803d")
                            : (power.hovered ? "#2563eb" : "#1d4ed8")
                        border.color: power.visualFocus ? "#e1f4ff" : "#60cbecff"
                        border.width: power.visualFocus ? 2 : 1
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Card {
                objectName: "superBoosterClassicGain"
                Layout.fillWidth: true
                Layout.preferredHeight: 132
                Layout.minimumHeight: 132

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: qsTr("Amplification Gain")
                            color: "#f1f5f9"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: qsTr("Hotkeys: Ctrl+Alt+↑/↓/B")
                            color: "#aac0d3"
                            font.pixelSize: 10
                        }
                    }

                    ClassicSlider {
                        id: gainSlider
                        objectName: "superBoosterClassicGainSlider"
                        Layout.fillWidth: true
                        from: view.audio.directMode ? 100 : 0
                        value: view.audio.volume
                        accentColor: view.accent
                        Accessible.name: qsTr("Amplification gain")
                        onMoved: {
                            view.audio.volume = value
                            if (!pressed) view.audio.applyBoostLevel(value)
                        }
                        onPressedChanged: if (!pressed) view.audio.applyBoostLevel(value)
                    }

                    Item {
                        id: ticks
                        Layout.fillWidth: true
                        implicitHeight: 14

                        Repeater {
                            model: view.audio.directMode ? [100, 200, 300, 400, 500] : [0, 100, 200, 300, 400, 500]

                            Label {
                                required property int modelData
                                readonly property real fraction: (modelData - gainSlider.from)
                                    / (gainSlider.to - gainSlider.from)
                                x: Math.max(0, Math.min(ticks.width - width, ticks.width * fraction - width * 0.5))
                                text: modelData + "%"
                                color: modelData === 100 ? "#c3f7ed" : "#a0b8cf"
                                font.pixelSize: 10
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [100, 150, 200, 300, 400, 500]

                            Button {
                                id: preset
                                required property int modelData
                                readonly property bool selected: Math.abs(view.audio.volume - modelData) < 8
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: 24
                                padding: 1
                                text: modelData + "%"
                                onClicked: view.audio.applyBoostLevel(modelData)

                                contentItem: Label {
                                    text: preset.text
                                    color: "#edf6fd"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 6
                                    color: preset.selected ? "#4538bdf8" : preset.hovered ? "#36c7d9e7" : "#22c7d9e7"
                                    border.color: preset.visualFocus ? "#baeeff"
                                        : preset.selected ? "#9938bdf8" : "#35d5eefa"
                                    border.width: preset.visualFocus ? 2 : 1
                                }
                            }
                        }
                    }
                }
            }

            Card {
                objectName: "superBoosterClassicEffects"
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                Layout.minimumHeight: 92

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    ColumnLayout {
                        Layout.preferredWidth: parent.width * 0.58
                        Layout.minimumWidth: 157
                        spacing: 5

                        EffectToggle {
                            Layout.fillWidth: true
                            text: qsTr("SuperBoost Clarity")
                            checked: view.audio.superBoost
                            checkedColor: "#22c55e"
                            onToggled: view.audio.superBoost = checked
                        }
                        EffectToggle {
                            Layout.fillWidth: true
                            text: qsTr("Anti-Clip Soft Limiter")
                            checked: view.audio.limiterEnabled
                            checkedColor: view.cyan
                            onToggled: view.audio.limiterEnabled = checked
                        }
                    }

                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: 1
                        color: "#35d5eefa"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                text: qsTr("Bass Depth")
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            Label {
                                text: Math.round(view.audio.bassBoost * 100) + "%"
                                color: "#73d7fd"
                                font.pixelSize: 11
                            }
                        }

                        ClassicSlider {
                            Layout.fillWidth: true
                            from: 0
                            to: 1
                            stepSize: 0
                            thumbSize: 16
                            accentColor: view.cyan
                            value: view.audio.bassBoost
                            Accessible.name: qsTr("Bass depth")
                            onMoved: view.audio.bassBoost = value
                        }
                    }
                }
            }

            Card {
                objectName: "superBoosterClassicMeter"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 72

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("LIVE SPECTRUM & OUTPUT PEAK")
                            color: "#b3c6d8"
                            font.pixelSize: 10
                            font.letterSpacing: 0.6
                            elide: Text.ElideRight
                        }
                        Label {
                            readonly property bool limiting: view.showMeters && view.audio.limiterReduction > 0.03
                            text: limiting ? qsTr("LIMITER ENGAGED")
                                : view.peak > 0.002 ? qsTr("SIGNAL") : qsTr("STANDBY")
                            color: limiting ? "#ffb571" : "#69f1a1"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ShaderEffect {
                            anchors.fill: parent
                            visible: view.useShaders
                            property real u_time: view.shaderTime
                            property real u_boostNorm: view.audio.volume / 500
                            property real u_peakLevel: Math.min(1, view.peak)
                            property real u_active: view.audio.engineActive ? 1 : 0
                            property real u_limiterHit: view.showMeters ? Math.min(1, view.audio.limiterReduction * 3) : 0
                            fragmentShader: "qrc:/shaders/spectrum_glow.frag.qsb"
                        }

                        Row {
                            id: spectrum
                            anchors.fill: parent
                            spacing: 4

                            Repeater {
                                model: 24

                                Item {
                                    id: band
                                    required property int index
                                    width: (spectrum.width - 23 * spectrum.spacing) / 24
                                    height: spectrum.height

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: Math.min(parent.height,
                                            Math.max(4, parent.height * Math.min(1, view.spectrumBands[band.index] || 0)))
                                        radius: 3
                                        gradient: Gradient {
                                            GradientStop {
                                                position: 0
                                                color: view.audio.volume > 300 ? "#fb923c" : view.cyan
                                            }
                                            GradientStop { position: 1; color: "#2ecc71" }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: ["L", "R"]

                            RowLayout {
                                id: channel
                                required property int index
                                required property string modelData
                                readonly property real level: view.showMeters
                                    ? (index === 0 ? view.audio.outputPeakL : view.audio.outputPeakR) : 0
                                Layout.fillWidth: true
                                spacing: 8

                                Label {
                                    text: channel.modelData
                                    color: "#b3c6d8"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 5
                                    radius: height * 0.5
                                    color: "#33d8e9f6"

                                    Rectangle {
                                        width: parent.width * Math.min(1, channel.level)
                                        height: parent.height
                                        radius: parent.radius
                                        color: channel.level > 0.9 ? "#fb923c" : "#2ecc71"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
