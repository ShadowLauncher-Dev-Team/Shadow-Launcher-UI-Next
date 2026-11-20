// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#pragma once

#include <QWidget>
#include <QImage>
#include <QElapsedTimer>

// 启动封面窗（启动动画方案 A 的"影子"那一半）。
//
// 为什么是静态的：QML 加载会同步堵住主线程 1.4~1.8s，这期间任何定时器/动画都不会走，
// 所以这块只能是**一张静止的画面**，动画全部交给加载完成后的 QML（StartupIntro.qml）。
// 它存在的唯一理由：把"进程已启动、窗口还没出来"这段黑屏换成一张像样的画面。
//
// 画面 = #08090d 底 + 居中 44px 的 SHADOW（清晰字 + 一圈模糊光晕）。
// 这个画面必须和 StartupIntro.qml 的第 0 帧**逐像素接近**，交接才看不出来：
// 所以字体、字号、字距、居中方式、光晕半径都是两边对着调的。
class SplashWindow : public QWidget
{
    Q_OBJECT
public:
    explicit SplashWindow(QWidget *parent = nullptr);

    // 主窗口首帧已上屏：淡出并自己 deleteLater
    void beginFinish();

private:
    void paintEvent(QPaintEvent *e) override;

    QImage m_halo;          // 模糊光晕（含外扩边距）
    int m_haloPad = 0;
    int m_wordW = 0;        // 清晰字宽（布局用）
    int m_wordH = 0;
    QElapsedTimer m_fadeClock;
    int m_fadeMs = -1;
};
