// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
// Shadow Launcher — 下载步骤不确定环（C++ 场景图 item）
//
// 结构照 Qt 自己的 Material BusyIndicator 写：
//   src/quickcontrols/material/impl/qquickmaterialbusyindicator.cpp
//     · QQuickItem 子类 + setFlag(ItemHasContents)
//     · 私有 QSGNode 派生节点，几何在 updatePaintNode() 里重建
//     · 时间由 item 自己的定时器推进，只调 update()，QML 里零逐帧绑定
//
// 为什么不用 QML 动画：下载卡片每 200ms 轮询 cardData() 刷新一次数据，
// delegate 里的 Image/Sprite/NumberAnimation 会被重置，表现为"转一下回跳"。
// 相位存在 C++ 对象里，数据怎么刷新都打断不了。
#pragma once

#include <QBasicTimer>
#include <QColor>
#include <QElapsedTimer>
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class QSGNode;
class QTimerEvent;

namespace ShadowLauncher {

class DlSpinnerItem : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(DlSpinner)
    Q_PROPERTY(bool running READ isRunning WRITE setRunning NOTIFY runningChanged FINAL)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged FINAL)
    Q_PROPERTY(QColor trackColor READ trackColor WRITE setTrackColor NOTIFY trackColorChanged FINAL)
    Q_PROPERTY(qreal lineWidth READ lineWidth WRITE setLineWidth NOTIFY lineWidthChanged FINAL)

public:
    explicit DlSpinnerItem(QQuickItem *parent = nullptr);
    ~DlSpinnerItem() override;

    bool isRunning() const { return m_running; }
    void setRunning(bool running);

    QColor color() const { return m_color; }
    void setColor(const QColor &color);

    QColor trackColor() const { return m_trackColor; }
    void setTrackColor(const QColor &color);

    qreal lineWidth() const { return m_lineWidth; }
    void setLineWidth(qreal width);

signals:
    void runningChanged();
    void colorChanged();
    void trackColorChanged();
    void lineWidthChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *updateInfo) override;
    void timerEvent(QTimerEvent *event) override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private:
    void startAnimation();
    void stopAnimation();
    qreal ringRadius() const;

    bool m_running = false;
    QColor m_color{0x3b, 0x82, 0xf6};       // Theme.accent
    QColor m_trackColor{0x23, 0x2a, 0x34};  // 底环
    qreal m_lineWidth = 1.8;

    QBasicTimer m_timer;
    QElapsedTimer m_clock;
    qint64 m_elapsedMs = 0;
};

} // namespace ShadowLauncher
