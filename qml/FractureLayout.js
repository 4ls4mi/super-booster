.pragma library

// Each fracture is defined once in the drawing's coordinate space. A pane follows
// the same curve as its neighbor in reverse, with a small inset on either side.
const brandCommand = edge([[899, 78], [913, 97], [920, 117], [911, 144], [899, 169]])
const brandGain = edge([[55, 184], [78, 193], [111, 178], [192, 184], [210, 204],
    [304, 185], [428, 191], [465, 185], [491, 171], [545, 171], [581, 172]])
const brandPlayback = edge([[581, 172], [638, 171], [691, 173], [725, 147], [748, 138],
    [808, 155], [852, 155], [899, 169]])
const commandAppearance = edge([[899, 169], [947, 170], [968, 163], [1007, 165], [1032, 149],
    [1061, 151], [1101, 167], [1133, 173], [1175, 166], [1211, 171], [1281, 188]])
const gainPlayback = edge([[581, 172], [598, 221], [597, 247], [578, 283], [541, 307],
    [531, 331], [525, 358], [513, 376], [527, 392]])
const gainEffects = edge([[527, 392], [478, 385], [461, 405], [437, 443], [440, 465],
    [467, 504], [471, 530], [487, 549]])
const gainMeter = edge([[487, 549], [460, 537], [431, 545], [382, 549], [374, 571],
    [365, 613], [340, 641], [316, 652], [278, 695], [224, 696], [192, 718],
    [113, 716], [77, 729]])
const playbackEffects = edge([[527, 392], [575, 411], [611, 430], [667, 431],
    [708, 405], [766, 389], [811, 409], [846, 407], [863, 411]])
const playbackAppearance = edge([[899, 169], [910, 193], [909, 220], [885, 259],
    [912, 293], [914, 309], [900, 342], [864, 364], [856, 382], [863, 411]])
const effectsAppearance = edge([[863, 411], [884, 435], [902, 452], [909, 481],
    [897, 513], [868, 551], [860, 584], [883, 615], [879, 647]])
const effectsMeter = edge([[487, 549], [502, 573], [485, 611], [519, 634], [563, 656],
    [571, 680], [545, 712], [547, 730], [562, 770]])

const brandOuter = edge([[899, 78], [877, 68], [827, 84], [800, 86], [698, 75],
    [612, 68], [535, 61], [457, 66], [397, 56], [310, 73], [261, 84], [186, 76],
    [143, 75], [84, 71], [42, 87], [53, 122], [64, 143], [62, 161], [55, 184]])
const commandOuter = edge([[1281, 188], [1295, 148], [1319, 130], [1336, 86], [1321, 77],
    [1250, 86], [1170, 78], [1133, 60], [1080, 57], [990, 74], [950, 60], [925, 73], [899, 78]])
const gainOuter = edge([[77, 729], [48, 707], [55, 675], [75, 620], [66, 592], [41, 546],
    [47, 509], [62, 449], [65, 415], [64, 367], [53, 333], [32, 281], [28, 255],
    [43, 197], [55, 184]])
const meterOuter = edge([[562, 770], [575, 794], [550, 805], [485, 811], [389, 820],
    [288, 813], [260, 812], [196, 829], [119, 816], [55, 807], [45, 794],
    [62, 769], [77, 729]])
const effectsOuter = edge([[879, 647], [858, 689], [817, 704], [773, 719], [725, 697],
    [699, 705], [652, 755], [578, 771], [562, 770]])
const appearanceOuter = edge([[1281, 188], [1299, 225], [1288, 259], [1272, 294], [1277, 318],
    [1297, 355], [1292, 387], [1275, 427], [1270, 505], [1265, 616], [1263, 646],
    [1246, 666], [1200, 690], [1162, 728], [1143, 692], [1090, 694], [978, 706],
    [886, 722], [880, 711], [885, 665], [879, 647]])

function edge(vertices) {
    const result = [vertices[0]]
    for (let i = 1; i + 1 < vertices.length; ++i) {
        const before = vertices[i - 1]
        const corner = vertices[i]
        const after = vertices[i + 1]
        const start = toward(corner, before)
        const end = toward(corner, after)
        for (let j = 0; j <= 5; ++j) {
            const t = j / 5
            const u = 1 - t
            result.push([
                u * u * start[0] + 2 * u * t * corner[0] + t * t * end[0],
                u * u * start[1] + 2 * u * t * corner[1] + t * t * end[1]
            ])
        }
    }
    result.push(vertices[vertices.length - 1])
    return result
}

