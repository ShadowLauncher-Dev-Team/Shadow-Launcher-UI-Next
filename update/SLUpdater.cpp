// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 Shadow
//
// SLUpdater — standalone helper process for Shadow Launcher self-update.
//
// Usage (called by ShadowLauncher after downloading a new version):
//   增量: SLUpdater.exe <oldPid> <oldExePath> <newFilePath>
//   全量: SLUpdater.exe <oldPid> <oldExePath> <newFilePath> <fullExtractDir>
//         全量时 newFilePath = <fullExtractDir>/ShadowLauncher.exe
//
// 流程（2026-08-15 方案A重构，替代原 PreInit 内 applyFullUpdate）：
//   1. 显示小型进度窗口（纯 Win32，无 Qt）
//   2. 等旧启动器进程退出（文件解锁）
//   3. 全量：复制 extracted/* → appDir（覆盖+新增），再删除多余旧文件
//   4. 替换 ShadowLauncher.exe（.old 备份 + 回滚）
//   5. 清理 _update，重启新版本
// 全量复制失败时不删 state.json/zip → 下次启动自动重试（自愈）。

#ifndef UNICODE
#  define UNICODE       // 确保 IDC_* / TCHAR 宏展开为宽字符版本（须在 windows.h 之前）
#  define _UNICODE
#endif
#include <windows.h>
#include <shellapi.h>
#include <commctrl.h>
#include <tlhelp32.h>   // 2026-08-15：枚举/结束 helper 进程（easytier/wv2login 可能锁文件）
#include <gdiplus.h>    // 2026-11-20：卡片式进度窗口（自绘圆角/阴影/进度条）
#include <string>
#include <cstdio>
#include <cstdarg>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "gdiplus.lib")

static HWND g_hwnd = nullptr;
static const wchar_t* kWinClass = L"ShadowUpdateWindow";

// ══ 2026-11-20 改版：无边框圆角卡片（方案 A）═════════════════════════
// 旧实现是 WS_OVERLAPPED 带系统标题栏的 420x150 窗口 + 两个 STATIC + PROGRESS_CLASS，
// 和启动器自己的卡片风格完全是两套视觉。现在改成一张悬浮卡：
//   · UpdateLayeredWindow + 32bpp 位图 → 圆角/阴影/3px 进度条全部抗锯齿，
//     而且不依赖 DWM 圆角（Win10 上也是圆的）
//   · GDI+ 自绘：启动器图标 + 标题 + 一句说明 + 进度条 + 「阶段 / 百分比」小字
//   · 阶段文字没丢，只是缩成 11px 灰字放在进度条下方 —— 否则 92%~100% 那段看不出在干什么
static const int kCardW  = 360;   // 逻辑像素（96dpi 基准），实际按屏幕 DPI 缩放
static const int kCardH  = 96;
static const int kShadow = 14;    // 卡片四周留给阴影的透明边距

static ULONG_PTR g_gdiplus = 0;
static HDC     g_memDC = nullptr;
static HBITMAP g_dib = nullptr;
static HGDIOBJ g_oldBmp = nullptr;
static void*   g_dibBits = nullptr;
static int     g_sw = 0, g_sh = 0, g_stride = 0;
static float   g_scale = 1.0f;
static HICON   g_icon = nullptr;
static int     g_progress = -1;                       // -1 = 跑马灯；0..100 = 百分比
static std::wstring g_phase = L"正在准备更新…";
static std::wstring g_title = L"正在安装更新";
static std::wstring g_sub   = L"更新完成后将自动重启应用";
static DWORD   g_lastRender = 0;
static bool    g_timerOn = false;

// ── 消息泵：长任务期间保持窗口响应 ──
static void pumpMessages()
{
    MSG msg;
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
}

static void logMsg(const wchar_t* fmt, ...);       // 定义在文件后段

// ── GDI+ 绘图小工具 ──
static Gdiplus::Color rgba(BYTE r, BYTE g, BYTE b, BYTE a = 255)
{
    return Gdiplus::Color(a, r, g, b);
}

static Gdiplus::FontFamily& uiFamily()
{
    static Gdiplus::FontFamily yahei(L"Microsoft YaHei UI");
    static Gdiplus::FontFamily segoe(L"Segoe UI");
    if (yahei.GetLastStatus() == Gdiplus::Ok) return yahei;
    return segoe;
}

static void roundRectPath(Gdiplus::GraphicsPath& p, const Gdiplus::RectF& r, float rad)
{
    const float d = rad * 2.0f;
    if (d <= 0.5f) { p.AddRectangle(r); return; }
    p.AddArc(r.X, r.Y, d, d, 180.0f, 90.0f);
    p.AddArc(r.GetRight() - d, r.Y, d, d, 270.0f, 90.0f);
    p.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0.0f, 90.0f);
    p.AddArc(r.X, r.GetBottom() - d, d, d, 90.0f, 90.0f);
    p.CloseFigure();
}

// ── 32bpp 位图表面（分层窗口的绘制目标）──
static bool ensureSurface(int w, int h)
{
    if (!g_memDC) g_memDC = CreateCompatibleDC(nullptr);
    if (!g_memDC) return false;
    if (g_dib && g_sw == w && g_sh == h) return true;
    if (g_dib) {
        if (g_oldBmp) { SelectObject(g_memDC, g_oldBmp); g_oldBmp = nullptr; }
        DeleteObject(g_dib);
        g_dib = nullptr;
        g_dibBits = nullptr;
    }
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;          // 负数 = 自上而下，行序与屏幕一致
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    g_dib = CreateDIBSection(g_memDC, &bi, DIB_RGB_COLORS, &g_dibBits, nullptr, 0);
    if (!g_dib || !g_dibBits) return false;
    g_oldBmp = SelectObject(g_memDC, g_dib);
    g_sw = w; g_sh = h; g_stride = w * 4;
    return true;
}

