import QtQuick
import QtQuick.Window
import SuperBoosterUI

Item {
    id: shard

    property string material: "clear"
    readonly property bool samplesWallpaper: material === "blurred" || material === "acrylic" || material === "mica"
    // Coordinates are fractions of this shard's width and height.
    property var points: [Qt.point(0.025, 0.08), Qt.point(0.15, 0.015), Qt.point(0.65, 0.03),
        Qt.point(0.96, 0.015), Qt.point(0.995, 0.12), Qt.point(0.98, 0.89),
        Qt.point(0.92, 0.99), Qt.point(0.05, 0.96), Qt.point(0.005, 0.78)]
    signal geometryChanged()

    onPointsChanged: geometryChanged()
    onXChanged: geometryChanged()
    onYChanged: geometryChanged()
    onWidthChanged: geometryChanged()
    onHeightChanged: geometryChanged()
    onVisibleChanged: geometryChanged()

    function windowPolygon() {
        const origin = mapToItem(null, 1, 1)
        const right = mapToItem(null, width - 1, 1)
        const bottom = mapToItem(null, 1, height - 1)
        const horizontal = Qt.point(right.x - origin.x, right.y - origin.y)
        const vertical = Qt.point(bottom.x - origin.x, bottom.y - origin.y)
        return points.map(point => Qt.point(
            origin.x + point.x * horizontal.x + point.y * vertical.x,
            origin.y + point.x * horizontal.y + point.y * vertical.y))
    }

    GlassFace {
        anchors.fill: parent
        material: shard.material
        points: shard.points
        wallpaper: winHelper.wallpaper
        wallpaperGeometry: winHelper.wallpaperGeometry
        screenPosition: {
            if (!shard.samplesWallpaper)
                return Qt.point(0, 0)
            const window = shard.Window.window
            if (!window || !shard.parent || window.width < 1 || window.height < 1)
                return Qt.point(0, 0)
            const origin = shard.parent.mapToItem(null, shard.x, shard.y)
            return Qt.point(window.x + origin.x, window.y + origin.y)
        }
    }
}
