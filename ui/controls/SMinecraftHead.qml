// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 方形 MC 头像（无圆角、无边框 —— 用户 2026-11-04 明确要求）
//
// 清晰度要点（2026-11-04 用户反馈"头像很模糊"后重做）：
//   · 首选 backend.skinTexturePath（64×64 原始皮肤），自己裁脸 (8,8,8,8)。
//     不用 backend.skinPath —— 那个是 renderHead3D() 的产物，实测对部分皮肤会渲染出错图
//     （本项目账号的 _head.png 是"左紫右灰"的拼接块，不是脸）。
//   · smooth: false + mipmap: false：MC 皮肤是像素图，最近邻放大才锐利。
//     之前用 smooth: true 把 8×8 插值放大 7 倍 → 整张糊成一团，就是用户看到的问题。
//   · 放大用整数倍（k = size/8 向上取整到 >=1），避免出现 7px/8px 参差的格子。
Item {
    id: root
    /// 整张皮肤（首选，64×64 标准 UV）
    property string rawSource: ""
    /// 后端渲染好的头部图（兜底）
    property string source: ""
    property int size: 22
    property string fallbackText: "?"

    width: size
    height: size
    clip: true

    readonly property string effectiveSource: root.rawSource.length > 0 ? root.rawSource : root.source

    // 首选：原始皮肤 → 裁脸 (8,8,8,8) → 最近邻放大
    Item {
        anchors.fill: parent
        visible: root.rawSource.length > 0
        clip: true

        Image {
            // 每格放大倍数 = size/8。不要向上取整：取整后 8 格会比容器大（22px 时 8*3=24），
            // 右/下边缘会被裁掉。56 这类能整除的尺寸仍是整数格，完美对齐。
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

    // 兜底：后端头图，直接铺满（同样最近邻）
    Image {
        anchors.fill: parent
        visible: root.rawSource.length === 0 && root.source.length > 0 && status === Image.Ready
        source: root.source
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        mipmap: false
        smooth: false
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
