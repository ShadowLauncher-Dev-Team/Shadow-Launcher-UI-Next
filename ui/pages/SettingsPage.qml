// SPDX-License-Identifier: AGPL-3.0-or-later
// 全局设置（全屏页）—— 顶栏 + 左栏七项 + 内容区
//
// 与版本设置页同一套壳：侧栏收起、页面右滑入、左栏选中胶囊整块滑动。
// 语义区别：这里改的是「全局默认值」，单个版本在版本设置页里选「独立配置」才覆盖它。
import QtQuick
import ShadowLauncher.Next

Item {
    id: page
    property var toast: null
    // 子页自学自报忙碌（Java 扫描等），转给壳的顶部光条
    property bool busy: false
    // 子页要求「实时预览」（外观页拖取景时）：壳把自身除内容区以外的部分全部隐藏
    // （底色/顶栏/左栏/页标题），内容区里的其它卡片由外观页自己淡出，
    // 只留取景预览 —— 这样背后是**完整无遮挡**的启动页，不会两层叠在一起。
    property bool livePreview: false
    readonly property real chromeOpacity: livePreview ? 0 : 1
    signal close()

    readonly property var rows: [
        { k: "general",    label: "常规",         icon: "list",     desc: "界面语言与游戏内语言的写入方式。" },
        { k: "java",       label: "Java 与内存",  icon: "cpu",      desc: "启动游戏用的 Java 运行时，以及所有版本默认分配的堆内存。" },
        { k: "launch",     label: "启动",         icon: "play",     desc: "所有版本的默认启动参数。单个版本可在版本设置里覆盖这里任意一项。" },
        { k: "download",   label: "下载",         icon: "download", desc: "版本文件与资源列表的来源、并发与限速。" },
        { k: "advanced",   label: "高级",         icon: "settings", desc: "实验性开关。" },
        { k: "appearance", label: "外观",         icon: "palette",  desc: "配色方案与启动页图片。" },
        { k: "about",      label: "关于",         icon: "info",     desc: "版本信息、许可，以及这个启动器背后的每一个名字。" }
    ]

    property string currentKey: "general"
    readonly property int navItemH: 40

    function navIndex(k) {
        for (var i = 0; i < rows.length; ++i) if (rows[i].k === k) return i
        return -1
    }
    function rowOf(k) {
        var i = navIndex(k)
        return i >= 0 ? rows[i] : rows[0]
    }
    function paneFor(k) {
        if (k === "general")    return generalComp
        if (k === "java")       return javaComp
        if (k === "launch")     return launchComp
        if (k === "download")   return downloadComp
        if (k === "advanced")   return advancedComp
        if (k === "appearance") return appearanceComp
        if (k === "about")      return aboutComp
        return generalComp
    }

    // --ui-pane <key> 直接落在某个分区（截图/验收用），与版本设置页同一个约定
    Component.onCompleted: {
        var args = Qt.application.arguments
        var i = args.indexOf("--ui-pane")
        if (i >= 0 && i + 1 < args.length && args[i + 1].indexOf("--") !== 0) {
            var k = args[i + 1]
            if (navIndex(k) >= 0) page.currentKey = k
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: page.chromeOpacity
        Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
    }

    // ---------- 顶栏 ----------
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 56
        opacity: page.chromeOpacity
        enabled: !page.livePreview
        Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }

        // 空白处拖动窗口（无边框窗口没有系统标题栏，必须显式请求系统接管移动）。
        // 放在子项最前面：后面的按钮都盖在它上面，只有空白区能走到这里。
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: { if (backend) backend.beginWindowMove() }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.line
        }

        SButton {
            id: backBtn
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            kind: 1
            radius: 2
            height: 32
            iconName: "arrow-left"
            text: "返回"
            onClicked: page.close()
        }

        Row {
            anchors.left: backBtn.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "设置"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.weight: Font.Bold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "全局默认值"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
        }
    }

    // ---------- 左栏 ----------
    Rectangle {
        id: nav
        anchors.left: parent.left
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom
        width: Theme.sideW
        color: Theme.sidebar
        opacity: page.chromeOpacity
        enabled: !page.livePreview
        Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.line
        }

        Item {
            id: navHost
            anchors.fill: parent
            anchors.topMargin: 10

            // 选中胶囊：整块从旧位置滑到新位置（继承主菜单 SideBar 的做法），
            // 不是「旧的缩回去、新的长出来」两段互不相关的动作。
            Item {
                id: selPill
                z: 0
                x: 10
                width: Math.max(0, navHost.width - 20)
                visible: page.navIndex(page.currentKey) >= 0
                y: Math.max(0, page.navIndex(page.currentKey)) * page.navItemH + 2
                height: page.navItemH - 4

                Behavior on y { NumberAnimation { duration: Theme.durSlow; easing.type: Theme.easeEnter } }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rSm
                    color: Theme.bgCard
                }
                Rectangle {
                    width: 2
                    radius: 1
                    anchors.left: parent.left
                    anchors.leftMargin: -8
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height * 0.55
                    color: Theme.accent
                }
            }

            Column {
                id: navCol
                z: 1
                width: parent.width

                Repeater {
                    model: page.rows
                    delegate: Item {
                        id: itemRoot
                        width: navCol.width
                        height: page.navItemH
                        readonly property bool active: page.currentKey === modelData.k

                        // 选中高亮由外层 selPill 承担，这里只做 hover，
                        // 否则会出现「胶囊在滑、行背景自己也在亮灭」两套高亮打架。
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            radius: Theme.rSm
                            color: Theme.bgCard2
                            opacity: (hover.hovered && !itemRoot.active) ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                            }
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 22
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 9

                            SIcon {
                                name: modelData.icon
                                size: 15
                                color: itemRoot.active ? Theme.accentText : Theme.line3
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: itemRoot.active ? Theme.fg : Theme.fg2
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                Behavior on color {
                                    ColorAnimation { duration: Theme.durFast; easing.type: Theme.easeStandard }
                                }
                            }
                        }

                        HoverHandler { id: hover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.currentKey = modelData.k
                        }
                    }
                }
            }
        }
    }

    // ---------- 内容区 ----------
    Item {
        anchors.left: nav.right
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: parent.bottom

        // 页标题（固定不滚）：分区标题 + 一句话说明，跟着左栏走
        Column {
            id: pageHead
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 40
            anchors.rightMargin: 40
            anchors.topMargin: 24
            spacing: 6
            opacity: page.chromeOpacity
            Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }

            Text {
                text: page.rowOf(page.currentKey).label
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 21
                font.weight: Font.Bold
            }
            Text {
                width: parent.width
                text: page.rowOf(page.currentKey).desc
                color: Theme.fg2
                font.family: Theme.fontFamily
                font.pixelSize: 12
                lineHeight: 1.5
                wrapMode: Text.WordWrap
            }
        }

        Loader {
            id: paneLoader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: pageHead.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 6
            sourceComponent: page.paneFor(page.currentKey)

            onLoaded: {
                page.busy = (paneLoader.item && paneLoader.item.busy) ? true : false
                // 子页的属性会变，必须用绑定转发，不能只拷一次值
                page.livePreview = Qt.binding(function() {
                    return paneLoader.item ? paneLoader.item.livePreview === true : false
                })
            }
            onSourceComponentChanged: {
                page.busy = false
                page.livePreview = false
                if (paneIn) paneIn.restart()
            }

            // 分区切换：新页淡入 + 上移 6px。只做入场不做交叉淡出 —— 旧页同帧被替换、
            // 底色一致不会闪。壳的整页切换用 durPage(320)，这里 durBase(180)，两级不抢戏。
            transform: Translate { id: paneSlide; y: 0 }

            ParallelAnimation {
                id: paneIn
                NumberAnimation {
                    target: paneLoader; property: "opacity"
                    from: 0; to: 1
                    duration: Theme.durBase
                    easing.type: Theme.easeEnter
                }
                NumberAnimation {
                    target: paneSlide; property: "y"
                    from: 6; to: 0
                    duration: Theme.durBase
                    easing.type: Theme.easeEnter
                }
            }
        }
    }

    Component { id: generalComp;    SetGeneralPane    { toast: page.toast; onBusyChanged: page.busy = busy } }
    Component { id: javaComp;       SetJavaPane       { toast: page.toast; onBusyChanged: page.busy = busy } }
    Component { id: launchComp;     SetLaunchPane     { toast: page.toast } }
    Component { id: downloadComp;   SetDownloadPane   { toast: page.toast } }
    Component { id: advancedComp;   SetAdvancedPane   { toast: page.toast } }
    Component { id: appearanceComp; SetAppearancePane { toast: page.toast } }
    Component { id: aboutComp;      SetAboutPane      { toast: page.toast } }
}