static Gdiplus::Bitmap* iconToBitmap(HICON ic)
{
    if (!ic) return nullptr;
    ICONINFO ii = {};
    if (!GetIconInfo(ic, &ii)) return nullptr;
    Gdiplus::Bitmap* b = nullptr;
    if (ii.hbmColor) b = Gdiplus::Bitmap::FromHBITMAP(ii.hbmColor, nullptr);
    if (ii.hbmColor) DeleteObject(ii.hbmColor);
    if (ii.hbmMask) DeleteObject(ii.hbmMask);
    if (b && b->GetLastStatus() != Gdiplus::Ok) { delete b; return nullptr; }
    return b;
}

// ── 圆角/阴影用解析式 alpha 遮罩生成 ──
// 之前用"一圈圈同心圆角矩形叠阴影 + GDI+ 抗锯齿路径"，结果一是阴影有环带，
// 二是文字走 GDI+ 在 32bpp+alpha 表面上会退化成灰度 AA，深底浅字小字号直接笔画断裂
// （影的原话："分辨率极低，文字、图标甚至有锯齿"）。
// 现在：卡面/进度条用 GDI+ 画、文字用 GDI ClearType 画、圆角与阴影由下面这个
// 逐像素遮罩生成 —— 边缘是真正 1px 抗锯齿，阴影是平滑衰减，没有环带。
static inline float clamp01(float v) { return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v); }

// 圆角矩形的有符号距离（<0 在内部）
static float sdRoundRect(float px, float py, float x, float y, float w, float h, float r)
{
    const float cx = x + w * 0.5f, cy = y + h * 0.5f;
    const float hx = w * 0.5f - r, hy = h * 0.5f - r;
    const float dx = fabsf(px - cx) - hx;
    const float dy = fabsf(py - cy) - hy;
    const float ox = dx > 0.0f ? dx : 0.0f;
    const float oy = dy > 0.0f ? dy : 0.0f;
    const float outside = sqrtf(ox * ox + oy * oy);
    const float inside = (dx > dy ? dx : dy);
    return outside + (inside > 0.0f ? 0.0f : inside) - r;
}

static long g_opaquePixels = 0;
static void applyCardMask(int w, int h, float x, float y, float cw, float ch, float rad,
                          float margin, float shadowOffY)
{
    g_opaquePixels = 0;
    BYTE* px = static_cast<BYTE*>(g_dibBits);
    for (int yy = 0; yy < h; ++yy) {
        const float fy = static_cast<float>(yy) + 0.5f;
        BYTE* row = px + static_cast<size_t>(yy) * static_cast<size_t>(g_stride);
        for (int xx = 0; xx < w; ++xx) {
            const float fx = static_cast<float>(xx) + 0.5f;
            const float d = sdRoundRect(fx, fy, x, y, cw, ch, rad);
            const float cover = clamp01(0.5f - d);          // 卡片覆盖率（1px 过渡）
            float a = cover;
            if (cover < 1.0f) {
                const float ds = sdRoundRect(fx, fy - shadowOffY, x, y, cw, ch, rad);
                float sa = 0.0f;
                if (ds > 0.0f && ds < margin) {
                    const float t = 1.0f - ds / margin;
                    sa = 0.58f * t * t * t;                 // 三次衰减，越远越淡
                }
                a = cover + sa * (1.0f - cover);
                if (a > 1.0f) a = 1.0f;
            }
            BYTE* q = row + static_cast<size_t>(xx) * 4;
            const BYTE av = static_cast<BYTE>(a * 255.0f + 0.5f);
            if (a >= 0.999f) ++g_opaquePixels;
            q[3] = av;
            if (av == 0) {
                q[0] = q[1] = q[2] = 0;
            } else if (av < 255) {                          // 预乘 alpha（分层窗口要求）
                q[0] = static_cast<BYTE>(q[0] * av / 255);
                q[1] = static_cast<BYTE>(q[1] * av / 255);
                q[2] = static_cast<BYTE>(q[2] * av / 255);
            }
        }
    }
}

// GDI + ClearType 写字（不透明底上才清楚）
static void drawTextGdi(HDC dc, const std::wstring& text, int x, int y, int w, int h,
                        int px, int weight, COLORREF color, UINT fmt)
{
    HFONT f = CreateFontW(-px, 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                          OUT_TT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                          DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
    HGDIOBJ old = SelectObject(dc, f);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, color);
    RECT r = { x, y, x + w, y + h };
    DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &r,
              fmt | DT_SINGLELINE | DT_NOPREFIX | DT_VCENTER);
    SelectObject(dc, old);
    DeleteObject(f);
}

// 取 PNG 编码器 CLSID
static int pngEncoderClsid(CLSID* clsid)
{
    UINT num = 0, size = 0;
    Gdiplus::GetImageEncodersSize(&num, &size);
    if (size == 0) return -1;
    Gdiplus::ImageCodecInfo* info = (Gdiplus::ImageCodecInfo*)malloc(size);
    if (!info) return -1;
    Gdiplus::GetImageEncoders(num, size, info);
    int found = -1;
    for (UINT i = 0; i < num; ++i) {
        if (wcscmp(info[i].MimeType, L"image/png") == 0) { *clsid = info[i].Clsid; found = 0; break; }
    }
    free(info);
    return found;
}

