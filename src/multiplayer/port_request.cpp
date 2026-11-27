// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "port_request.h"
#include <QTcpServer>
#include <QHostAddress>

namespace PortRequest {

quint16 requestSpecific(quint16 port)
{
    // 2026-11-26 修（审计 E4）：探测必须绑 0.0.0.0，与实际转发口径一致。
    // 原实现绑 127.0.0.1，而 addPortForward 绑的是 0.0.0.0（Terracotta UNSPECIFIED）。
    // Windows 允许"已占 0.0.0.0:P 再绑 127.0.0.1:P"，于是探测恒判"可用"，
    // 真正建转发时 easytier 报 os error 10048；随后 verifier 把 127.0.0.1:P 连到
    // 本机别的程序上、判定通过 → 界面显示"已加入房间"，隧道其实没起来。
    // 代价：短暂监听全接口。启动器本来就 listen(Any) 建房间，不新增防火墙暴露面。
    QTcpServer server;
    if (server.listen(QHostAddress::AnyIPv4, port)) {
        quint16 boundPort = server.serverPort();
        server.close();  // release immediately — we just probed
        return boundPort;
    }
    return 0;  // port is occupied
}

quint16 requestFree(quint16 basePort)
{
    // 同上：探到的端口会被 addPortForward 绑成 0.0.0.0，所以这里也必须按 0.0.0.0 判定，
    // 否则同样会出现"取到看似空闲、实际转发失败"的情况。
    QTcpServer server;
    if (server.listen(QHostAddress::AnyIPv4, 0)) {
        quint16 boundPort = server.serverPort();
        server.close();
        return boundPort;
    }
    // Fallback: Terracotta's default is self as u8 as u16 + 35780
    return static_cast<quint16>(basePort + 35780);
}

} // namespace PortRequest
