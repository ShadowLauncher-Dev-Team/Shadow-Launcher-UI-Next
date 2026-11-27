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

    // ── 键盘（统一契约四件套）──
    // 纯 Item + Repeater 手绘，**不是 QtQuick.Controls 的 Control/RadioButton**：
    // 方向键与选中都没有自带行为，必须自己实现。"不可用"判据是 Item 自带的 enabled。
    activeFocusOnTab: root.enabled

    // 鼠标与键盘共用的唯一入口：改选中 + 发 activated。
    // 越界（←/→ 到头）直接忽略、不做环绕 —— 环绕等于"到最后一项又跳回第一项"，看不出是到头了。
    function selectSegment(i) {
        if (i < 0 || i >= root.items.length) return
        if (i === root.currentIndex) return
        root.currentIndex = i
        root.activated(i)
    }

    // 每项等宽，宽度由**最长那条文案**决定 —— 不能只看 60px 下限。
    // 之前英文 "System language" 比 60px 宽，文字溢出到隔壁项上，三项叠在卡片外。
    // +20 而不是 +12：TextMetrics 与实际 Text 的排版有细微差异（字距/微调），
    // 只留 12px 时「分代 ZGC」这类刚好卡边的文案会被省略号吃掉。左右各 6px 内边距 + 8px 余量。
    readonly property real segW: Math.max(60, maxTextW + 20)
    implicitWidth: segW * Math.max(1, items.length) + Math.max(0, items.length - 1) * 2 + 4

    TextMetrics {
        id: metrics
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
    // 用**函数**量宽度，不用绑定：TextMetrics.text 是读写属性，写在绑定里赋值会把自己
    // 变成它自己的依赖 → Qt 报 "Binding loop detected for property maxTextW"（实测刷满日志）。
    // 函数在 items 变化/组件完成时各跑一次就够了。
    property real maxTextW: 0
    function measureText() {
        var w = 0
        for (var i = 0; i < items.length; i++) {
            metrics.text = items[i]
            if (metrics.width > w) w = metrics.width
        }
        maxTextW = w
    }
    onItemsChanged: measureText()
    Component.onCompleted: measureText()

    // 实际每段宽度 = max(测量宽度, 容器均分宽度)。
    // 只取测量值的话：调用方给了固定 width（如账号页的 180）时段落会缩成 60 一排挤在左边，
    // 右边留一大片空白，选中滑块也跟着错位 —— 那正是"滑块大小异常"。
    // 容器比文字窄时（英文长标签）才由测量值把容器撑开。
    // 注意分母用 root.width 而不是 row.width：row 的宽度又来自每段 width，用它会成环。
    readonly property real effSegW: Math.max(segW,
        (root.width - Math.max(0, items.length - 1) * row.spacing) / Math.max(1, items.length))

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
                    // 文字永远在自己这一段里：超长就省略号，绝不能溢出去压到相邻项、
                    // 也不能突破外面那层圆角边框（英文长标签踩过这个坑）。
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
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
                    // 点一下也拿焦点：键盘与鼠标共用同一套焦点状态
                    onPressed: { Theme.keyboardNav = false; root.forceActiveFocus() }
                    onClicked: root.selectSegment(index)
                }
            }
        }
    }

    // ←/→ 在分项之间移动并立刻选中。故意不接管 Space/Enter：
    // 本控件"选中即生效"，没有独立的激活动作，多给一个 Space 只会让焦点停在哪一项产生歧义。
    // 不接管 ↑/↓：垂直键留给外层滚动容器，翻页时按上下键仍然滚页面。
    Keys.onPressed: function(e) {
        if (!root.enabled) return
        if (e.key === Qt.Key_Left) {
            e.accepted = true
            root.selectSegment(root.currentIndex - 1)
        } else if (e.key === Qt.Key_Right) {
            e.accepted = true
            root.selectSegment(root.currentIndex + 1)
        }
    }

    // 焦点环：独立一层描边，只锚定 + 负 margin，不占布局
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingGap
        radius: (root.radius !== undefined ? root.radius : 8) + Theme.focusRingGap
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && Theme.keyboardNav
        z: 999
        antialiasing: true
    }
}
