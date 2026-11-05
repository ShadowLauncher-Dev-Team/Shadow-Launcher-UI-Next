// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
// Shadow Launcher — 下载步骤不确定环（C++ 场景图实现）

#include "dl_spinner_item.h"

#include <QPointF>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGNode>
#include <QSGVertexColorMaterial>

#include <cmath>

namespace ShadowLauncher {

namespace {

constexpr qreal kPi = 3.14159265358979323846;

// 几何密度与抗锯齿宽度（逻辑像素）。
// 每段 <= 2°：16px 的环上单段弦高约 0.002px，肉眼与多边形化都看不出来。
constexpr int kTrackSegments = 180;
constexpr int kArcSegments = 120;
constexpr int kCapSegments = 12;
constexpr qreal kFeather = 0.55;

// ── 动画参数（Material 不确定环，按实机反馈调过两轮） ──
//   turn : 1.4s 一圈 + 正弦调速 —— 不是匀速画圈，快慢起伏出"惯性"
//   sweep: 1.4s 一个来回，弧长 90°..250° 呼吸，最长时压在最快的相位
//
// 为什么不照搬 CSS 的 spin+dashoffset：那份实现里容器转 1.6s/圈（+225°/s）、
// dashoffset 每 1.4s 反向移 42/50 圈（-216°/s），两者相抵只剩 +9.6°/s，
// 弧的起点几乎不动，看上去就是"转一点又缩回去"（第一轮实机反馈原话）。
// 现在：
//   弧心 = turn(t)            单调前进（测角度只看它）
//   两端 = turn(t) ∓ sweep/2  角速度恒为正，两极值互不同相，最慢也有 ~64°/s
// 两个端点都不会倒退，旋转 + 呼吸 + 甩动可以同时成立。
constexpr qreal kTurnPeriodMs = 1400.0;
constexpr qreal kSweepCenterDeg = 170.0;
constexpr qreal kSweepAmplitudeDeg = 80.0;
// 惯性感：整环不是匀速转，而是一个周期内"快-慢"起伏（角速度约 0.68x..1.32x）。
// 弧最长的那一下就压在最快的相位上，读起来是"甩出去 + 收回来"，而不是匀速画圈。
constexpr qreal kInertiaDeg = 18.0;

// QSGVertexColorMaterial 按**预乘 alpha** 混合（ONE, ONE_MINUS_SRC_ALPHA），
// 顶点色必须先乘 alpha；直接传直通色会让羽化边缘"发亮"（蓝边泛青、看着像噪点）。
inline QSGGeometry::ColoredPoint2D makeVertex(const QPointF &p, const QColor &c, int alpha)
{
    const int a = qBound(0, alpha, 255);
    QSGGeometry::ColoredPoint2D v;
    v.set(float(p.x()), float(p.y()),
          uchar(c.red() * a / 255),
          uchar(c.green() * a / 255),
          uchar(c.blue() * a / 255),
          uchar(a));
    return v;
}

/// 当前帧的弧起点与弧长（角度制，0° 在 12 点方向，顺时针为正）。
void spinnerState(qint64 ms, qreal *startDeg, qreal *sweepDeg)
{
    const qreal t = qreal(ms);
    const qreal phase = 2.0 * kPi * t / kTurnPeriodMs;

    // 匀速项 + 正弦调速：d(turn)/dt = 257 ∓ 81 °/s，快慢交替（惯性）。
    const qreal turnDeg = t / kTurnPeriodMs * 360.0 + kInertiaDeg * std::sin(phase);
    // 呼吸相位前置 90°：弧最长时正好转得最快（"甩"的那一下）。
    const qreal sweep = kSweepCenterDeg + kSweepAmplitudeDeg * std::sin(phase + kPi * 0.5);

    *sweepDeg = sweep;
    *startDeg = turnDeg - sweep * 0.5;
}

/// 画一段圆弧（带 alpha 羽化与可选圆头端帽），写进 geo 的顶点/索引缓冲。
/// 顶点/索引数量只由 segments 决定（每次调用完全一样），所以 allocate 是空操作，
/// 只有数据在变——不会每帧重新分配显存。
void buildArc(QSGGeometry *geo, const QPointF &center, qreal radius, qreal halfWidth,
              qreal startDeg, qreal sweepDeg, const QColor &color,
              int segments, bool closed, bool roundCaps)
{
    const int columns = segments + 1;
    const int capCount = (roundCaps && !closed) ? 2 : 0;
    const int capVertsPerCap = 1 + 2 * (kCapSegments + 1);
    const int vertexCount = columns * 4 + capCount * capVertsPerCap;
    const int indexCount = segments * 18 + capCount * kCapSegments * 9;

    geo->allocate(vertexCount, indexCount);
    QSGGeometry::ColoredPoint2D *v = geo->vertexDataAsColoredPoint2D();
    quint16 *idx = geo->indexDataAsUShort();
    const int baseAlpha = color.alpha();

    // 每个采样点四个顶点：内羽化(alpha 0) / 内沿(全 alpha) / 外沿(全 alpha) / 外羽化(alpha 0)
    const qreal radii[4] = { radius - halfWidth - kFeather, radius - halfWidth,
                             radius + halfWidth, radius + halfWidth + kFeather };
    const int alphas[4] = { 0, baseAlpha, baseAlpha, 0 };

    for (int i = 0; i < columns; ++i) {
        const qreal a = (startDeg + sweepDeg * qreal(i) / qreal(segments)) * kPi / 180.0;
        const qreal dx = std::sin(a);
        const qreal dy = -std::cos(a);
        for (int k = 0; k < 4; ++k) {
            const QPointF p(center.x() + dx * radii[k], center.y() + dy * radii[k]);
            v[i * 4 + k] = makeVertex(p, color, alphas[k]);
        }
    }

    int n = 0;
    for (int i = 0; i < segments; ++i) {
        const quint16 a0 = quint16(i * 4 + 0), b0 = quint16(i * 4 + 1);
        const quint16 c0 = quint16(i * 4 + 2), d0 = quint16(i * 4 + 3);
        const quint16 a1 = quint16(i * 4 + 4), b1 = quint16(i * 4 + 5);
        const quint16 c1 = quint16(i * 4 + 6), d1 = quint16(i * 4 + 7);
        idx[n++] = a0; idx[n++] = b0; idx[n++] = b1;   // 内羽化
        idx[n++] = a0; idx[n++] = b1; idx[n++] = a1;
        idx[n++] = b0; idx[n++] = c0; idx[n++] = c1;   // 主体
        idx[n++] = b0; idx[n++] = c1; idx[n++] = b1;
        idx[n++] = c0; idx[n++] = d0; idx[n++] = d1;   // 外羽化
        idx[n++] = c0; idx[n++] = d1; idx[n++] = c1;
    }

    if (capCount > 0) {
        int vertexBase = columns * 4;
        for (int e = 0; e < 2; ++e) {
            const qreal a = (startDeg + (e == 0 ? 0.0 : sweepDeg)) * kPi / 180.0;
            const QPointF p(center.x() + std::sin(a) * radius, center.y() - std::cos(a) * radius);
            v[vertexBase] = makeVertex(p, color, baseAlpha);   // 圆心（实心）
            for (int k = 0; k <= kCapSegments; ++k) {
                const qreal phi = 2.0 * kPi * qreal(k) / qreal(kCapSegments);
                const qreal ux = std::cos(phi), uy = std::sin(phi);
                v[vertexBase + 1 + k * 2] =
                    makeVertex(p + QPointF(ux * halfWidth, uy * halfWidth), color, baseAlpha);
                v[vertexBase + 1 + k * 2 + 1] =
                    makeVertex(p + QPointF(ux * (halfWidth + kFeather), uy * (halfWidth + kFeather)),
                               color, 0);
            }
            for (int k = 0; k < kCapSegments; ++k) {
                const quint16 centerIdx = quint16(vertexBase);
                const quint16 in0 = quint16(vertexBase + 1 + k * 2);
                const quint16 out0 = quint16(vertexBase + 1 + k * 2 + 1);
                const quint16 in1 = quint16(vertexBase + 1 + (k + 1) * 2);
                const quint16 out1 = quint16(vertexBase + 1 + (k + 1) * 2 + 1);
                idx[n++] = centerIdx; idx[n++] = in0; idx[n++] = in1;   // 实心圆
                idx[n++] = in0; idx[n++] = out0; idx[n++] = out1;       // 边缘羽化
                idx[n++] = in0; idx[n++] = out1; idx[n++] = in1;
            }
            vertexBase += capVertsPerCap;
        }
    }
}

/// 场景图节点：一条底环 + 一条前景弧，都是逐顶点着色的三角面片。
class DlSpinnerNode : public QSGNode
{
public:
    DlSpinnerNode()
        : m_trackGeometry(new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0, 0))
        , m_arcGeometry(new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0, 0))
    {
        // 两条几何节点必须挂到根节点下，否则绘制列表里什么都不存在
        m_track = createChild(m_trackGeometry);
        appendChildNode(m_track);
        m_arc = createChild(m_arcGeometry);
        appendChildNode(m_arc);
    }