// 把当前位图导出成 PNG（反预乘回直通 alpha）——开发模式用来核对真实像素
static void dumpCardToPng(const std::wstring& path)
{
    if (!g_dibBits || g_sw <= 0 || g_sh <= 0) return;
    Gdiplus::Bitmap out(g_sw, g_sh, PixelFormat32bppARGB);
    Gdiplus::Rect r(0, 0, g_sw, g_sh);
    Gdiplus::BitmapData bd;
    if (out.LockBits(&r, Gdiplus::ImageLockModeWrite, PixelFormat32bppARGB, &bd) != Gdiplus::Ok)
        return;
    BYTE* dst = static_cast<BYTE*>(bd.Scan0);
    const BYTE* src = static_cast<const BYTE*>(g_dibBits);
    for (int y = 0; y < g_sh; ++y) {
        for (int x = 0; x < g_sw; ++x) {
            const BYTE* sp = src + static_cast<size_t>(y) * g_stride + x * 4;
            BYTE* dp = dst + static_cast<size_t>(y) * bd.Stride + x * 4;
            const BYTE a = sp[3];
            dp[3] = a;
            if (a == 0) { dp[0] = dp[1] = dp[2] = 0; continue; }
            for (int k = 0; k < 3; ++k) {
                const int v = sp[k] * 255 / a;
                dp[k] = static_cast<BYTE>(v > 255 ? 255 : v);
            }
        }
    }
    out.UnlockBits(&bd);
    CLSID png;
    if (pngEncoderClsid(&png) >= 0)
        out.Save(path.c_str(), &png, nullptr);
}

// ── 整卡重绘（只在阶段/百分比变化时调用；用节流避免每复制一个文件就重绘）──
static void renderCard()
{
    if (!g_hwnd) return;
    const int winW = g_sw, winH = g_sh;
    if (winW <= 0 || winH <= 0) return;
    if (!ensureSurface(winW, winH)) return;

    const float s = g_scale;
    const float m = static_cast<float>(kShadow) * s;          // 阴影边距
    const float cw = static_cast<float>(winW) - m * 2.0f;      // 卡片宽高
    const float chh = static_cast<float>(winH) - m * 2.0f;
    const float rad = 14.0f * s;
    const float pad = 16.0f * s;
    const float isz = 30.0f * s;
    const float ix = m + pad, iy = m + pad;
    const float tx = ix + isz + 13.0f * s;
    const float textW = (m + cw - pad) - tx;
    const float trackW = cw - pad * 2.0f;
    const float th = (3.0f * s < 2.0f) ? 2.0f : 3.0f * s;
    const float ty = iy + isz + 12.0f * s;
    const float my = ty + th + 8.0f * s;

    memset(g_dibBits, 0, static_cast<size_t>(g_stride) * static_cast<size_t>(winH));

    {
        Gdiplus::Graphics gfx(g_memDC);
        gfx.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        gfx.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
        gfx.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);

        // 卡面底色：多铺 1px 保证抗锯齿边缘不漏底（圆角由 alpha 遮罩裁）
        Gdiplus::SolidBrush bg(rgba(0x12, 0x15, 0x1C));
        gfx.FillRectangle(&bg, Gdiplus::RectF(m - 1.0f, m - 1.0f, cw + 2.0f, chh + 2.0f));

        // 1px 描边
        Gdiplus::GraphicsPath edge;
        roundRectPath(edge, Gdiplus::RectF(m + 0.5f, m + 0.5f, cw - 1.0f, chh - 1.0f), rad);
        Gdiplus::Pen pen(rgba(0x26, 0x2B, 0x35), 1.0f);
        gfx.DrawPath(&pen, &edge);

        // 图标底框（与 QML 版一致：8px 圆角 + 1px 描边）
        {
            Gdiplus::GraphicsPath boxPath;
            roundRectPath(boxPath, Gdiplus::RectF(ix, iy, isz, isz), 8.0f * s);
            Gdiplus::SolidBrush boxBg(rgba(0x08, 0x09, 0x0D));
            gfx.FillPath(&boxBg, &boxPath);
            Gdiplus::Pen boxPen(rgba(0x26, 0x2B, 0x35), 1.0f);
            gfx.DrawPath(&boxPen, &boxPath);
        }

        // 启动器图标（圆角裁切）
        if (Gdiplus::Bitmap* ib = iconToBitmap(g_icon)) {
            Gdiplus::GraphicsPath clip;
            roundRectPath(clip, Gdiplus::RectF(ix, iy, isz, isz), 8.0f * s);
            gfx.SetClip(&clip);
            gfx.DrawImage(ib, Gdiplus::RectF(ix, iy, isz, isz));
            gfx.ResetClip();
            delete ib;
        }

        // 进度条（3px 圆头）
        Gdiplus::GraphicsPath trackPath;
        roundRectPath(trackPath, Gdiplus::RectF(ix, ty, trackW, th), th * 0.5f);
        Gdiplus::SolidBrush trackBr(rgba(0x26, 0x2B, 0x35));
        gfx.FillPath(&trackBr, &trackPath);

        gfx.SetClip(&trackPath);
        if (g_progress < 0) {
            const float segW = trackW * 0.35f;
            const float span = trackW + segW;
            const double ph = static_cast<double>(GetTickCount() % 1500) / 1500.0;
            const float x0 = static_cast<float>(ph * span) - segW;
            Gdiplus::GraphicsPath fp;
            roundRectPath(fp, Gdiplus::RectF(ix + x0, ty, segW, th), th * 0.5f);
            Gdiplus::LinearGradientBrush gb(Gdiplus::PointF(ix + x0, ty),
                                            Gdiplus::PointF(ix + x0 + segW, ty),
                                            rgba(0x25, 0x63, 0xEB), rgba(0x4B, 0x8C, 0xF7));
            gfx.FillPath(&gb, &fp);
        } else if (g_progress > 0) {
            const float fw = trackW * static_cast<float>(g_progress) / 100.0f;
            if (fw > th * 0.5f) {
                Gdiplus::GraphicsPath fp;
                roundRectPath(fp, Gdiplus::RectF(ix, ty, fw, th), th * 0.5f);
                Gdiplus::LinearGradientBrush gb(Gdiplus::PointF(ix, ty),
                                                Gdiplus::PointF(ix + trackW, ty),
                                                rgba(0x25, 0x63, 0xEB), rgba(0x4B, 0x8C, 0xF7));
                gfx.FillPath(&gb, &fp);
            }
        }
        gfx.ResetClip();
    }   // ← GDI+ 先析构，再用 GDI 写字，两套绘制不交错

    {
        const int titlePx = static_cast<int>(14.0f * s + 0.5f);
        const int subPx   = static_cast<int>(12.0f * s + 0.5f);
        const int metaPx  = static_cast<int>(11.0f * s + 0.5f);
        // 行位与 QML 版（ui/UpdateCardWindow.qml）逐像素对齐：标题 y=11、副行 y=32
        const int titleY  = static_cast<int>(iy - 5.0f * s);
        const int titleH  = static_cast<int>(20.0f * s);
        const int subY    = static_cast<int>(iy + 16.0f * s);
        const int subH    = static_cast<int>(17.0f * s);
        const int metaY   = static_cast<int>(my - 1.0f * s);
        const int metaH   = static_cast<int>(15.0f * s);

        drawTextGdi(g_memDC, g_title, static_cast<int>(tx), titleY, static_cast<int>(textW), titleH,
                    titlePx, FW_SEMIBOLD, RGB(0xE8, 0xEB, 0xF2), DT_LEFT);
        drawTextGdi(g_memDC, g_sub, static_cast<int>(tx), subY, static_cast<int>(textW), subH,
                    subPx, FW_NORMAL, RGB(0x98, 0xA1, 0xAE), DT_LEFT);
        drawTextGdi(g_memDC, g_phase, static_cast<int>(ix), metaY,
                    static_cast<int>(trackW - 52.0f * s), metaH,
                    metaPx, FW_NORMAL, RGB(0x5D, 0x66, 0x73), DT_LEFT | DT_END_ELLIPSIS);

        const std::wstring pct = (g_progress < 0) ? std::wstring(L"…")
                               : (g_progress >= 100 ? std::wstring(L"完成")
                                                    : (std::to_wstring(g_progress) + L"%"));
        drawTextGdi(g_memDC, pct, static_cast<int>(ix), metaY, static_cast<int>(trackW), metaH,
                    metaPx, FW_NORMAL, RGB(0x98, 0xA1, 0xAE), DT_RIGHT);
    }

    applyCardMask(winW, winH, m, m, cw, chh, rad, m - 1.0f, 2.0f * s);

    RECT wr = { 0, 0, 0, 0 };
    GetWindowRect(g_hwnd, &wr);
    POINT ptDst = { wr.left, wr.top };
    POINT ptSrc = { 0, 0 };
    SIZE  sz = { winW, winH };
    BLENDFUNCTION bf = { AC_SRC_OVER, 0, 255, AC_SRC_ALPHA };
    const BOOL ulwOk = UpdateLayeredWindow(g_hwnd, nullptr, &ptDst, &sz, g_memDC,
                                           &ptSrc, 0, &bf, ULW_ALPHA);
    if (!ulwOk)
        logMsg(L"[SLUpdater] UpdateLayeredWindow 失败 err=%lu", GetLastError());
}

