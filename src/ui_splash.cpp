// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "ui_splash.h"

#include <QGuiApplication>
#include <QPainter>
#include <QScreen>
#include <QTimer>
#include <QFont>
#include <QFontMetricsF>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QThread>
#include <cmath>
#include <vector>

namespace {

constexpr int   kWinW     = 1100;
constexpr int   kWinH     = 720;
constexpr int   kWordPx   = 44;
constexpr qreal kSpacing  = 2.2;
constexpr int   kHaloR    = 8;      // 光晕半径（逻辑像素），两遍盒模糊≈高斯
constexpr int   kFadeMs   = 130;

QFont wordFont()
{
    // 必须和 SideBar.qml 的 SHADOW 用同一套字体参数（family/weight/letterSpacing 2.2），
    // 否则交接那一刻字宽差 1~2px，看起来就是"抖了一下"。
    QFont f(QStringLiteral("Microsoft YaHei UI"));
    f.setPixelSize(kWordPx);
    f.setWeight(QFont::Bold);
    f.setLetterSpacing(QFont::AbsoluteSpacing, kSpacing);
    f.setHintingPreference(QFont::PreferNoHinting);
    return f;
}

// 只模糊 alpha：字是纯白，RGB 不用动。
void boxBlurAlpha(QImage &img, int r)
{
    const int w = img.width();
    const int h = img.height();
    std::vector<int> src(size_t(w) * h), dst(size_t(w) * h);
    for (int y = 0; y < h; ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < w; ++x)
            src[size_t(y) * w + x] = qAlpha(line[x]);
    }
    const int span = 2 * r + 1;
    for (int pass = 0; pass < 2; ++pass) {
        for (int y = 0; y < h; ++y) {
            int acc = 0;
            for (int x = -r; x <= r; ++x) acc += src[size_t(y) * w + qBound(0, x, w - 1)];
            for (int x = 0; x < w; ++x) {
                dst[size_t(y) * w + x] = acc / span;
                acc += src[size_t(y) * w + qBound(0, x + r + 1, w - 1)]
                     - src[size_t(y) * w + qBound(0, x - r, w - 1)];
            }
        }
        std::swap(src, dst);
        for (int x = 0; x < w; ++x) {
            int acc = 0;
            for (int y = -r; y <= r; ++y) acc += src[size_t(qBound(0, y, h - 1)) * w + x];
            for (int y = 0; y < h; ++y) {
                dst[size_t(y) * w + x] = acc / span;
                acc += src[size_t(qBound(0, y + r + 1, h - 1)) * w + x]
                     - src[size_t(qBound(0, y - r, h - 1)) * w + x];
            }
        }
        std::swap(src, dst);
    }
    for (int y = 0; y < h; ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(y));
        for (int x = 0; x < w; ++x)
            line[x] = qRgba(255, 255, 255, src[size_t(y) * w + x]);
    }
}

} // namespace

SplashWindow::SplashWindow(QWidget *parent)
    : QWidget(parent)
{
    // Tool + 无边框 + 置顶：不进任务栏、不抢焦点、永远盖在主窗口上面。
    setWindowFlags(Qt::Window | Qt::FramelessWindowHint
                   | Qt::WindowStaysOnTopHint | Qt::Tool);
    setAttribute(Qt::WA_ShowWithoutActivating, true);
    setAttribute(Qt::WA_DeleteOnClose, true);
    resize(kWinW, kWinH);
    if (QScreen *scr = QGuiApplication::primaryScreen()) {
        const QRect g = scr->availableGeometry();
        move(g.center() - QPoint(kWinW / 2, kWinH / 2));
    }

    const QString text = QStringLiteral("SHADOW");
    const QFont f = wordFont();
    const QFontMetricsF fm(f);
    m_wordW = int(std::ceil(fm.horizontalAdvance(text)));
    m_wordH = int(std::ceil(fm.height()));

    m_haloPad = kHaloR * 2 + 4;
    QImage img(m_wordW + m_haloPad * 2, m_wordH + m_haloPad * 2, QImage::Format_ARGB32);
    img.fill(Qt::transparent);
    {
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing);
        p.setRenderHint(QPainter::TextAntialiasing);
        p.setFont(f);
        p.setPen(Qt::white);
        p.drawText(QPointF(m_haloPad, m_haloPad + fm.ascent()), text);
    }
    boxBlurAlpha(img, kHaloR);
    m_halo = img;
}

void SplashWindow::fadeInAndShow(int ms)
{
    // 之前的写法是 show() 直接满不透明 —— 屏幕上是桌面，然后「啪」一下变成
    // #08090d + SHADOW，这就是「硬出现」。窗口淡入只能自己泵事件循环做，
    // 因为紧接着的 QML 加载会把主线程堵死，任何 QTimer 都不会走。
    setWindowOpacity(0.0);
    show();
    raise();
    QCoreApplication::processEvents(QEventLoop::AllEvents, 20);

    QElapsedTimer clock;
    clock.start();
    for (;;) {
        const qreal k = qBound(0.0, clock.elapsed() / qreal(ms), 1.0);
        // smoothstep（3k²-2k³）：两端缓、中间匀。用 easeOut 会让头 40ms 就冲到 78%，
        // 观感还是「啪」一下 —— 实测采样只有 2 个中间帧，等于没柔化。
        const qreal e = k * k * (3.0 - 2.0 * k);
        setWindowOpacity(0.02 + 0.98 * e);
        QCoreApplication::processEvents(QEventLoop::AllEvents, 8);
        if (k >= 1.0) break;
        QThread::msleep(12);
    }
    setWindowOpacity(1.0);
    QCoreApplication::processEvents(QEventLoop::AllEvents, 8);
}

void SplashWindow::beginFinish()
{
    if (m_fadeMs >= 0) return;
    m_fadeClock.start();
    m_fadeMs = 0;
    auto *t = new QTimer(this);
    t->setInterval(16);
    QObject::connect(t, &QTimer::timeout, this, [this, t]() {
        const qreal k = qBound(0.0, m_fadeClock.elapsed() / qreal(kFadeMs), 1.0);
        setWindowOpacity(1.0 - k);
        if (k >= 1.0) {
            t->stop();
            close();
        }
    });
    t->start();
}

void SplashWindow::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.fillRect(rect(), QColor(8, 9, 13));
    if (m_halo.isNull()) return;

    const QFontMetricsF fm(wordFont());
    const qreal x = (width() - m_wordW) / 2.0;
    const qreal y = (height() - m_wordH) / 2.0;

    p.setRenderHint(QPainter::Antialiasing);
    p.drawImage(QPointF(x - m_haloPad, y - m_haloPad), m_halo);

    p.setRenderHint(QPainter::TextAntialiasing);
    p.setFont(wordFont());
    p.setPen(QColor(232, 235, 242));   // Theme.fg
    p.drawText(QPointF(x, y + fm.ascent()), QStringLiteral("SHADOW"));
}