function toward(from, to) {
    const dx = to[0] - from[0]
    const dy = to[1] - from[1]
    const fraction = Math.min(0.34, 18 / Math.hypot(dx, dy))
    return [from[0] + dx * fraction, from[1] + dy * fraction]
}

function reverse(points) {
    return points.slice().reverse()
}

function shape(scale, edges, content) {
    const points = edges.reduce((result, segment) => result.concat(segment.slice(0, -1)), [])
        .map(point => [scale.x(point[0]), scale.y(point[1])])
    const area = points.reduce((total, point, index) => {
        const next = points[(index + 1) % points.length]
        return total + point[0] * next[1] - point[1] * next[0]
    }, 0)
    const inset = 2.4 * Math.sign(area)
    const insetPoints = points.map((point, index) => {
        const before = normal(points[(index + points.length - 1) % points.length], point)
        const after = normal(point, points[(index + 1) % points.length])
        const offset = inset / Math.max(0.45, 1 + before.x * after.x + before.y * after.y)
        return Qt.point(point[0] + (before.x + after.x) * offset, point[1] + (before.y + after.y) * offset)
    })
    // Reserve a pixel for the antialiased rim along the pane's item boundary.
    const x = Math.floor(Math.min(...insetPoints.map(point => point.x)) - 1)
    const y = Math.floor(Math.min(...insetPoints.map(point => point.y)) - 1)
    const width = Math.ceil(Math.max(...insetPoints.map(point => point.x)) + 1) - x
    const height = Math.ceil(Math.max(...insetPoints.map(point => point.y)) + 1) - y
    return {
        x, y, width, height,
        points: insetPoints.map(point => Qt.point((point.x - x - 1) / (width - 2), (point.y - y - 1) / (height - 2))),
        content: position(scale, content, x, y)
    }
}

function normal(from, to) {
    const dx = to[0] - from[0]
    const dy = to[1] - from[1]
    const length = Math.hypot(dx, dy)
    return { x: -dy / length, y: dx / length }
}

function position(scale, box, x, y) {
    return Qt.rect(scale.x(box[0]) - x, scale.y(box[1]) - y, box[2] * scale.sx, box[3] * scale.sy)
}

function arrange(width, height) {
    const sx = Math.max(100, width - 27) / 1310
    const sy = Math.max(100, height - 24) / 773
    const scale = { sx, sy, x: value => 13 + (value - 28) * sx, y: value => 11 + (value - 56) * sy }
    const brand = shape(scale, [reverse(brandOuter), brandCommand, reverse(brandPlayback), reverse(brandGain)],
                        [85, 88, 797, 66])
    const commands = shape(scale, [reverse(commandOuter), reverse(commandAppearance), reverse(brandCommand)],
                           [951, 89, 356, 64])
    const gain = shape(scale, [brandGain, gainPlayback, gainEffects, gainMeter, gainOuter], [113, 228, 281, 390])
    const playback = shape(scale, [brandPlayback, playbackAppearance, reverse(playbackEffects), reverse(gainPlayback)],
                           [615, 215, 251, 153])
    const effects = shape(scale, [playbackEffects, effectsAppearance, effectsOuter, reverse(effectsMeter),
        reverse(gainEffects)], [538, 455, 280, 204])
    const meter = shape(scale, [reverse(gainMeter), effectsMeter, meterOuter], [125, 729, 393, 74])
    const appearance = shape(scale, [commandAppearance, appearanceOuter, reverse(effectsAppearance),
        reverse(playbackAppearance)], [943, 215, 305, 447])
    const pages = shape(scale, [brandGain, brandPlayback, playbackAppearance, effectsAppearance, effectsOuter,
        meterOuter, gainOuter], [108, 220, 707, 423])
    const grip = position(scale, [814, 651, 46, 45], effects.x, effects.y)
    return { brand, commands, gain, playback, effects, meter, appearance, pages, grip }
}
