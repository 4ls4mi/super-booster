#include "glass_face.h"

#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QRadialGradient>
#include <QRandomGenerator>

namespace {

struct Finish {
    QRgb top;
    QRgb bottom;
    QRgb light;
    QRgb accent;
    QRgb edge;
    QRgb edgeAccent;
    qreal sampleOpacity;
    qreal grainOpacity;
};

Finish finishFor(const QString& name) {
    if (name == QLatin1String("acrylic")) {
        return {0xbd254353, 0xd1112437, 0x4b91e2e0, 0x196499b3, 0xd3c8f5ef, 0xa872baca, 0.22, 0.44};
    }
    if (name == QLatin1String("mica")) {
        return {0xe12d3c59, 0xee1c253c, 0x2fb0bddb, 0x3057527b, 0xc8c3d6eb, 0x927b96ba, 0.28, 0};
    }
    if (name == QLatin1String("blurred")) {
        return {0x85404c69, 0xa922233c, 0x6699aecf, 0x456482b7, 0xd3c5d7f4, 0xac9b9ed2, 0.86, 0};
    }
    if (name == QLatin1String("frosted")) {
        return {0xb343395e, 0xb934274d, 0x539ea5d1, 0x655f427f, 0xe6dce9fc, 0xddca93e9, 0, 0.36};
    }
    if (name == QLatin1String("glassy")) {
        return {0x963d345e, 0xb414132c, 0x3198c6e2, 0x28977bc8, 0xf5eaecff, 0xe3a7a0ea, 0, 0};
    }
    return {0x68233440, 0x9c161f32, 0x176ca8b0, 0x1d6c579f, 0xb7c3edea, 0x9b8ba4bd, 0, 0};
}

const QImage& grainTexture() {
    static const QImage texture = [] {
        QImage image(96, 96, QImage::Format_ARGB32_Premultiplied);
        QRandomGenerator random(0x534247U);
        for (int y = 0; y < image.height(); ++y) {
            auto* scan = reinterpret_cast<QRgb*>(image.scanLine(y));
            for (int x = 0; x < image.width(); ++x) {
                const quint32 sample = random.generate();
                const int shade = (sample & 1) ? 255 : 0;
                const int alpha = 3 + ((sample >> 1) % 29);
                scan[x] = qPremultiply(qRgba(shade, shade, shade, alpha));
            }
        }
        return image;
    }();
    return texture;
}

void paintHaze(QPainter* painter, const QRectF& bounds, const QPointF& origin,
               qreal radius, QRgb color) {
    QRadialGradient gradient(origin, radius);
    gradient.setColorAt(0, QColor::fromRgba(color));
    gradient.setColorAt(1, Qt::transparent);
    painter->fillRect(bounds, gradient);
}

}

GlassFace::GlassFace(QQuickItem* parent) : QQuickPaintedItem(parent) {
    setAntialiasing(true);
}

void GlassFace::setPoints(const QVariantList& points) {
    if (m_points == points) return;
    m_points = points;
    update();
    emit pointsChanged();
}

void GlassFace::setMaterial(const QString& material) {
    if (m_material == material) return;
    m_material = material;
    update();
    emit materialChanged();
}

void GlassFace::setWallpaper(const QVariant& wallpaper) {
    const auto image = wallpaper.value<QImage>();
    if (m_wallpaper.cacheKey() == image.cacheKey()) return;
    m_wallpaper = image;
    if (finishFor(m_material).sampleOpacity > 0) update();
    emit wallpaperChanged();
}

void GlassFace::setWallpaperGeometry(const QRect& geometry) {
    if (m_wallpaperGeometry == geometry) return;
    m_wallpaperGeometry = geometry;
    if (finishFor(m_material).sampleOpacity > 0) update();
    emit wallpaperGeometryChanged();
}

void GlassFace::setScreenPosition(const QPointF& position) {
    if (m_screenPosition == position) return;
    m_screenPosition = position;
    if (finishFor(m_material).sampleOpacity > 0) update();
    emit screenPositionChanged();
}

void GlassFace::paint(QPainter* painter) {
    if (m_points.size() < 3 || width() <= 2 || height() <= 2) return;

    const QRectF bounds(0, 0, width(), height());
    QPolygonF polygon;
    polygon.reserve(m_points.size());
    for (const QVariant& pointValue : m_points) {
        const QPointF point = pointValue.toPointF();
        // Keep the exact same contour for paint as GlassShard.windowPolygon().
        polygon.append(QPointF(1 + point.x() * (width() - 2), 1 + point.y() * (height() - 2)));
    }
    QPainterPath pane;
    pane.addPolygon(polygon);
    pane.closeSubpath();

    const Finish finish = finishFor(m_material);
    painter->save();
    painter->setClipPath(pane);
    const bool useWallpaper = finish.sampleOpacity > 0 && !m_wallpaper.isNull()
        && !m_wallpaperGeometry.isEmpty();
    if (useWallpaper) {
        painter->setRenderHint(QPainter::SmoothPixmapTransform);
        painter->setOpacity(finish.sampleOpacity);
        const QRectF localWallpaper = QRectF(m_wallpaperGeometry).translated(-m_screenPosition);
        painter->drawImage(localWallpaper, m_wallpaper);
        painter->setOpacity(1);
    }

    QLinearGradient tint(0, 0, width() * 0.3, height());
    tint.setColorAt(0, QColor::fromRgba(finish.top));
    tint.setColorAt(1, QColor::fromRgba(finish.bottom));
    painter->fillRect(bounds, tint);

    const qreal extent = qMax(width(), height());
    if (m_material != QLatin1String("blurred") || !useWallpaper) {
        paintHaze(painter, bounds, QPointF(width() * 0.12, 0), extent * 0.67, finish.light);
        paintHaze(painter, bounds, QPointF(width() * 0.82, height() * 1.08), extent * 0.61, finish.accent);
    }

    if (finish.grainOpacity > 0) {
        painter->setOpacity(finish.grainOpacity);
        painter->fillRect(bounds, QBrush(grainTexture()));
        painter->setOpacity(1);
    }
    if (m_material == QLatin1String("glassy")) {
        QLinearGradient reflection(width() * 0.13, 0, width(), height() * 0.9);
        reflection.setColorAt(0.00, Qt::transparent);
        reflection.setColorAt(0.20, QColor(209, 216, 255, 88));
        reflection.setColorAt(0.23, QColor(231, 226, 255, 57));
        reflection.setColorAt(0.25, Qt::transparent);
        reflection.setColorAt(0.37, QColor(220, 242, 255, 40));
        reflection.setColorAt(0.41, Qt::transparent);
        painter->fillRect(bounds, reflection);
    }

    const QColor edge = QColor::fromRgba(finish.edge);
    const QColor edgeAccent = QColor::fromRgba(finish.edgeAccent);
    QLinearGradient bevel(0, 0, width() * 0.84, height());
    bevel.setColorAt(0.00, edge);
    bevel.setColorAt(0.45, edgeAccent);
    bevel.setColorAt(0.72, edge);
    bevel.setColorAt(1.00, edgeAccent);
    painter->setOpacity(0.12);
    painter->strokePath(pane, QPen(QBrush(bevel), 6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    painter->restore();

    const qreal edgeWidth = m_material == QLatin1String("glassy") ? 1.65 : 1.20;
    painter->strokePath(pane, QPen(QBrush(bevel), edgeWidth, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
}
