import QtQuick

Item {
    id: shard

    property string material: "clear"
    // Coordinates are fractions of this shard's width and height.
    property var points: [Qt.point(0.025, 0.08), Qt.point(0.15, 0.015), Qt.point(0.65, 0.03),
        Qt.point(0.96, 0.015), Qt.point(0.995, 0.12), Qt.point(0.98, 0.89),
        Qt.point(0.92, 0.99), Qt.point(0.05, 0.96), Qt.point(0.005, 0.78)]
    signal geometryChanged()

    onPointsChanged: { face.requestPaint(); geometryChanged() }
    onMaterialChanged: face.requestPaint()
    onXChanged: geometryChanged()
    onYChanged: geometryChanged()
    onWidthChanged: { face.requestPaint(); geometryChanged() }
    onHeightChanged: { face.requestPaint(); geometryChanged() }
    onVisibleChanged: geometryChanged()

    function windowPolygon() {
        return points.map(point => mapToItem(null, point.x * (width - 2) + 1, point.y * (height - 2) + 1))
    }

    readonly property var finish: {
        switch (material) {
        case "acrylic": return ["#941f5263", "#b80a2635", "#a0bcf7f4", "#70a9f2ed"]
        case "mica": return ["#d32c4758", "#e3152635", "#958ce7e3", "#5692adc3"]
        case "blurred": return ["#65323c56", "#9d152436", "#a1c8f4ff", "#6398c1db"]
        case "frosted": return ["#9c5c7985", "#d32b4655", "#e4dbfcff", "#ab9dc5ce"]
        case "glassy": return ["#85165265", "#9406212d", "#ded5fffc", "#9277dacc"]
        default: return ["#95163642", "#ad071e2c", "#c6c0f9f3", "#9279d9d8"]
        }
    }
    readonly property color topTint: finish[0]
    readonly property color bottomTint: finish[1]
    readonly property color edgeHighlight: finish[2]
    readonly property color edgeMidtone: finish[3]

    Canvas {
        id: face
        anchors.fill: parent

        onPaint: {
            if (width <= 0 || height <= 0) return
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const inset = 1
            ctx.beginPath()
            for (let i = 0; i < shard.points.length; ++i) {
                const point = shard.points[i]
                const x = inset + point.x * (width - 2 * inset)
                const y = inset + point.y * (height - 2 * inset)
                if (i === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
            }
            ctx.closePath()
            const tint = ctx.createLinearGradient(0, 0, width * 0.22, height)
            tint.addColorStop(0, shard.topTint)
            tint.addColorStop(1, shard.bottomTint)
            ctx.fillStyle = tint
            ctx.fill()

            if (shard.material === "acrylic" || shard.material === "frosted" || shard.material === "glassy") {
                ctx.save()
                ctx.clip()
                if (shard.material === "glassy") {
                    const sheen = ctx.createLinearGradient(0, height * 0.65, width, 0)
                    sheen.addColorStop(0, "transparent")
                    sheen.addColorStop(0.45, Qt.rgba(1, 1, 1, 0.055))
                    sheen.addColorStop(0.55, Qt.rgba(0.82, 1, 1, 0.146))
                    sheen.addColorStop(0.66, "transparent")
                    ctx.fillStyle = sheen
                    ctx.fillRect(0, 0, width, height)
                } else {
                    // Fixed grain keeps acrylic and frost stable through repaints.
                    ctx.fillStyle = Qt.rgba(1, 1, 1, shard.material === "frosted" ? 0.10 : 0.055)
                    for (let i = 0; i < width * height / 57; ++i) {
                        const x = (i * 4177 % 8513) * width / 8513
                        const y = (i * 6659 % 8377) * height / 8377
                        ctx.fillRect(x, y, 1, 1)
                    }
                }
                ctx.restore()
            }

            const edge = ctx.createLinearGradient(0, 0, width * 0.8, height)
            edge.addColorStop(0, shard.edgeHighlight)
            edge.addColorStop(0.49, shard.edgeMidtone)
            edge.addColorStop(1, shard.edgeHighlight)
            ctx.strokeStyle = edge
            ctx.lineJoin = "round"
            ctx.lineWidth = shard.material === "glassy" ? 2 : 1.25
            ctx.stroke()
        }
    }
}