// ── 阶段推进：percent < 0 = 跑马灯（不定进度）──
static void setPhase(const wchar_t* text, int percent)
{
    bool changed = false;
    if (g_phase != text) { g_phase = text; changed = true; }

    if (percent >= 100) {
        // 收尾：文案切到「正在启动新版本」（卡片上的最后 0.3 秒）
        if (g_title != L"正在启动新版本") { g_title = L"正在启动新版本"; changed = true; }
        if (g_sub != L"即将自动回到启动器") { g_sub = L"即将自动回到启动器"; changed = true; }
    }
    if (g_progress != percent) { g_progress = percent; changed = true; }

    // 跑马灯需要一个定时器推进；有真实百分比就不需要
    if (percent < 0) {
        if (!g_timerOn && g_hwnd) { SetTimer(g_hwnd, 1, 40, nullptr); g_timerOn = true; }
    } else {
        if (g_timerOn && g_hwnd) { KillTimer(g_hwnd, 1); g_timerOn = false; }
    }

    // 节流：复制阶段每个文件都会调一次，不能每次都整卡重绘（GDI+ 文字代价不小）
    const DWORD now = GetTickCount();
    if (changed && (percent < 0 || percent >= 100 || now - g_lastRender >= 50)) {
        renderCard();
        g_lastRender = now;
    }
    if (changed) logMsg(L"[SLUpdater] 阶段: %s (%d%%)", text, percent);
    pumpMessages();
}

static void showError(const wchar_t* msg, DWORD err = GetLastError())
{
    wchar_t buf[1024];
    swprintf_s(buf, L"%s (error: %lu)", msg, err);
    MessageBoxW(nullptr, buf, L"Shadow Launcher Update", MB_ICONERROR);
}

// ── 2026-08-15：详细日志（OutputDebugString + _update/sl_updater.log）──
// 之前报错不记录失败文件路径，无法定位 error 32 具体来源。日志写在
// _update/ 下（成功清理 _update 时一并删除；失败保留供诊断）。
static FILE* g_logFile = nullptr;

static void openLog(const std::wstring& appDir)
{
    const std::wstring p = appDir + L"\\_update\\sl_updater.log";
    _wfopen_s(&g_logFile, p.c_str(), L"w, ccs=UTF-8");
}

static void logMsg(const wchar_t* fmt, ...)
{
    wchar_t buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vswprintf_s(buf, fmt, ap);
    va_end(ap);
    OutputDebugStringW(buf);
    OutputDebugStringW(L"\n");
    if (g_logFile) {
        fwprintf(g_logFile, L"%s\n", buf);
        fflush(g_logFile);
    }
}

static LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CLOSE:
        return 0;   // 更新进行中禁止关闭（关闭=残缺安装）
    case WM_LBUTTONDOWN:
        // 无标题栏：整张卡都可以拖动
        ReleaseCapture();
        SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        return 0;
    case WM_TIMER:
        if (wp == 1) renderCard();     // 跑马灯动画
        return 0;
    case WM_DPICHANGED: {
        g_scale = static_cast<float>(HIWORD(wp)) / 96.0f;
        const int nw = static_cast<int>((kCardW + 2 * kShadow) * g_scale + 0.5f);
        const int nh = static_cast<int>((kCardH + 2 * kShadow) * g_scale + 0.5f);
        const RECT* r = reinterpret_cast<const RECT*>(lp);
        SetWindowPos(hwnd, nullptr, r->left, r->top, nw, nh,
                     SWP_NOZORDER | SWP_NOACTIVATE);
        renderCard();
        return 0;
    }
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

// ── 卡片式进度窗口 ──
static HICON loadLauncherIcon(const std::wstring& exePath)
{
    // 优先取大图（256，退回 64）：卡面按 30 逻辑像素画，125%/150% 缩放时需要更大源图才不糊
    typedef UINT (WINAPI* PFN_PEI)(LPCWSTR, int, int, int, HICON*, UINT*, UINT, UINT);
    PFN_PEI pei = reinterpret_cast<PFN_PEI>(
        GetProcAddress(GetModuleHandleW(L"user32.dll"), "PrivateExtractIconsW"));
    if (pei) {
        HICON ic = nullptr;
        if (pei(exePath.c_str(), 0, 256, 256, &ic, nullptr, 1, 0) && ic) return ic;
        if (pei(exePath.c_str(), 0, 64, 64, &ic, nullptr, 1, 0) && ic) return ic;
    }
    HICON big = nullptr;
    if (ExtractIconExW(exePath.c_str(), 0, &big, nullptr, 1) > 0) return big;
    return nullptr;
}

static void createProgressWindow(HINSTANCE hInst, const std::wstring& launcherExe)
{
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = wndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kWinClass;
    RegisterClassExW(&wc);

    g_icon = loadLauncherIcon(launcherExe);

    const int winW = static_cast<int>((kCardW + 2 * kShadow) * g_scale + 0.5f);
    const int winH = static_cast<int>((kCardH + 2 * kShadow) * g_scale + 0.5f);

    // 必须置顶（下面用 SetWindowPos(HWND_TOPMOST)）：实测普通 z 序下，卡片会被前台窗口
    //（浏览器/聊天）整块盖住，用户只看到"启动器关了、什么都没发生"。更新卡片就活几秒，置顶是对的行为。
    g_hwnd = CreateWindowExW(WS_EX_LAYERED, kWinClass, L"Shadow Launcher 更新中",
                             WS_POPUP, 0, 0, winW, winH, nullptr, nullptr, hInst, nullptr);
    if (!g_hwnd)
        logMsg(L"[SLUpdater] 创建卡片窗口失败 err=%lu", GetLastError());

    // 工作区居中（避开任务栏）
    RECT wa = { 0, 0, 1920, 1080 };
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0);
    SetWindowPos(g_hwnd, HWND_TOPMOST,
                 wa.left + (wa.right - wa.left - winW) / 2,
                 wa.top + (wa.bottom - wa.top - winH) / 2,
                 winW, winH, SWP_SHOWWINDOW | SWP_NOACTIVATE);

    ensureSurface(winW, winH);
    renderCard();
    UpdateWindow(g_hwnd);
    // 画完再抬一次 z 序（不激活）：只带 SWP_SHOWWINDOW 的置顶在某些情况下
    // 仍会被前台窗口压住，这里补一次显式 topmost 抬升。
    // 卡片是"正在替换启动器"的唯一可视反馈，必须真的在最前面：
    // 置顶（不抢焦点，避免打断开着游戏的用户）
    SetWindowPos(g_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW | SWP_NOACTIVATE);
    pumpMessages();
}

// ── 等待旧进程退出（分段等待，保持消息泵）──
static bool waitForProcess(DWORD pid, DWORD timeoutMs)
{
    HANDLE h = OpenProcess(SYNCHRONIZE, FALSE, pid);
    if (!h) return true;   // 进程已不在
    const DWORD start = GetTickCount();
    for (;;) {
        DWORD r = WaitForSingleObject(h, 100);
        pumpMessages();
        if (r == WAIT_OBJECT_0) break;
        if (r == WAIT_TIMEOUT && (GetTickCount() - start) >= timeoutMs) {
            CloseHandle(h);
            return false;
        }
    }
    CloseHandle(h);
    return true;
}

// ── 递归删除目录 ──
static void removeDirRecursive(const std::wstring& dir)
{
    std::wstring search = dir + L"\\*";
    WIN32_FIND_DATAW fd;
    HANDLE hFind = FindFirstFileW(search.c_str(), &fd);
    if (hFind != INVALID_HANDLE_VALUE) {
        do {
            if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0) continue;
            std::wstring p = dir + L"\\" + fd.cFileName;
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                removeDirRecursive(p);
            else
                DeleteFileW(p.c_str());
        } while (FindNextFileW(hFind, &fd));
        FindClose(hFind);
    }
    RemoveDirectoryW(dir.c_str());
}

// ── 统计目录内文件总数（复制进度用）──
static DWORD countFilesRecursive(const std::wstring& dir)
{
    DWORD n = 0;
    std::wstring search = dir + L"\\*";
    WIN32_FIND_DATAW fd;
    HANDLE hFind = FindFirstFileW(search.c_str(), &fd);
    if (hFind != INVALID_HANDLE_VALUE) {
        do {
            if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0) continue;
            std::wstring p = dir + L"\\" + fd.cFileName;
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                n += countFilesRecursive(p);
            else
                n++;
        } while (FindNextFileW(hFind, &fd));
        FindClose(hFind);
    }
    return n;
}

