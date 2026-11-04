// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 方形 MC 头像（无圆角、无边框 —— 用户 2026-11-04 明确要求）
// 两种源都支持：
//   · 64×64 整张皮肤  → 裁剪脸部 (8,8,8,8) 后放大（皮肤布局固定，MC 脸就在这个格子）
//   · 128×128 头图    → 直接铺满（backend 已预渲染的 _head.png / steve_head.png）
// 用 probe 读隐含尺寸自行判断，不靠调用方猜。
Item {
    id: root
    /// 整张皮肤（优先）：能自己裁脸，不依赖后端渲染的头部图
    property string rawSource: ""
    /// 已经渲染好的头部图（兜底）
    property string source: ""
    property int size: 22
    property string fallbackText: "?"

    width: size
    height: size
    clip: true
    visible: true

    // 实际使用的图：有原始皮肤就用它，否则用头部图
    readonly property string effectiveSource: root.rawSource.length > 0 ? root.rawSource : root.source

    Image {
        id: probe
        width: 1; height: 1
        visible: false
        source: root.effectiveSource
        // 整张皮肤（64×64）。头图是 128×128，不走这条路
        readonly property bool skinSheet: status === Image.Ready
                                          && implicitWidth > 0
                                          && implicitWidth === implicitHeight
                                          && implicitWidth <= 64
    }

    // 整张皮肤：放大到 size/8 倍，平移到脸 (8,8)
    Image {
        visible: probe.skinSheet
        readonly property real k: root.size / 8.0
        width: 64 * k
        height: 64 * k
        x: -8 * k
        y: -8 * k
        source: root.effectiveSource
        sourceSize.width: 256
        sourceSize.height: 256
        fillMode: Image.Stretch
        smooth: true
        mipmap: true
    }

    // 头图或其它：直接铺满
    Image {
        visible: root.effectiveSource.length > 0 && !probe.skinSheet && probe.status === Image.Ready
        anchors.fill: parent
        source: root.effectiveSource
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        sourceSize.width: root.size * 4
        sourceSize.height: root.size * 4
    }

    // 没有皮肤：方形色块 + 首字母（同样无圆角无边框）
    Rectangle {
        anchors.fill: parent
        visible: root.effectiveSource.length === 0
        color: "#1b2432"
        Text {
            anchors.centerIn: parent
            text: root.fallbackText.length > 0 ? root.fallbackText.substring(0, 1).toUpperCase() : "?"
            color: "#9fb4cf"
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(9, Math.round(root.size * 0.45))
            font.weight: Font.DemiBold
        }
    }
}