    QSGGeometry *trackGeometry() const { return m_trackGeometry; }
    QSGGeometry *arcGeometry() const { return m_arcGeometry; }

    void markDirty()
    {
        m_track->markDirty(QSGNode::DirtyGeometry);
        m_arc->markDirty(QSGNode::DirtyGeometry);
    }

private:
    static QSGGeometryNode *createChild(QSGGeometry *geometry)
    {
        geometry->setDrawingMode(QSGGeometry::DrawTriangles);
        geometry->setVertexDataPattern(QSGGeometry::DynamicPattern);
        geometry->setIndexDataPattern(QSGGeometry::DynamicPattern);

        auto *material = new QSGVertexColorMaterial;
        material->setFlag(QSGMaterial::Blending);

        auto *node = new QSGGeometryNode;
        node->setGeometry(geometry);
        node->setMaterial(material);
        node->setFlag(QSGGeometryNode::OwnsGeometry);
        node->setFlag(QSGGeometryNode::OwnsMaterial);
        return node;
    }

    QSGGeometryNode *m_track = nullptr;
    QSGGeometryNode *m_arc = nullptr;
    QSGGeometry *m_trackGeometry = nullptr;
    QSGGeometry *m_arcGeometry = nullptr;
};

} // namespace

DlSpinnerItem::DlSpinnerItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(QQuickItem::ItemHasContents, true);
    setAntialiasing(true);
}