// ── 2026-08-15：结束可能锁定更新文件的 helper 进程 ──
// 旧启动器退出后，easytier-core（联机通道）/wv2login（嵌入式登录）可能作为
// 独立进程存活并锁定 bin/ 或 WebView2Loader.dll → 复制报 error 32
// (ERROR_SHARING_VIOLATION)。更新需要替换这些文件，先结束它们是安全的
// （新版本启动时会重新拉起）。
static void killHelperProcesses()
{
    const wchar_t* names[] = {
        L"easytier-core.exe", L"easytier-cli.exe", L"wv2login.exe",
    };
    for (const wchar_t* n : names) {
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snap == INVALID_HANDLE_VALUE) continue;
        PROCESSENTRY32W pe = { sizeof(pe) };
        if (Process32FirstW(snap, &pe)) {
            do {
                if (_wcsicmp(pe.szExeFile, n) == 0) {
                    HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, pe.th32ProcessID);
                    if (h) {
                        TerminateProcess(h, 0);
                        CloseHandle(h);
                    }
                }
            } while (Process32NextW(snap, &pe));
        }
        CloseHandle(snap);
    }
    Sleep(500);   // 等句柄释放
}

// ── 2026-08-15：复制单个文件，失败重试 8 次（0.5/1/1.5/…/4s ≈ 18s）──
// 覆盖目标：DeleteFileW 先行（目标只读/存在）；每次失败记录具体文件路径到
// 日志（此前只报 error 32 无路径，无法定位）。返回 true 成功；失败时
// *failPath 记录是哪个文件。
static bool copyFileOverwrite(const std::wstring& src, const std::wstring& dst,
                              std::wstring* failPath = nullptr)
{
    for (int attempt = 0; attempt < 8; ++attempt) {
        // 2026-11-20 实测：目标文件带只读属性时 CopyFileW 恒报 ERROR_ACCESS_DENIED(5)，
        // 后面 DeleteFileW 也删不掉 → 8 次重试纯浪费 18 秒，整个更新被迫中止。
        // 覆盖前先把目标属性清成 NORMAL（失败无所谓，只是尽力而为）。
        SetFileAttributesW(dst.c_str(), FILE_ATTRIBUTE_NORMAL);
        if (CopyFileW(src.c_str(), dst.c_str(), FALSE)) return true;
        const DWORD err = GetLastError();
        DeleteFileW(dst.c_str());
        logMsg(L"[SLUpdater] 复制失败 %s -> %s (err=%lu, attempt=%d)",
               src.c_str(), dst.c_str(), err, attempt + 1);
        Sleep(500 * (attempt + 1));
    }
    if (failPath) *failPath = dst;
    return false;
}

// ── 递归复制（覆盖+新增）；skipExe=true 跳过两个 exe（单独处理）──
// done/total 用于进度（40%→90%）。
// 2026-08-15：isBin=true 的子树（bin/ 联机组件：easytier/wintun/WinDivert）失败
// 降级跳过（联机可选功能，缺失不阻止启动器更新；日志记录），核心文件失败
// 才整体失败（*firstFail 记录具体文件）。
static bool copyTreeOverwrite(const std::wstring& srcDir, const std::wstring& dstDir,
                              DWORD& done, DWORD total, bool skipExe,
                              bool isBin, int* skipped, std::wstring* firstFail)
{
    CreateDirectoryW(dstDir.c_str(), nullptr);
    std::wstring search = srcDir + L"\\*";
    WIN32_FIND_DATAW fd;
    HANDLE hFind = FindFirstFileW(search.c_str(), &fd);
    if (hFind == INVALID_HANDLE_VALUE) return true;

    bool ok = true;
    do {
        if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0) continue;
        std::wstring s = srcDir + L"\\" + fd.cFileName;
        std::wstring d = dstDir + L"\\" + fd.cFileName;
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            const bool childBin = isBin || wcscmp(fd.cFileName, L"bin") == 0;
            if (!copyTreeOverwrite(s, d, done, total, skipExe, childBin, skipped, firstFail)) {
                ok = false; break;
            }
        } else {
            if (skipExe && (wcscmp(fd.cFileName, L"ShadowLauncher.exe") == 0
                         || wcscmp(fd.cFileName, L"SLUpdater.exe") == 0)) continue;
            if (!copyFileOverwrite(s, d)) {
                if (isBin) {
                    (*skipped)++;
                    logMsg(L"[SLUpdater] bin 联机组件复制失败已跳过: %s", d.c_str());
                    continue;   // 联机可选，降级跳过
                }
                if (firstFail) *firstFail = d;
                ok = false; break;
            }
            done++;
            if (total > 0) {
                const int pct = 40 + static_cast<int>(static_cast<double>(done) * 50.0 / static_cast<double>(total));
                setPhase(L"正在更新文件…", pct);
            }
        }
    } while (FindNextFileW(hFind, &fd));
    FindClose(hFind);
    return ok;
}

// ── 全量后删除多余旧文件：排除保留项 + extracted 内同名（刚复制的新文件）──
static void deleteStaleFiles(const std::wstring& appDir, const std::wstring& keepDir)
{
    std::wstring search = appDir + L"\\*";
    WIN32_FIND_DATAW fd;
    HANDLE hFind = FindFirstFileW(search.c_str(), &fd);
    if (hFind == INVALID_HANDLE_VALUE) return;
    do {
        if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0) continue;
        // 保留：游戏数据 / 日志 / Java 缓存 / 更新临时 / 协议记录 / 两个 exe（已单独处理）
        if (wcscmp(fd.cFileName, L".minecraft") == 0
            || wcscmp(fd.cFileName, L"logs") == 0
            || wcscmp(fd.cFileName, L"java_cache") == 0
            || wcscmp(fd.cFileName, L"_update") == 0
            || wcscmp(fd.cFileName, L"agreement_consent.txt") == 0
            || wcscmp(fd.cFileName, L"ShadowLauncher.exe") == 0
            || wcscmp(fd.cFileName, L"ShadowLauncher.exe.old") == 0
            || wcscmp(fd.cFileName, L"SLUpdater.exe") == 0)
            continue;
        // keepDir 有同名 → 刚复制的新文件，保留
        const std::wstring kept = keepDir + L"\\" + fd.cFileName;
        if (GetFileAttributesW(kept.c_str()) != INVALID_FILE_ATTRIBUTES) continue;
        const std::wstring p = appDir + L"\\" + fd.cFileName;
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            removeDirRecursive(p);
        else
            DeleteFileW(p.c_str());
    } while (FindNextFileW(hFind, &fd));
    FindClose(hFind);
}

