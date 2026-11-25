// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
// 「对局域网开放」日志行解析 —— 启动器 stdout 解析与日志文件兜底共用的唯一判定处。
//
// 为什么要有这个文件（2026-11-25 实测，不是猜）：
//   MC <= 26.1.x：  [Server thread/INFO]: Started serving on 52968
//   MC >= 26.2  ：  [Render thread/INFO]: Published LAN server on port 57759
//                   （26.2 起 IntegratedServer 的文案改了；26.2 / 26.2-Forge /
//                    26.2-Fabric / 26.3 的 jar 里都只剩 "Published LAN server"。
//                    旧正则只认 "Started serving on"，于是 26.2 上线后主通道静默失效，
//                    组播一漏包就永远停在「还差游戏里开服」。）
//   MC 关闭世界：  [Server thread/INFO]: Stopping the server
//
// 判定只看英文日志，与界面语言无关；同一条聊天提示 "[CHAT] This world is now open
// to LAN. The port number is [57759]" 也带端口，但日志行更稳（不会被聊天过滤关掉）。
#pragma once
#include <QRegularExpression>
#include <QString>

namespace ShadowLauncher {
namespace McLanLog {

/// 该行是否是「对局域网开放」；命中返回端口，否则 0。
inline int openPort(const QString& line)
{
    static const QRegularExpression rx(QStringLiteral(
        "Started serving on (\\d+)|Published LAN server on port (\\d+)"));
    const auto m = rx.match(line);
    if (!m.hasMatch())
        return 0;
    const QString cap = m.captured(1).isEmpty() ? m.captured(2) : m.captured(1);
    bool ok = false;
    const int port = cap.toInt(&ok);
    return (ok && port > 0 && port < 65536) ? port : 0;
}

/// 该行是否是「关闭对局域网开放 / 退出单人世界」。
inline bool isCloseLine(const QString& line)
{
    static const QRegularExpression rx(QStringLiteral("Stopping the server|Stopping server"));
    return rx.match(line).hasMatch();
}

} // namespace McLanLog
} // namespace ShadowLauncher