DlSpinnerItem::~DlSpinnerItem()
{
    m_timer.stop();
}

void DlSpinnerItem::setRunning(bool running)
{
    if (m_running == running)
        return;
    m_running = running;
    if (m_running)
        startAnimation();
    else
        stopAnimation();
    emit runningChanged();
}

void DlSpinnerItem::startAnimation()
{
    if (!m_running)
        return;
    m_elapsedMs = 0;
    m_clock.restart();
    m_timer.start(16, this);   // ~60fps；只推进时间，绘制交给 update()
    update();
}

void DlSpinnerItem::stopAnimation()
{
    m_timer.stop();
    update();                  // 停在当前相位，重绘一次
}

void DlSpinnerItem::setColor(const QColor &color)
{
    if (m_color == color)
        return;
    m_color = color;
    update();
    emit colorChanged();
}

void DlSpinnerItem::setTrackColor(const QColor &color)
{
    if (m_trackColor == color)
        return;
    m_trackColor = color;
    update();
    emit trackColorChanged();
}

void DlSpinnerItem::setLineWidth(qreal width)
{
    if (qFuzzyCompare(m_lineWidth, width))
        return;
    m_lineWidth = width;
    update();
    emit lineWidthChanged();
}

/// 环半径：16px 时正好 6.2（设计稿），放大 / 缩小时等比跟随。
qreal DlSpinnerItem::ringRadius() const
{
    const qreal side = qMin(width(), height());
    return side * (6.2 / 16.0);
}

void DlSpinnerItem::timerEvent(QTimerEvent *event)
{
    if (event->timerId() != m_timer.timerId()) {
        QQuickItem::timerEvent(event);
        return;
    }
    m_elapsedMs = m_clock.elapsed();
    update();
}

void DlSpinnerItem::itemChange(ItemChange change, const ItemChangeData &value)
{
    if (change == QQuickItem::ItemVisibleHasChanged) {
        // 不可见时别白烧 60fps 的 CPU；重新可见再从 0 相位开始
        if (!value.boolValue)
            stopAnimation();
        else if (m_running)
            startAnimation();
    }
    QQuickItem::itemChange(change, value);
}

QSGNode *DlSpinnerItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    auto *node = static_cast<DlSpinnerNode *>(oldNode);
    if (!node)
        node = new DlSpinnerNode;

    const qreal radius = ringRadius();
    if (radius > 0.5) {
        const QPointF center(width() * 0.5, height() * 0.5);
        const qreal halfWidth = qMax<qreal>(0.35, m_lineWidth) * 0.5;

        // 底环：整圈 trackColor，无端帽
        buildArc(node->trackGeometry(), center, radius, halfWidth, 0.0, 360.0,
                 m_trackColor, kTrackSegments, true, false);

        // 前景弧：旋转 + 弧长伸缩 + 沿圆周行进
        qreal startDeg = 0.0;
        qreal sweepDeg = 0.0;
        spinnerState(m_elapsedMs, &startDeg, &sweepDeg);
        buildArc(node->arcGeometry(), center, radius, halfWidth, startDeg, sweepDeg,
                 m_color, kArcSegments, false, true);

        node->markDirty();
    }
    return node;
}

} // namespace ShadowLauncher
