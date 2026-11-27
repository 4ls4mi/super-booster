#pragma once

#include <QImage>
#include <QQuickPaintedItem>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class GlassFace : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantList points READ points WRITE setPoints NOTIFY pointsChanged)
    Q_PROPERTY(QString material READ material WRITE setMaterial NOTIFY materialChanged)
    Q_PROPERTY(QVariant wallpaper READ wallpaper WRITE setWallpaper NOTIFY wallpaperChanged)
    Q_PROPERTY(QRect wallpaperGeometry READ wallpaperGeometry WRITE setWallpaperGeometry NOTIFY wallpaperGeometryChanged)
    Q_PROPERTY(QPointF screenPosition READ screenPosition WRITE setScreenPosition NOTIFY screenPositionChanged)

public:
    explicit GlassFace(QQuickItem* parent = nullptr);
    void paint(QPainter* painter) override;

    QVariantList points() const { return m_points; }
    QString material() const { return m_material; }
    QVariant wallpaper() const { return QVariant::fromValue(m_wallpaper); }
    QRect wallpaperGeometry() const { return m_wallpaperGeometry; }
    QPointF screenPosition() const { return m_screenPosition; }
    void setPoints(const QVariantList& points);
    void setMaterial(const QString& material);
    void setWallpaper(const QVariant& wallpaper);
    void setWallpaperGeometry(const QRect& geometry);
    void setScreenPosition(const QPointF& position);

signals:
    void pointsChanged();
    void materialChanged();
    void wallpaperChanged();
    void wallpaperGeometryChanged();
    void screenPositionChanged();

private:
    QVariantList m_points;
    QString m_material;
    QImage m_wallpaper;
    QRect m_wallpaperGeometry;
    QPointF m_screenPosition;
};
