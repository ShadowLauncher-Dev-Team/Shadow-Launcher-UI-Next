// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

Item {
    id: root
    property bool narrow: false
    // ── 选中项用**稳定 key**，不用显示文案 ──
    // 以前这里直接存中文 label，StageShell 也拿 label 做 `=== "下载"` 判断。
    // 一旦文案进翻译（界面语言切换），判断值会跟着变成译文，整个路由直接失效。
    // 所以：key 是逻辑标识（永不翻译），label 才是给人看的（qsTr）。
    property string currentKey: "launch"
    /// 点击前停在哪一项。currentKey 会被点击立刻改掉，
    /// 外面需要「回到上一项」时只能靠这个（全局设置页退出还原用）。
    property string previousKey: "launch"
    property Window hostWindow: null
    /// 主菜单点击（StageShell 据此切换内容区页面）；传的是 key，不是文案
    signal navActivated(string key)

    implicitWidth: narrow ? Theme.sideWNarrow : Theme.sideW
    clip: true

    // ── 选中滑块（动效系统 P1）──
    // 之前每个导航项各自长一条 2px 竖条：切换是"一条缩回去、另一条长出来"，两段无关的动作。
    // 现在整块选中态是一个对象，切页时**从旧位置滑到新位置**，方向感直接读出来。
    // 几何由每个 row 自己上报（mapToItem 到本层），因为 ColumnLayout 会重排 y。
    property var _geom: ({})
    function reportGeom(key, item) {
        var pt = item.mapToItem(root, 0, 0)
        var m = {}
        for (var k in root._geom) m[k] = root._geom[k]
        m[key] = { y: pt.y, h: item.height }
        root._geom = m
    }
    readonly property var selGeom: root._geom[root.currentKey] || null
    readonly property int rowInset: root.narrow ? 8 : 12

    // key：逻辑标识（路由判断用，永不翻译）；label：显示文案（走翻译）
    readonly property var mainItems: [
        { key: "launch",      ic: "play",     label: qsTr("启动"),     group: "main" },
        { key: "download",    ic: "download", label: qsTr("下载"),     group: "main" },
        { key: "multiplayer", ic: "globe",    label: qsTr("联机"),     group: "main" },
        { key: "settings",    ic: "settings", label: qsTr("设置"),     group: "main" }
    ]
    readonly property var subItems: [
        { key: "progress", ic: "list",      label: qsTr("下载进度"), group: "sub" },
        { key: "help",     ic: "book-open", label: qsTr("帮助文档"), group: "sub" },
    ]

    Rectangle {
        anchors.fill: parent
        color: Theme.sidebar
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            property point pressPos
            onPressed: (m) => { pressPos = Qt.point(m.x, m.y) }
            onPositionChanged: (m) => {
                if (!pressed || !root.hostWindow) return
                root.hostWindow.x += m.x - pressPos.x
                root.hostWindow.y += m.y - pressPos.y
            }
        }
    }

    // 选中滑块：位于导航项之下，随 currentLabel 滑动
    Item {
        id: selPill
        x: root.rowInset
        width: Math.max(0, root.width - root.rowInset * 2)
        visible: root.selGeom !== null
        y: root.selGeom ? root.selGeom.y : 0
        height: root.selGeom ? root.selGeom.h : 0

        Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }
        Behavior on height { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }

        Rectangle {
            anchors.fill: parent
            radius: Theme.rSm
            color: Theme.bgCard
        }
        // 左侧强调条跟着滑块一起走（不再是"旧的缩回去、新的长出来"）
        Rectangle {
            width: 2
            radius: 1
            anchors.left: parent.left
            anchors.leftMargin: -6
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height * 0.42
            color: Theme.accent
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: root.narrow ? 8 : 12
        anchors.rightMargin: root.narrow ? 8 : 12
        anchors.topMargin: 16
        anchors.bottomMargin: 12
        spacing: 1

        Text {
            id: brandWord
            visible: !root.narrow
            // 品牌名，不翻译（不加 qsTr 是有意的）
            text: "SHADOW"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Bold
            font.letterSpacing: 2.2
            leftPadding: 10
            Layout.bottomMargin: 18
            // 启动动画的落点就是这里。打一次场景坐标，供核对（差 1px 交接就抖）。
            Component.onCompleted: {
                var p = brandWord.mapToItem(null, 0, 0)
                console.info("[启动动画] 侧栏字标 scene", p.x, p.y, brandWord.width, brandWord.height)
            }
        }
        Item { visible: root.narrow; Layout.preferredHeight: 6 }

        Repeater { model: root.mainItems; delegate: navRow }

        Item { Layout.preferredHeight: 12 }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.line
            visible: !root.narrow
        }
        Item { Layout.preferredHeight: 12 }

        Repeater { model: root.subItems; delegate: navRow }

        Item { Layout.fillHeight: true }

        Text {
            visible: !root.narrow
            // appVersion 已是可直接显示的完整串（含 v 前缀，见 src/version.h），此处禁止再做任何拼接装饰
            text: ((typeof backend !== "undefined" && backend) ? backend.appVersion : "")
            color: Theme.line3
            font.family: Theme.fontFamily
            font.pixelSize: 11
            leftPadding: 10
        }
    }

    Component {
        id: navRow
        Item {
            id: row
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            readonly property bool isMain: modelData.group === "main"
            // 子项（下载进度等）也能被高亮：选中态就是"当前导航项"
            readonly property bool sel: root.currentKey === modelData.key

            // 只画 hover 底色；选中底色由 root 的滑块统一提供
            Rectangle {
                anchors.fill: parent
                radius: Theme.rSm
                color: (!row.sel && rowHover.containsMouse) ? Theme.bgCard : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard } }
            }
            // 几何上报：ColumnLayout 重排 / 侧栏收窄都会改 y 与高度，跟着更新滑块位置
            function sync() { root.reportGeom(modelData.key, row) }
            Component.onCompleted: row.sync()
            onYChanged: row.sync()
            onHeightChanged: row.sync()
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.narrow ? 0 : 10
                spacing: 10
                SIcon {
                    name: modelData.ic
                    size: 17
                    color: row.sel ? Theme.fg : Theme.fg2
                    Layout.alignment: root.narrow ? Qt.AlignHCenter : Qt.AlignLeft
                    // 选中瞬间轻微弹一下（过冲缓动），提示"落到这一项了"
                    scale: row.sel ? 1.0 : 0.94
                    Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easePop } }
                }
                Text {
                    visible: !root.narrow
                    text: modelData.label
                    color: row.sel ? Theme.fg : Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: row.sel ? Font.DemiBold : Font.Normal
                }
                Item { Layout.fillWidth: true }
            }
            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    // 主项才改高亮；子项也要发信号，否则「下载进度」这类子项完全点不动
                    // 只对主项记录：子项（下载进度等）不参与"上一项"还原
                    if (row.isMain) {
                        root.previousKey = root.currentKey
                        root.currentKey = modelData.key
                    }
                    root.navActivated(modelData.key)
                }
            }
        }
    }
}