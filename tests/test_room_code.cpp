// SPDX-License-Identifier: AGPL-3.0-or-later
// 房码规范化单测（2026-11-27 审计 D16）
//
// 缺陷：parse() 只把用户输入 c.toUpper() 存进 chars，I/O 仅在 charToValue 校验时按 1/0 处理。
// 于是 displayCode / networkName / networkKey 全部保留原始 I/O 形态：
//   · 回显码与房主不一致；
//   · networkName 不一致 ⇒ easytier 网络名对不上。
// 修复：存回字符集规范字符（kCharset[value]），I→1、O→0。
//
// 用法：RoomCodeTest.exe   退出码 0=PASS 1=FAIL

#include "multiplayer/room_code.h"

#include <QCoreApplication>
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
    std::printf("=== 房码 I/O 规范化（D16）===\n");

    // 1) 生成一个合法码，构造 I/O 易混变体，验证解析后与房主完全一致
    bool tested = false;
    for (int attempt = 0; attempt < 500 && !tested; ++attempt) {
        const auto owner = RoomCode::generate();
        const QString orig = owner.displayCode;
        if (!orig.contains(QLatin1Char('1')) && !orig.contains(QLatin1Char('0')))
            continue;   // 需要含 1 或 0 才能构造易混变体

        QString variant = orig;
        variant.replace(QLatin1Char('1'), QLatin1Char('I'));
        variant.replace(QLatin1Char('0'), QLatin1Char('O'));

        const auto guest = RoomCode::parse(variant);
        std::printf("  房主码=%s  访客输入=%s\n", qPrintable(orig), qPrintable(variant));
        check(guest.has_value(), "I/O 变体应能解析（校验时按 1/0 映射）");
        if (guest) {
            std::printf("  访客解析后 display=%s\n", qPrintable(guest->displayCode));
            check(guest->displayCode == orig, "displayCode 应规范化为 1/0 形态");
            check(guest->networkName == owner.networkName, "networkName 应与房主一致（否则隧道对不上）");
            check(guest->networkKey == owner.networkKey, "networkKey 应与房主一致");
        }
        tested = true;
    }
    check(tested, "找到一个含 1/0 的合法码用于构造变体");

    // 2) 小写输入同样规范化
    {
        const auto p = RoomCode::generate();
        const QString lower = p.displayCode.toLower();
        const auto q = RoomCode::parse(lower);
        check(q.has_value(), "小写房码应可解析");
        if (q) {
            check(q->displayCode == p.displayCode, "小写输入解析后应与原始码一致");
            check(q->networkName == p.networkName, "小写输入 networkName 应一致");
        }
    }

    // 3) 规范化不能放过真正非法的码
    {
        check(!RoomCode::parse(QStringLiteral("U/1234-5678-9012-3456")).has_value(),
              "校验和不匹配的码应被拒绝");
        check(!RoomCode::parse(QStringLiteral("X/1WNK-214W-4KL8-44UP")).has_value(),
              "前缀不是 U/ 应被拒绝");
        check(!RoomCode::parse(QStringLiteral("U/1WNK-214W-4KL8-44U")).has_value(),
              "位数不足应被拒绝");
    }

    std::printf("\n=== %s (%d FAIL) ===\n", g_fail == 0 ? "PASS" : "FAIL", g_fail);
    return g_fail == 0 ? 0 : 1;
}
