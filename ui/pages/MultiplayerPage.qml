// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 联机页（2026-11-07，d3b 方案）
// 结构：顶部标题 + 设备 chip，中间 560 宽居中卡片（四点阶段条 / 标题 / 说明 / 房间码 / 徽章 / 成员行 / 操作）。
// 身份模型：联机认「这台设备」，与 MC 账号无关。
//   deviceName 用户可改（存本地设置，跟设备走）；deviceCode = machine_id 前 4 位，固定，用于区分同名设备。
//   **房间里不允许改名**（backend.canRename 只在该页 Idle 且未入房时为 true）。
Item {
    id: page
    property var toast: null

    readonly property var mp: backend ? backend.multiplayer : null
    readonly property int st: mp ? mp.state : 0
    readonly property int role: mp ? mp.role : 0
    readonly property string code: (mp && mp.roomCode) ? mp.roomCode : ""
    readonly property string devName: (mp && mp.deviceName) ? mp.deviceName : ""
    readonly property string devCode: (mp && mp.deviceCode) ? mp.deviceCode : ""
    readonly property bool canRename: mp ? mp.canRename : false
    readonly property var members: (mp && mp.players) ? mp.players : []

    property string errorText: ""
    property bool errorHostGone: false
    property bool renameOpen: false
    property string renameDraft: ""
    property real enter: 0

    readonly property bool inRoom: role !== 0
    // 错误态：只留错误卡（房间码/成员/徽章都不该出现，否则像"房间还在"）
    readonly property bool isError: errorText !== ""
    readonly property bool busy: st >= 1 && st <= 4

    // 阶段点：0 建房/入网 · 1 找中心 · 2 等开服 · 3 已连通
    readonly property int stage: {
        if (st === 1) return 0
        if (st === 2) return 1
        if (st === 3 || st === 4 || st === 7) return 2
        if (st === 5 || st === 6 || st === 8) return 3
        return -1
    }

    readonly property string hostName: {
        for (var i = 0; i < members.length; ++i) {
            if (String(members[i].kind) === "HOST")
                return String(members[i].name || "房主")
        }
        return "房主"
    }

    readonly property string titleText: {
        if (errorText !== "")
            return errorHostGone ? "房主已离开" : "出错了"
        switch (st) {
        case 1: return "正在创建房间…"
        case 2: return "正在加入联机网络…"
        case 3: return "正在查找联机中心…"
        case 4: return "正在连接联机中心…"
        case 7: return "房间已建好 · 还差游戏里开服"
        case 8: return "正在验证 MC 连接…"
        case 5: return role === 1 ? "房间已连通" : ("已加入 · " + page.hostName + " 的房间")
        case 6: return "房间在线 · " + members.length + "/" + (mp ? mp.maxPlayers : 5)
        default: return "和朋友一起玩"
        }
    }

    readonly property string subText: {
        if (errorText !== "") {
            if (errorHostGone)
                return "房间已自动退出。可以重新加入，或者自己开一间。"
            if (errorText.indexOf("房间码无效") >= 0)
                return "少了位数，或者校验位不对。连续 3 次失败会冷却 60 秒。"
            return errorText
        }
        switch (st) {
        case 1: return "生成房间码并启动隧道，通常 2–5 秒。"
        case 2: return "正在建立到房主的隧道。"
        case 3: return "房主刚创建房间时可能需要多等几秒。"
        case 4: return "正在连到房主的联机中心…"
        case 7: return "请打开游戏，进入单人世界后按 Esc 选「对局域网开放」。开好后会自动识别，不用填端口。"
        case 8: return "最多 8 次尝试；不过也会放行，先进游戏再看。"
        case 5: return role === 1 ? "朋友现在可以在游戏里进去了。" : "打开 Minecraft 的「多人游戏」，进「局域网世界」即可。"
        case 6: return "朋友在「多人游戏」的「局域网世界」里能直接看到，无需输入 IP。"
        default: return "房主在自己游戏里「对局域网开放」，其他人凭房间码加入。不用公网 IP、不用开端口，最多 5 人。"
        }
    }

    readonly property color accentSoft: "#14213a"

    function avatarColor(id, alpha) {
        var s = String(id || "x")
        var h = 0
        for (var i = 0; i < s.length; ++i)
            h = (h * 31 + s.charCodeAt(i)) % 360
        return Qt.hsla(h / 360, 0.45, 0.62, alpha)
    }
    function avatarChar(name) {
        var t = String(name || "").trim()
        return t.length > 0 ? t.charAt(0) : "?"
    }
    function isMe(p) {
        return String(p.machine_id || "").slice(0, 4).toUpperCase() === page.devCode
    }
    function latencyText(p) {
        var v = Number(p.latency)
        return (isNaN(v) || v < 0) ? "—" : (v + "ms")
    }
    function latencyColor(p) {
        var v = Number(p.latency)
        if (isNaN(v) || v < 0) return Theme.fg3
        return v < 60 ? Theme.ok : (v < 150 ? Theme.warn : Theme.danger)
    }
    function difficultyText(d) {
        switch (d) {
        case 1: return "直连"
        case 2: return "简单"
        case 3: return "中等"
        case 4: return "困难"
        default: return ""
        }
    }
    function difficultyColor(d) {
        switch (d) {
        case 1: return Theme.ok
        case 2: return Theme.ok
        case 3: return Theme.warn
        case 4: return Theme.danger
        default: return Theme.fg3
        }
    }
    function doJoin() {
        var t = joinInput.text.trim()
        if (t.length === 0) {
            if (page.toast) page.toast.show("先粘贴房间码")
            return
        }
        if (page.mp) page.mp.joinRoom(t)
    }
    function openRename() {
        if (!page.canRename) {
            if (page.toast) page.toast.show("房间里不能改名，请先离开房间")
            return
        }
        page.renameDraft = page.devName
        page.renameOpen = true
        renameInput.text = page.renameDraft
        renameInput.forceActiveFocus()
    }
    function saveRename() {
        if (!page.mp) return
        if (page.mp.setDeviceName(renameInput.text)) {
            page.renameOpen = false
            if (page.toast) page.toast.show("已保存")
        }
    }

    onVisibleChanged: if (visible) enterAnim.restart()
    Component.onCompleted: if (visible) enterAnim.restart()

    NumberAnimation {
        id: enterAnim
        target: page
        property: "enter"
        from: 0.6
        to: 1.0
        duration: Theme.durPage
        easing.type: Theme.easeEnter
    }

    Connections {
        target: page.mp
        ignoreUnknownSignals: true
        function onErrorOccurred(msg) {
            page.errorHostGone = String(msg).indexOf("房主已离开") >= 0
            page.errorText = String(msg)
            errorTimer.restart()
            if (page.toast) page.toast.show(msg)
        }
        function onMinecraftPortReady(port) {
            if (page.toast) page.toast.show("游戏端口已就绪：" + port)
        }
        function onStateChanged() {
            if (page.st === 0 && page.role === 0)
                page.renameOpen = false
        }
    }

    Timer {
        id: errorTimer
        interval: 6000
        onTriggered: page.errorText = ""
    }

    // ── 标题 ──
    Text {
        id: pageTitle
        anchors.left: parent.left
        anchors.leftMargin: Theme.padL
        anchors.top: parent.top
        anchors.topMargin: 20
        text: "联机"
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 19
        font.bold: true
        opacity: page.enter
    }

    // ── 设备 chip（点开改名）──
    Rectangle {
        id: devChip
        anchors.right: parent.right
        anchors.rightMargin: Theme.padR
        anchors.verticalCenter: pageTitle.verticalCenter
        width: chipRow.implicitWidth + 22
        height: 26
        radius: 7
        color: "transparent"
        border.width: 1
        border.color: chipHover.containsMouse ? Theme.accent : Theme.line2
        opacity: page.enter

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 7
            Rectangle {
                width: 6; height: 6; radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: page.inRoom ? Theme.ok : Theme.fg3
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.devName.length > 0 ? page.devName : "…"
                color: Theme.fg2
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.devCode
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }
        MouseArea {
            id: chipHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.openRename()
        }
    }

    // ── 居中卡片 ──
    Item {
        id: stageWrap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: pageTitle.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.padL
        anchors.rightMargin: Theme.padL
        anchors.topMargin: 16
        opacity: page.enter

        Rectangle {
            id: card
            width: Math.min(560, stageWrap.width)
            height: body.implicitHeight + 44
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.max(0, (stageWrap.height - height) / 2 - 16)
            radius: 14
            color: Theme.sidebar
            border.width: 1
            border.color: page.errorText !== "" ? "#5b2a2a" : Theme.line2

            Behavior on height { NumberAnimation { duration: Theme.durBase; easing.type: Theme.easeStandard } }
            Behavior on border.color { ColorAnimation { duration: Theme.durBase } }

            Column {
                id: body
                x: 22
                y: 22
                width: parent.width - 44
                spacing: 13

                // 四点阶段条
                Row {
                    width: parent.width
                    spacing: 6
                    visible: !page.isError
                    Repeater {
                        model: 4
                        Rectangle {
                            height: 3
                            radius: 2
                            width: (body.width - 18) / 4
                            color: page.stage < 0 ? "#181d26"
                                 : (index < page.stage ? Qt.rgba(0.23, 0.51, 0.96, 0.45)
                                    : (index === page.stage ? Theme.accent : "#181d26"))
                            Behavior on color { ColorAnimation { duration: Theme.durBase } }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: page.titleText
                    color: page.errorText !== "" ? "#fca5a5" : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 19
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    text: page.subText
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    lineHeight: 1.6
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                }

                // 进度条（仅前置阶段）
                Rectangle {
                    width: parent.width
                    height: 3
                    radius: 2
                    color: "#151a22"
                    visible: page.busy || page.st === 8
                    clip: true
                    Rectangle {
                        id: sweep
                        width: 0.38 * parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                        opacity: 0.9
                        x: 0
                        SequentialAnimation on x {
                            running: page.busy || page.st === 8
                            loops: Animation.Infinite
                            NumberAnimation { from: -0.4 * sweep.parent.width; to: sweep.parent.width; duration: Theme.durLoop; easing.type: Theme.easeLoop }
                        }
                    }
                }

                // 房间码
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: page.code
                    color: page.errorText !== "" ? "#4a5361" : "#a9c8ff"
                    font.family: Theme.fontFamily
                    font.pixelSize: page.st === 0 ? 19 : 26
                    font.bold: true
                    font.letterSpacing: 2
                    visible: page.code.length > 0 && !page.isError
                }

                // 徽章行
                Item {
                    width: parent.width
                    height: 20
                    visible: page.inRoom && page.st >= 5 && !page.isError
                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        Rectangle {
                            height: 20; radius: 5; width: roleTxt.implicitWidth + 14
                            color: page.role === 1 ? Qt.rgba(0.96, 0.62, 0.04, 0.10) : Qt.rgba(0.29, 0.87, 0.50, 0.10)
                            border.width: 1
                            border.color: page.role === 1 ? Qt.rgba(0.96, 0.62, 0.04, 0.35) : Qt.rgba(0.29, 0.87, 0.50, 0.30)
                            Text {
                                id: roleTxt
                                anchors.centerIn: parent
                                text: page.role === 1 ? "房主" : "访客"
                                color: page.role === 1 ? Theme.warn : Theme.ok
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                        Rectangle {
                            height: 20; radius: 5; width: diffTxt.implicitWidth + 14
                            visible: diffTxt.text.length > 0
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                id: diffTxt
                                anchors.centerIn: parent
                                text: page.difficultyText(page.mp ? page.mp.connectionDifficulty : 0)
                                color: page.difficultyColor(page.mp ? page.mp.connectionDifficulty : 0)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: page.st === 7
                            text: "2 分钟内没开服会自动关闭"
                            color: Theme.warn
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                // 空闲：身份行
                Rectangle {
                    width: parent.width
                    height: 38
                    radius: 9
                    color: "#0d1016"
                    border.width: 1
                    border.color: Theme.line2
                    visible: page.st === 0 && page.errorText === ""

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        Text {
                            id: idLabel
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "这台设备叫"
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            id: idName
                            anchors.left: idLabel.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.devName
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            id: idCode
                            anchors.left: idName.right
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.devCode
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                        Text {
                            id: idEdit
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "修改"
                            color: editHover.containsMouse ? Theme.accent : "#7fb0ff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            MouseArea {
                                id: editHover
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.openRename()
                            }
                        }
                    }
                }

                // 空闲：加入房间输入
                Row {
                    width: parent.width
                    spacing: 8
                    visible: page.st === 0 && page.errorText === ""

                    Rectangle {
                        width: parent.width - 86
                        height: 36
                        radius: 9
                        color: "#0d1016"
                        border.width: 1
                        border.color: joinInput.activeFocus ? Theme.accent : Theme.line2
                        Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

                        TextInput {
                            id: joinInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#a9c8ff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            selectionColor: Theme.accent
                            selectedTextColor: "#ffffff"
                            clip: true
                            selectByMouse: true
                            onAccepted: page.doJoin()
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: joinInput.text.length === 0
                                text: "粘贴房间码  U/0000-0000-0000-0000"
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                        }
                    }
                    SButton {
                        width: 78
                        height: 36
                        kind: 1
                        text: "加入"
                        onClicked: page.doJoin()
                    }
                }

                // 成员列表
                Column {
                    width: parent.width
                    spacing: 6
                    visible: page.inRoom && !page.isError

                    Item {
                        width: parent.width
                        height: 18
                        Text {
                            anchors.left: parent.left
                            anchors.baseline: undefined
                            anchors.verticalCenter: parent.verticalCenter
                            text: "在房间里"
                            color: Theme.fg2
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.members.length + " / " + (page.mp ? page.mp.maxPlayers : 5)
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }

                    Repeater {
                        model: page.members
                        delegate: Rectangle {
                            width: parent.width
                            height: 44
                            radius: 9
                            color: page.isMe(modelData) ? page.accentSoft : "#0e1117"
                            border.width: 1
                            border.color: page.isMe(modelData) ? Qt.rgba(0.23, 0.51, 0.96, 0.42) : Theme.line2

                            Rectangle {
                                id: av
                                width: 26; height: 26; radius: 7
                                anchors.left: parent.left
                                anchors.leftMargin: 11
                                anchors.verticalCenter: parent.verticalCenter
                                color: page.avatarColor(modelData.machine_id, 0.16)
                                border.width: 1
                                border.color: page.avatarColor(modelData.machine_id, 0.42)
                                Text {
                                    anchors.centerIn: parent
                                    text: page.avatarChar(modelData.name)
                                    color: page.avatarColor(modelData.machine_id, 0.95)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                }
                            }
                            Text {
                                id: memberName
                                anchors.left: av.right
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.name || "?")
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                            }
                            Text {
                                id: memberTag
                                anchors.left: memberName.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    var k = String(modelData.kind || "")
                                    var base = (k === "HOST") ? "房主" : "访客"
                                    if (page.isMe(modelData)) base += " · 这台设备"
                                    var h = String(modelData.hostname || "")
                                    return base
                                }
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.latencyText(modelData)
                                color: page.latencyColor(modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 38
                        radius: 9
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.line2
                        visible: page.members.length < (page.mp ? page.mp.maxPlayers : 5)
                        Text {
                            anchors.centerIn: parent
                            text: "还有 " + ((page.mp ? page.mp.maxPlayers : 5) - page.members.length) + " 个空位"
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                // 操作
                Column {
                    width: parent.width
                    spacing: 8

                    SButton {
                        width: parent.width
                        height: 40
                        visible: page.st === 0 && page.errorText === ""
                        text: "创建房间"
                        onClicked: if (page.mp) page.mp.createRoom()
                    }

                    SButton {
                        width: parent.width
                        height: 36
                        kind: 1
                        visible: page.busy || page.st === 8
                        text: "取消"
                        onClicked: if (page.mp) page.mp.leaveRoom()
                    }

                    SButton {
                        width: parent.width
                        height: 40
                        visible: (page.st === 7 || page.st === 6 || page.st === 5) && page.role === 1
                        text: "复制房间码"
                        onClicked: {
                            if (page.mp) page.mp.copyRoomCode()
                            if (page.toast) page.toast.show("房间码已复制")
                        }
                    }

                    SButton {
                        width: parent.width
                        height: 36
                        kind: 1
                        visible: (page.st === 7 || page.st === 6 || page.st === 5) && page.role === 1
                        text: "关闭房间"
                        onClicked: if (page.mp) page.mp.leaveRoom()
                    }

                    SButton {
                        width: parent.width
                        height: 40
                        kind: 1
                        visible: page.role === 2 && page.st >= 5
                        text: "离开房间"
                        onClicked: if (page.mp) page.mp.leaveRoom()
                    }

                    SButton {
                        width: parent.width
                        height: 40
                        visible: page.errorText !== ""
                        text: (page.errorText.indexOf("房间码无效") >= 0 || page.errorText.indexOf("过于频繁") >= 0)
                              ? "重新输入" : "知道了"
                        onClicked: page.errorText = ""
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.st === 0 && page.errorText === ""
                    text: "联机身份跟着「这台设备」走，与 MC 账号无关。"
                    color: "#3f4753"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ── 改昵称浮层 ──
    Item {
        id: renameLayer
        anchors.fill: parent
        visible: page.renameOpen
        z: 50

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
            opacity: 0.55
            MouseArea { anchors.fill: parent; onClicked: page.renameOpen = false }
        }

        Rectangle {
            width: 420
            height: renameCol.implicitHeight + 40
            anchors.centerIn: parent
            radius: 14
            color: Theme.sidebar
            border.width: 1
            border.color: Theme.line2

            Column {
                id: renameCol
                x: 20
                y: 20
                width: parent.width - 40
                spacing: 12

                Text {
                    text: "这台设备的昵称"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: "别人在成员列表里看到的就是它。只改这块牌子，不改设备、不改 MC 账号。"
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    lineHeight: 1.6
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 10
                    color: "#0d1016"
                    border.width: 1
                    border.color: renameInput.activeFocus ? Theme.accent : Theme.line2
                    TextInput {
                        id: renameInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        selectionColor: Theme.accent
                        selectedTextColor: "#ffffff"
                        maximumLength: 16
                        selectByMouse: true
                        onAccepted: page.saveRename()
                    }
                }
                Item {
                    width: parent.width
                    height: 16
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "设备码 " + page.devCode
                        color: Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "固定不变，用于区分同名设备"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
                SButton {
                    width: parent.width
                    height: 40
                    text: "保存"
                    onClicked: page.saveRename()
                }
                SButton {
                    width: parent.width
                    height: 34
                    kind: 1
                    text: "取消"
                    onClicked: page.renameOpen = false
                }
            }
        }
    }
}
