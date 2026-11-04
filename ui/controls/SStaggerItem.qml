// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 列表逐条入场：内容包进来，play 置 true 后按 index 依次淡入 + 轻微上浮。
// 用法：SStaggerItem { index: model.index; play: listReady } 里面放真正的内容。
// 总时长 = index*step + durSlow，调用方控制行数即可（超过 8 行建议关掉，避免拖沓）。
Item {
    id: root
    property int index: 0
    property bool play: false
    property int step: Theme.staggerStep
    property int duration: Theme.durSlow
    property int rise: 10
    default property alias content: holder.data

    Item {
        id: holder
        anchors.fill: parent
    }

    opacity: shown ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: root.duration; easing.type: Theme.easeEnter }
    }

    property bool shown: false
    Timer {
        interval: Math.max(0, root.index) * root.step
        running: root.play
        onTriggered: root.shown = true
    }
    onPlayChanged: if (!root.play) root.shown = false

    transform: Translate {
        y: root.shown ? 0 : root.rise
        Behavior on y { NumberAnimation { duration: root.duration; easing.type: Theme.easeEnter } }
    }
}
