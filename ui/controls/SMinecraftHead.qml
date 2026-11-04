// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 方形 MC 头像（无圆角、无边框 —— 用户 2026-11-04 明确要求）
//
// 2026-11-04 定稿，踩过三个坑，全部记录在这里，别再走回头路：
//   1) 不要自己从 64×64 皮肤裁脸 (8,8,8,8) —— 那只是脸的正面一格，
//      头发/犄角/头饰在别的 UV 格里，裁出来"角就没了"（用户原话）。
//      backend.skinPath 提供的 128×128 图是后端 renderHead3D() 渲染好的完整头部，
//      直接用它才是对的。
//   2) 清晰度靠最近邻：smooth: false + mipmap: false，且**不要设 sourceSize**
//      （预缩放到小尺寸再缩放会二次采样变糊）。旧 UI qml/MinecraftHead2D.qml 就是这么写的。
//   3) 之前用 smooth: true 显示 → 一张糊成一团，用户明确反馈过。
Item {
    id: root
    /// 后端渲染好的 128×128 完整头部图（首选）
    property string source: ""
    /// 整张皮肤（仅在拿不到头部图时兜底：裁 (8,8) 正面，会缺头发/角）
    property string rawSource: ""
    property int size: 22
    property string fallbackText: "?"

    width: size
    height: size
    clip: true

    readonly property string effectiveSource: root.source.length > 0 ? root.source : root.rawSource

    // 首选：后端头图，最近邻铺满（含头发/犄角等外层）
    Image {
        anchors.fill: parent
        visible: root.source.length > 0
        source: root.source
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        mipmap: false
        smooth: false
    }

    // 兜底：只有原始皮肤时裁正面 (8,8)，同样最近邻
    Item {
        anchors.fill: parent
        visible: root.source.length === 0 && root.rawSource.length > 0
        clip: true
        Image {
            readonly property real k: Math.max(1, root.size / 8.0)
            width: 64 * k
            height: 64 * k
            x: -8 * k
            y: -8 * k
            source: root.rawSource
            fillMode: Image.Stretch
            asynchronous: true
            cache: false
            mipmap: false
            smooth: false
        }
    }

    // 两路都没有：方形色块 + 首字母（同样无圆角无边框）
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
