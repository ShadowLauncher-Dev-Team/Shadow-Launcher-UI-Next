import QtQuick
import ShadowLauncher.Next

// 通用「拖入文件」投放区。
// 三个场景共用：账号页（authlib-injector jar）、版本页（整合包 .zip/.mrpack）、
// 资源页（mod / 资源包 / 光影）。
//
// 用法：
//   SDropZone {
//       anchors.fill: parent
//       active: page.dragActive          // 由外部或内部状态控制
//       accept: [".jar", ".zip", ".mrpack"]
//       onDropped: (urls) => page.handleDrop(urls)
//   }
//
// 设计约束（项目铁律）：
//   · 不使用任何 emoji / Unicode 图标，提示文字纯文本；图标用 SIcon
//   · 动画只用 Theme.dur* / Theme.ease*
//   · font.pixelSize 用整数
//   · 不做全局覆盖式投放区：只在目标页面挂载，避免抢走别的页面的 drop
//
// 2026-11-13 踩过的两个坑（都实测过，别再写回去）：
//   ① 根 Item 写 visible: parent/self 的某个"状态" → 常态不可见时 DropArea 收不到任何
//      拖拽事件（ENTERED 都不来），而且第一次修成 visible: containsDrag 会变成
//      "不可见→收不到事件→containsDrag 永远 false" 的死循环。
//   ② 遮罩用不透明底色 → 拖拽时整页被盖死。
//   正解：根 Item 常驻可见（它没有绘制内容，不挡不吞），可见性只给遮罩层。
Item {
    id: root

    property bool active: true
    // 允许的扩展名（小写，含点）；空数组表示不限制
    property var accept: []
    // 拖入内容是否合法：由外部决定（比如版本页只接受整合包）
    property bool showHint: true
    // 提示文案
    property string hintTitle: qsTr("松开以导入")
    property string hintBody: ""

    signal dropped(var urls)

    anchors.fill: parent
    // 注意：这个根 Item 必须保持 visible=true。
    //   DropArea 是「不可见就收不到拖拽事件」的（res-drop 用 qml.exe 双向探针验证过：
    //   父 Item visible=false 时连 ENTERED 都没有）。
    //   本控件自身没有任何绘制内容，常驻可见不会挡住页面，也不会吞点击。
    //   「拖拽时才出现提示」由下面的遮罩层自己控制。
    z: 500

    function extOf(u) {
        var s = String(u)
        var i = s.lastIndexOf(".")
        if (i < 0) return ""
        var q = s.indexOf("?", i)
        return (q < 0 ? s.substring(i) : s.substring(i, q)).toLowerCase()
    }

    function filterUrls(list) {
        var out = []
        for (var i = 0; i < list.length; ++i) {
            var u = list[i]
            if (!root.accept || root.accept.length === 0) { out.push(u); continue }
            if (root.accept.indexOf(root.extOf(u)) >= 0) out.push(u)
        }
        return out
    }

    DropArea {
        id: dropOverlay
        anchors.fill: parent
        enabled: root.active

        onEntered: (drag) => {
            var ok = root.filterUrls(drag.urls)
            if (ok.length === 0) { drag.accept() }  // 不接受，但也不吞掉
        }
        onDropped: (drop) => {
            var urls = root.filterUrls(drop.urls)
            // 自定义 scheme 的拖拽（典型：authlib-injector:yggdrasil-server:https%3A...）
            // 系统不把它当文件，urls 是空的，内容只在 text 里。
            // 不读 text 的话表现就是「拖进去了但什么都没发生」。
            if (urls.length === 0 && drop.text && String(drop.text).length > 0) {
                var trimmed = String(drop.text).trim()
                if (trimmed.length > 0) urls = [trimmed]
            }
            if (urls.length === 0) { drop.accept() }
            root.dropped(urls)
        }

        Rectangle {
            anchors.fill: parent
            // 遮罩只在拖拽经过时出现：
            //   · 不用 root.visible 控制（会让 DropArea 收不到事件）
            //   · 也不用不透明底色（会盖死页面）
            visible: dropOverlay.containsDrag
            color: Theme.scrim
            opacity: 0.88

            // 虚线框（用 4 段细边框近似，避免依赖 Shape）
            Rectangle {
                anchors.fill: parent
                anchors.margins: 10
                color: "transparent"
                radius: Theme.rMd
                border.width: 2
                border.color: Theme.accent
                opacity: 0.55
            }

            Column {
                anchors.centerIn: parent
                spacing: 6
                visible: root.showHint

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.hintTitle
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.hintBody.length > 0
                    text: root.hintBody
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }
        }
    }
}
