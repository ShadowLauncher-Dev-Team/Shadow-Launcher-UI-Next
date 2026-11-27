// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

// 账户胶囊：方形皮肤头 + 名字 + 状态点 + 箭头
// 规则（用户 2026-11-04 明确）：MC 头像是**方形**，QML 不用圆形头像，也不给头像加任何边框/圆角。
// 皮肤来源：backend.skinPath（正版，已是渲染好的脸图）/ backend.offlineSkinPath（离线）。
Item {
    id: root
    property var backend: null
    property string name: ""
    property bool online: false
    property string skinSource: ""       // 已渲染头部图（优先）
    property string rawSkinSource: ""    // 整张皮肤（兜底：自己裁脸，会缺头发/角）
    property int status: 0          // 0 正常 / 1 需注意（离线、令牌异常）
    signal clicked()

    // ── 键盘（统一契约四件套）──
    // 本控件没有 dimmed/busy 这类内部灰态：name 为空时显示"登录"仍可点（点了开账户页），
    // status 只改状态点颜色、不改可点性。唯一"不可用"通道是 Qt 的 Item.enabled。
    activeFocusOnTab: root.enabled

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 14

    Rectangle {
        anchors.fill: parent
        radius: 99
        color: hover.containsMouse ? "#1dffffff" : "#0effffff"
        border.width: 1
        border.color: "#12ffffff"
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        // 方形头像：SMinecraftHead 会自己判断"整张皮肤 → 裁脸"还是"头图 → 直接用"
        SMinecraftHead {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            size: 22
            rawSource: root.rawSkinSource
            source: root.skinSource
            fallbackText: root.name.length > 0 ? root.name : "?"
        }
        Text {
            text: root.name.length > 0 ? root.name : qsTr("登录")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
        Rectangle {
            width: 6; height: 6; radius: 3
            color: root.status === 0 ? Theme.ok : Theme.warn
        }
        SIcon { name: "chevron-down"; size: 12; color: Theme.fg3 }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // 鼠标按下也拿焦点：键盘与鼠标共用同一套焦点状态
        onPressed: { Theme.keyboardNav = false; root.forceActiveFocus() }
        onClicked: root.clicked()
    }

    // 键盘激活：与鼠标**同一个入口**（root.clicked() → 展开账户）
    Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            e.accepted = true
            if (e.isAutoRepeat || !root.enabled) return
            root.clicked()
        }
    }

    // 焦点环：胶囊形，圆角跟随自身背景层（99），只锚定 + 负 margin，不占布局
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.focusRingGap
        radius: 99 + Theme.focusRingGap
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        visible: root.activeFocus && Theme.keyboardNav
        z: 999
        antialiasing: true
    }
}
