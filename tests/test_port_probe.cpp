// SPDX-License-Identifier: AGPL-3.0-or-later
// 端口探测口径单测（2026-11-26 审计 E4）
//
// 缺陷：PortRequest::requestSpecific 绑 127.0.0.1 判定"可用"，而 addPortForward 实际绑
// 0.0.0.0。Windows 允许「已占 0.0.0.0:P 再绑 127.0.0.1:P」，于是探测恒判可用，
// 真正建转发时 easytier 报 os error 10048；随后校验连 127.0.0.1:P 落到本机别的程序上
// 并"验证通过" → 界面显示已加入房间，隧道实际没建起来。
//
// 本测试同时验证两件事：
//   1) 前提成立：0.0.0.0:P 被占时，127.0.0.1:P 仍可绑（旧口径会误判）
//   2) 修复有效：0.0.0.0:P 被占时，requestSpecific(P) 返回 0；释放后返回 P
//
// 用法：PortProbeTest.exe      退出码 0=PASS 1=FAIL

#include "multiplayer/port_request.h"

#include <QCoreApplication>
#include <QHostAddress>
#include <QTcpServer>
#include <cstdio>

static int g_fail = 0;

static void check(bool ok, const char* what)
{
    std::printf("  [%s] %s\n", ok ? "OK" : "FAIL", what);
    if (!ok) ++g_fail;
}

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    std::printf("=== 端口探测口径（E4）===\n");

    // 模拟"别的程序已占 0.0.0.0:P" —— 这正是 addPortForward 要绑的地址
    QTcpServer wildcard;
    if (!wildcard.listen(QHostAddress::AnyIPv4, 0)) {
        std::printf("  [SKIP] 无法占用通配端口: %s\n", qPrintable(wildcard.errorString()));
        return 2;
    }
    const quint16 port = wildcard.serverPort();
    std::printf("  占用 0.0.0.0:%u\n", port);

    // 1) 前提：同一端口在 127.0.0.1 上仍能绑（旧探测口径因此会误判"可用"）
    {
        QTcpServer loopback;
        const bool canBind = loopback.listen(QHostAddress::LocalHost, port);
        std::printf("  127.0.0.1:%u 可绑=%s（旧口径据此误判可用）\n", port, canBind ? "true" : "false");
        if (canBind) loopback.close();
        check(canBind, "前提成立：通配被占时回环地址仍可绑 —— 旧口径会误判");
    }

    // 2) 修复：探测口径与转发一致，必须判为被占
    {
        const quint16 got = PortRequest::requestSpecific(port);
        std::printf("  requestSpecific(%u) = %u\n", port, got);
        check(got == 0, "通配端口被占时 requestSpecific 返回 0（判被占）");
    }

    // 3) 释放后应判为可用
    wildcard.close();
    {
        const quint16 got = PortRequest::requestSpecific(port);
        std::printf("  释放后 requestSpecific(%u) = %u\n", port, got);
        check(got == port, "端口释放后 requestSpecific 返回该端口");
    }

    // 4) requestFree 也应给出真正可绑 0.0.0.0 的端口
    {
        const quint16 freePort = PortRequest::requestFree(21234);
        QTcpServer probe;
        const bool ok = freePort > 0 && probe.listen(QHostAddress::AnyIPv4, freePort);
        std::printf("  requestFree() = %u  可绑 0.0.0.0=%s\n", freePort, ok ? "true" : "false");
        if (ok) probe.close();
        check(ok, "requestFree 返回的端口能真正绑到 0.0.0.0");
    }

    std::printf("\n=== %s (%d FAIL) ===\n", g_fail == 0 ? "PASS" : "FAIL", g_fail);
    return g_fail == 0 ? 0 : 1;
}