// ── 2026-11-20：进程级 DPI 感知（卡片按物理像素自绘，不感知会整体发虚）──
static void enableDpiAwareness()
{
    typedef BOOL (WINAPI* PFN_SETCTX)(HANDLE);
    auto p = reinterpret_cast<PFN_SETCTX>(
        GetProcAddress(GetModuleHandleW(L"user32.dll"), "SetProcessDpiAwarenessContext"));
    // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 == (HANDLE)-4
    if (p && p(reinterpret_cast<HANDLE>(static_cast<INT_PTR>(-4)))) return;
    SetProcessDPIAware();   // Win7/8 兜底
}

static UINT systemDpi()
{
    typedef UINT (WINAPI* PFN_GETDPI)(void);
    auto p = reinterpret_cast<PFN_GETDPI>(
        GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForSystem"));
    if (p) {
        const UINT d = p();
        if (d >= 48 && d <= 480) return d;
    }
    HDC dc = GetDC(nullptr);
    const UINT d = dc ? static_cast<UINT>(GetDeviceCaps(dc, LOGPIXELSY)) : 96u;
    if (dc) ReleaseDC(nullptr, dc);
    return d ? d : 96u;
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, LPWSTR, int)
{
    enableDpiAwareness();
    {
        Gdiplus::GdiplusStartupInput gi;
        if (Gdiplus::GdiplusStartup(&g_gdiplus, &gi, nullptr) != Gdiplus::Ok)
            g_gdiplus = 0;
        g_scale = static_cast<float>(systemDpi()) / 96.0f;
        if (g_scale < 0.75f) g_scale = 1.0f;
    }

    // 2026-08-11 修复：wWinMain 的 lpCmdLine 不含程序名，必须用 GetCommandLineW()
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);

    // ── 开发用：--card-test 只把卡片显示出来并循环几档进度（不碰任何文件）──
    //    SLUpdater.exe --card-test [top]
    //    不给 top 就按正式流程的 z 序显示；给 top 则强制置顶，用来区分
    //    「画不出来」和「被别的窗口挡住」两种看不见。
    if (argc >= 2 && _wcsicmp(argv[1], L"--card-test") == 0) {
        const bool forcedTop = (argc >= 3 && _wcsicmp(argv[2], L"top") == 0);
        wchar_t self[MAX_PATH] = { 0 };
        GetModuleFileNameW(nullptr, self, MAX_PATH);
        std::wstring selfPath = self;
        const size_t slash = selfPath.find_last_of(L"\\/");
        const std::wstring dir = (slash == std::wstring::npos) ? std::wstring()
                                                              : selfPath.substr(0, slash);
        LocalFree(argv);
        openLog(dir);                       // 诊断日志写到 <dir>\_update\sl_updater.log
        logMsg(L"[SLUpdater] --card-test 开始 dir=%s top=%d", dir.c_str(), forcedTop ? 1 : 0);
        createProgressWindow(hInst, dir + L"\\ShadowLauncher.exe");
        if (forcedTop)
            SetWindowPos(g_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        const int seq[] = { -1, 8, 25, 62, 87, 100 };
        const wchar_t* txt[] = { L"正在等待旧版本退出…", L"正在更新文件…", L"正在更新文件…",
                                 L"正在更新文件…", L"正在更新文件…", L"更新完成，正在启动…" };
        for (int i = 0; i < 6; ++i) {
            setPhase(txt[i], seq[i]);
            wchar_t dump[MAX_PATH] = { 0 };
            swprintf_s(dump, L"%s\\card_%d_%d.png", dir.c_str(), i, seq[i] < 0 ? -1 : seq[i]);
            dumpCardToPng(dump);
            const DWORD t0 = GetTickCount();
            while (GetTickCount() - t0 < 1800) { pumpMessages(); Sleep(8); }
        }
        DestroyWindow(g_hwnd);
        return 0;
    }

    if (argc < 4) {
        MessageBoxW(nullptr,
            L"Usage: SLUpdater.exe <oldPID> <oldExePath> <newFilePath> [fullExtractDir]",
            L"Shadow Launcher Update", MB_ICONINFORMATION);
        LocalFree(argv);
        return 1;
    }

    // 2026-08-15：立即拷贝到本地变量后再 LocalFree（修 use-after-free：
    // 旧代码 LocalFree 后仍用 argv[1] 调 OutputDebugStringW）
    const DWORD oldPid = static_cast<DWORD>(_wtoi(argv[1]));
    std::wstring oldExePath = argv[2];
    std::wstring newFilePath = argv[3];
    const std::wstring fullExtractDir = (argc >= 5) ? argv[4] : std::wstring();
    LocalFree(argv);

    auto stripQuotes = [](std::wstring& s) {
        if (s.size() >= 2 && s.front() == L'"' && s.back() == L'"')
            s = s.substr(1, s.size() - 2);
    };
    stripQuotes(oldExePath);
    stripQuotes(newFilePath);

    std::wstring appDirW = oldExePath.substr(0, oldExePath.find_last_of(L"\\/"));
    const bool isFull = !fullExtractDir.empty();

    // ── 1. 进度窗口（图标取自启动器 exe）──
    createProgressWindow(hInst, oldExePath);
    setPhase(L"正在等待旧版本退出…", -1);

    // ── 2. 等旧进程退出（30s 超时强制终止）──
    if (!waitForProcess(oldPid, 30000)) {
        OutputDebugStringW(L"[SLUpdater] oldPid 未正常退出，强制终止\n");
        HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, oldPid);
        if (h) {
            TerminateProcess(h, 0);
            CloseHandle(h);
            Sleep(1000);
        }
    }
    Sleep(500);   // 确保文件句柄释放
    pumpMessages();

    // ── 2026-08-15：结束 helper 进程，避免复制报 error 32（共享冲突）──
    killHelperProcesses();

    // ── 3. 全量：复制新文件（覆盖+新增）→ 删多余旧文件 ──
    if (isFull) {
        openLog(appDirW);
        logMsg(L"[SLUpdater] 全量更新开始 oldPid=%lu isFull=1", oldPid);
        logMsg(L"[SLUpdater] dpi=%u scale=%.2f 窗口=%dx%d（物理像素）", systemDpi(), g_scale, g_sw, g_sh);
        setPhase(L"正在更新文件…", 5);
        DWORD total = countFilesRecursive(fullExtractDir);
        DWORD done = 0;
        int skippedBin = 0;
        std::wstring firstFail;
        if (!copyTreeOverwrite(fullExtractDir, appDirW, done, total, true,
                               false, &skippedBin, &firstFail)) {
            // 失败：不删 state.json / zip → 下次启动 PreInit 自动重试（自愈）
            logMsg(L"[SLUpdater] 全量复制失败，保留现场待重试。失败文件: %s 已复制=%lu/%lu 跳过bin=%d",
                   firstFail.c_str(), done, total, skippedBin);
            if (g_logFile) { fclose(g_logFile); g_logFile = nullptr; }
            wchar_t errBuf[1024];
            swprintf_s(errBuf, L"文件更新失败(%s)，将保留现场，下次启动自动重试。详情见 _update/sl_updater.log",
                       firstFail.c_str());
            showError(errBuf, ERROR_SHARING_VIOLATION);
            DestroyWindow(g_hwnd);
            return 4;
        }
        if (skippedBin > 0)
            logMsg(L"[SLUpdater] 警告: %d 个 bin/ 联机组件复制失败已跳过（不影响启动器本体）", skippedBin);
        setPhase(L"正在清理旧文件…", 92);
        deleteStaleFiles(appDirW, fullExtractDir);
    } else {
        openLog(appDirW);
        logMsg(L"[SLUpdater] 增量更新开始 oldPid=%lu isFull=0", oldPid);
    }

    // ── 4. 替换 exe（增量/全量共用）：rename old → .old，move new → old，失败回滚 ──
    setPhase(L"正在替换主程序…", 95);
    {
        std::wstring backupPath = oldExePath + L".old";
        DeleteFileW(backupPath.c_str());   // 清上次残留备份
        if (!MoveFileExW(oldExePath.c_str(), backupPath.c_str(), MOVEFILE_REPLACE_EXISTING)) {
            DWORD err = GetLastError();
            if (err != ERROR_FILE_NOT_FOUND) {
                showError(L"Cannot remove old version", err);
                DestroyWindow(g_hwnd);
                return 2;
            }
        }
        if (!MoveFileExW(newFilePath.c_str(), oldExePath.c_str(), MOVEFILE_REPLACE_EXISTING)) {
            MoveFileExW(backupPath.c_str(), oldExePath.c_str(), MOVEFILE_REPLACE_EXISTING);   // 回滚
            showError(L"Cannot install new version, restored old version", GetLastError());
            DestroyWindow(g_hwnd);
            return 3;
        }
        DeleteFileW(backupPath.c_str());   // 替换成功，删除旧 exe 备份
    }

    // ── 5. 清理 _update（state/lock/zip/extracted/日志 一并删除）──
    if (g_logFile) { fclose(g_logFile); g_logFile = nullptr; }   // 先关日志再删目录
    setPhase(L"正在清理更新缓存…", 98);
    removeDirRecursive(appDirW + L"\\_update");
    pumpMessages();

    // ── 6. 重启新版本 ──
    // 800ms 而不是 300ms：卡片要让人看清"完成"这一帧（300ms 基本一闪而过）
    setPhase(L"更新完成，正在启动…", 100);
    Sleep(800);
    // 2026-11-20：目标目录里没有 Qt 运行库时不要硬起 —— CreateProcessW 会成功，
    // 但进程在加载阶段失败并弹出系统的「找不到 Qt6Qml.dll，无法继续执行代码」原生对话框，
    // 用户完全看不懂，还以为更新把启动器弄坏了。这里先体检，给人话提示。
    if (GetFileAttributesW((appDirW + L"\\Qt6Qml.dll").c_str()) == INVALID_FILE_ATTRIBUTES) {
        logMsg(L"[SLUpdater] 目标目录缺少 Qt6Qml.dll，跳过自动启动 dir=%s", appDirW.c_str());
        setPhase(L"更新完成，请手动启动", 100);
        Sleep(1500);
        MessageBoxW(nullptr,
            L"更新已写入，但这个目录里缺少 Qt 运行库（Qt6Qml.dll），无法自动启动。\n"
            L"请重新安装完整版本，或把完整包里的 DLL 补回该目录。",
            L"Shadow Launcher 更新", MB_ICONWARNING);
        DestroyWindow(g_hwnd);
        return 0;
    }

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = {};
    if (!CreateProcessW(oldExePath.c_str(), nullptr, nullptr, nullptr, FALSE,
                        0, nullptr, nullptr, &si, &pi)) {
        showError(L"更新完成，但无法自动重启，请手动启动", GetLastError());
        DestroyWindow(g_hwnd);
        return 0;
    }
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    DestroyWindow(g_hwnd);
    return 0;
}
