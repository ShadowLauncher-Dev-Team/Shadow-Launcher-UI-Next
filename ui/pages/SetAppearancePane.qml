// SPDX-License-Identifier: AGPL-3.0-or-later
// 外观（占位）—— 后端尚未合并，接口先不接，避免做出「改了但只影响一半」的假功能。
//
// 现状：外观这块有三套互不通气的实现
//   1. ui/Theme.qml：色板/动效常量，硬编码，UI 唯一直读
//   2. Appearance 单例（AppearanceController）：主题/明暗/密度/减动效，API 齐全但 Theme 不读它
//   3. SettingsBackend 的 customBg 系列：自定义壁纸/透明度/模糊/裁剪，只有 2 个页面用了 2 处
// 三者合一（Theme 读 Appearance、壁纸并入）之后才接这一页。
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property var toast: null

    Column {
        x: 40
        y: 4
        width: Math.min(900, pane.width - 80)
        spacing: 14

        Text {
            text: "外观设置暂未接入"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            text: "主题、界面密度、减少动效、自定义背景这几块的后端目前是分开的三套，还没有合并成一套统一的来源。现在接进来只会出现「改了但只影响一部分界面」的情况，所以先留空，等后端理清再接。"
            color: Theme.fg2
            font.family: Theme.fontFamily
            font.pixelSize: 12
            lineHeight: 1.7
            wrapMode: Text.WordWrap
        }
    }
}
