// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Effects
import ShadowLauncher.Next

// 启动动画里"影子"那一层：同一句 SHADOW 的模糊版本，强度由外面驱动。
//
// 单独一个文件而不是写进 StartupIntro.qml，是为了把 QtQuick.Effects 的依赖关在这里：
// 万一某个发布包里没有这个模块，Loader 加载失败只是**没有光晕**，
// 而整段启动动画（在 StartupIntro.qml 里）照旧能跑。
Item {
    id: halo
    property real px: 44
    property real strength: 1

    Text {
        id: src
        anchors.centerIn: parent
        text: "SHADOW"
        color: Theme.fg
        font.family: Theme.fontFamily
        font.weight: Font.Bold
        font.pixelSize: halo.px
        font.letterSpacing: 2.2
        renderType: Text.NativeRendering
        visible: false          // 只当 MultiEffect 的源
    }

    MultiEffect {
        anchors.centerIn: parent
        width: src.implicitWidth
        height: src.implicitHeight
        source: src
        blurEnabled: true
        blurMax: 40
        blur: halo.strength
        autoPaddingEnabled: true
        opacity: halo.strength
    }
}
