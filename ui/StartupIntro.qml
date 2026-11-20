// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

// 启动动画（方案 A「影子落定」）—— 加载完成后的那一半。
//
// 分工：
//   · QML 加载那 1.4~1.8s 主线程是同步堵死的，动画跑不动 → 那一段由 C++ 的
//     SplashWindow 顶住（静止画面：同一个字标 + 同一圈光晕）。
//   · 首帧真正上屏后（C++ 置 firstFrame=true），这里才开演。
//   所以第 0 帧必须和封面窗那张静止画面长得一样，交接才看不出来。
//
// 时序（总 800ms）：
//   0-120    停留（让眼睛认出这是什么）
//   120-320  光晕收到 0："影子"消失，字变实
//   320-600  44px → 14px，同时左移到侧栏字标原位（22,16）
//   600-800  底板淡出，界面显形；字标同一时间交给真正的侧栏字标
Item {
    id: intro

    property bool enabled: false
    property bool firstFrame: false
    property Window hostWindow: null

    property real halo: 1         // 1 = 还是影子，0 = 实心字
    property real shrink: 0       // 0 = 舞台中央，1 = 侧栏原位
    property real veil: 1         // 1 = 整块盖住，0 = 完全让开
    property real labelFade: 1
    property bool playing: false

    anchors.fill: parent
    visible: enabled && (playing || veil > 0.001)
    z: 4000

    function start() {
        if (!enabled) return
        intro.halo = 1
        intro.shrink = 0
        intro.veil = 1
        intro.labelFade = 1
        intro.playing = true
        boot.restart()
    }

    // 底板：颜色和窗口底色、封面窗底色是同一个值 —— 启动那一刻看不出有东西在切换
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: intro.veil
    }

    // 字标：**一个节点**。交接靠的是它最后停在 SideBar 里 SHADOW 的坐标上，
    // 而不是"大字淡出 + 小字淡入"两个元素。
    Item {
        id: word
        width: label.implicitWidth
        height: label.implicitHeight
        x: (intro.width - width) / 2 * (1 - intro.shrink) + 22 * intro.shrink
        y: (intro.height - height) / 2 * (1 - intro.shrink) + 16 * intro.shrink
        opacity: intro.labelFade

        // 光晕层：包在 Loader 里，加载失败只是没有光晕
        Loader {
            anchors.fill: parent
            active: intro.halo > 0.01
            sourceComponent: haloComp
        }

        Text {
            id: label
            text: "SHADOW"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.weight: Font.Bold
            font.pixelSize: 44 + (14 - 44) * intro.shrink
            font.letterSpacing: 2.2
            // 必须和 C++ 那块封面窗（QPainter 画的）用同一种光栅化，否则交接时字形会变
            renderType: Text.NativeRendering
        }
    }

    Component {
        id: haloComp
        StartupIntroHalo {
            px: 44 + (14 - 44) * intro.shrink
            strength: intro.halo
        }
    }

    // 时长一律走 Theme 的动效 token（ui 合同检查会拦裸数字，这也让启动动画和其他界面同一个节奏感）
    SequentialAnimation {
        id: boot
        PauseAnimation { duration: Theme.durFast }
        NumberAnimation {
            target: intro; property: "halo"; from: 1; to: 0
            duration: Theme.durBase; easing.type: Theme.easeStandard
        }
        NumberAnimation {
            target: intro; property: "shrink"; from: 0; to: 1
            duration: Theme.durPage; easing.type: Theme.easeEnter
        }
        ParallelAnimation {
            NumberAnimation {
                target: intro; property: "veil"; from: 1; to: 0
                duration: Theme.durBase; easing.type: Theme.easeStandard
            }
            NumberAnimation {
                target: intro; property: "labelFade"; from: 1; to: 0
                duration: Theme.durBase; easing.type: Theme.easeStandard
            }
        }
        ScriptAction {
            script: {
                var p = word.mapToItem(null, 0, 0)
                console.info("[启动动画] 结尾字标 scene", p.x, p.y, word.width, word.height)
                intro.playing = false
            }
        }
    }

    // 兜底：万一 firstFrame 一直没来（C++ 那边属性名改了、加载顺序变了），
    // 不能把整块屏幕永久盖住 —— 4 秒后不管有没有信号都开演。
    Timer {
        interval: 4000
        running: intro.enabled && !intro.playing && intro.veil > 0.001
        repeat: false
        onTriggered: intro.start()
    }

    onFirstFrameChanged: {
        if (firstFrame && enabled && !intro.playing) intro.start()
    }
    Component.onCompleted: {
        if (firstFrame && enabled) intro.start()
    }
}
