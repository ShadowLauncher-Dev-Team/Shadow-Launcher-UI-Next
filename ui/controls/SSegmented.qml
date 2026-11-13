// SPDX-License-Identifier: AGPL-3.0-or-later
// 分段控件：等价宽按钮，选中态蓝底
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    property var items: []
    property int currentIndex: 0
    property int itemHeight: 26
    signal activated(int index)

    implicitHeight: itemHeight + 4
    // 每项等宽，宽度由**最长那条文案**决定 —— 不能只看 60px 下限。
    // 之前英文 "System language" 比 60px 宽，文字溢出到隔壁项上，三项叠在卡片外。
    readonly property real segW: Math.max(60, maxTextW + 12)
    implicitWidth: segW * Math.max(1, items.length) + Math.max(0, items.length - 1) * 2 + 4

    TextMetrics {
        id: metrics
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
    readonly property real maxTextW: {
        var w = 0
        for (var i = 0; i < items.length; i++) {
            metrics.text = items[i]
            if (metrics.width > w) w = metrics.width
        }
        return w
    }

    // 实际每段宽度 = max(测量宽度, 容器均分宽度)。
    // 只取测量值的话：调用方给了固定 width（如账号页的 180）时段落会缩成 60 一排挤在左边，
    // 右边留一大片空白，选中滑块也跟着错位 —— 那正是"滑块大小异常"。
    // 容器比文字窄时（英文长标签）才由测量值把容器撑开。
    readonly property real effSegW: Math.max(segW,
        (row.width - Math.max(0, items.length - 1) * row.spacing) / Math.max(1, items.length))

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: Theme.bgCard2
        border.width: 1
        border.color: Theme.line2
    }

    // 选中滑块：整块在分项之间滑动（与主菜单 SideBar 的胶囊同一套语言）。
    // 原来每项各自画选中底色 —— 切换是"旧的灭、新的亮"两个互不相关的动作，读不出方向。
    // 分项等宽，所以位置可以直接算；width 也加过渡，避免 items 数量变化时硬跳。
    Rectangle {
        id: segPill
        readonly property real segW: root.effSegW
        x: 2 + root.currentIndex * (segW + row.spacing)
        y: 2
        width: segW
        height: row.height
        radius: 6
        color: Theme.accentSoft
        Behavior on x {
            NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
        }
        Behavior on width {
            NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter }
        }
    }

    Row {
        id: row
        anchors.fill: parent
        anchors.margins: 2
        spacing: 2
        Repeater {
            model: root.items
            delegate: Rectangle {
                width: root.effSegW
                height: row.height
                radius: 6
                // 选中底色由上面的 segPill 承担；这里不再自己变色，否则滑块滑动时旧项还在亮
                color: "transparent"
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: index === root.currentIndex ? Theme.accentText : Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    Behavior on color {
                        ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.currentIndex === index) return
                        root.currentIndex = index
                        root.activated(index)
                    }
                }
            }
        }
    }
}
