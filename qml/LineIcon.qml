import QtQuick

Canvas {
    id: icon

    required property string name
    property color color: "#f8f5fc"

    implicitWidth: 20
    implicitHeight: 20

    onNameChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function line(ctx, points) {
        ctx.beginPath()
        ctx.moveTo(points[0][0], points[0][1])
        for (let i = 1; i < points.length; ++i)
            ctx.lineTo(points[i][0], points[i][1])
        ctx.stroke()
    }

    function circle(ctx, x, y, radius) {
        ctx.beginPath()
        ctx.arc(x, y, radius, 0, 2 * Math.PI)
        ctx.stroke()
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        ctx.scale(width / 24, height / 24)
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = 1.65
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        switch (name) {
        case "boost":
            for (let i = 0; i < 4; ++i)
                line(ctx, [[4 + 5 * i, 20], [4 + 5 * i, 15 - 4 * i]])
            break
        case "mixer":
            for (let i = 0; i < 3; ++i) {
                const y = 5 + 7 * i
                const x = i === 1 ? 8 : 16
                line(ctx, [[2, y], [x - 2.5, y]])
                circle(ctx, x, y, 2.5)
                line(ctx, [[x + 2.5, y], [22, y]])
            }
            break
        case "menu":
            for (let i = 0; i < 3; ++i)
                line(ctx, [[3, 5 + 7 * i], [21, 5 + 7 * i]])
            break
        case "minimize":
            line(ctx, [[5, 12], [19, 12]])
            break
        case "maximize":
            ctx.strokeRect(5, 5, 14, 14)
            break
        case "restore":
            line(ctx, [[8, 6], [8, 3], [21, 3], [21, 16], [18, 16]])
            ctx.strokeRect(3, 8, 13, 13)
            break
        case "close":
            line(ctx, [[6, 6], [18, 18]])
            line(ctx, [[6, 18], [18, 6]])
            break
        case "expand":
            line(ctx, [[4, 9], [12, 17], [20, 9]])
            break
        case "playback":
            ctx.beginPath()
            ctx.arc(12, 11, 9, Math.PI, 2 * Math.PI)
            ctx.stroke()
            line(ctx, [[3, 11], [3, 20], [7, 20], [7, 12], [3, 12]])
            line(ctx, [[21, 11], [21, 20], [17, 20], [17, 12], [21, 12]])
            break
        case "effects":
            for (let i = 0; i < 5; ++i) {
                const amplitude = [3, 6, 10, 6, 3][i]
                line(ctx, [[3 + 4.5 * i, 12 - amplitude], [3 + 4.5 * i, 12 + amplitude]])
            }
            break
        case "output":
            line(ctx, [[2, 9], [6, 9], [11, 5], [11, 19], [6, 15], [2, 15], [2, 9]])
            for (const radius of [5, 9]) {
                ctx.beginPath()
                ctx.arc(13, 12, radius, -0.85, 0.85)
                ctx.stroke()
            }
            break
        case "muted":
            line(ctx, [[2, 9], [6, 9], [11, 5], [11, 19], [6, 15], [2, 15], [2, 9]])
            ctx.strokeStyle = "#f87171"
            line(ctx, [[15, 9], [21, 15]])
            line(ctx, [[21, 9], [15, 15]])
            break
        case "appearance":
            ctx.strokeRect(2, 3, 20, 14)
            line(ctx, [[12, 17], [12, 22]])
            line(ctx, [[8, 22], [16, 22]])
            break
        case "updates":
            for (const angle of [-2.7, 0.45]) {
                ctx.beginPath()
                ctx.arc(12, 12, 8.6, angle, angle + 2.3)
                ctx.stroke()
            }
            line(ctx, [[20, 4], [20, 9], [15, 9]])
            line(ctx, [[4, 20], [4, 15], [9, 15]])
            break
        case "settings": {
            const teeth = []
            for (let i = 0; i < 32; ++i) {
                const angle = (i + 0.5) * Math.PI / 16
                const radius = (i % 4 === 1 || i % 4 === 2) ? 10 : 7.9
                teeth.push([12 + radius * Math.cos(angle), 12 + radius * Math.sin(angle)])
            }
            line(ctx, teeth.concat([teeth[0]]))
            circle(ctx, 12, 12, 3.4)
            break
        }
        case "resize":
            for (let i = 0; i < 5; ++i) {
                const x = 3 + 4 * i
                const y = 20 - 4 * i
                ctx.beginPath()
                ctx.arc(x, y, 0.85, 0, 2 * Math.PI)
                if (i > 0 && i < 4) {
                    ctx.moveTo(x + 2.85, y + 2)
                    ctx.arc(x + 2, y + 2, 0.85, 0, 2 * Math.PI)
                }
                ctx.fill()
            }
            break
        case "pause":
            ctx.fillRect(6, 4, 4, 16)
            ctx.fillRect(14, 4, 4, 16)
            break
        case "play":
            ctx.beginPath()
            ctx.moveTo(7, 4)
            ctx.lineTo(20, 12)
            ctx.lineTo(7, 20)
            ctx.closePath()
            ctx.fill()
            break
        }
    }
}
