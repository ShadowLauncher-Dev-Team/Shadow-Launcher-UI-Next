// SPDX-License-Identifier: AGPL-3.0-or-later
// 背景图层：图片 + 取景（缩放 / 中心点）。启动页与外观页预览共用同一套公式，
// 保证"预览看到的 = 启动页实际显示的"。
//
// 取景模型：
//   coverScale = max(框宽/图宽, 框高/图高)   —— 先让图片恰好铺满
//   drawW/H    = 图原生尺寸 × coverScale × zoom
//   x/y        = (框尺寸 - 绘制尺寸) × cropX/cropY   —— crop 0..1 = 取景窗在图片内的位置
//
// interactive = true 时支持：拖动平移、滚轮缩放（1.0–4.0）。
import QtQuick
import ShadowLauncher.Next

Item {
    id: root
    clip: true

    property string source: ""
    property real zoom: 1.0
    property real cropX: 0.5
    property real cropY: 0.5
    property bool interactive: false
    property real maxZoom: 4.0
    // 图片没加载出来时的底色（避免闪白/黑块）
    property color fallbackColor: Theme.bgCard2

    // ── 动图（GIF）──
    // 判据只看扩展名：与后端 importBgFile 的规则一致，不嗅探文件内容。
    // 静态图仍走 Image；动图走 AnimatedImage（Qt 自带，用的就是部署里的 imageformats/qgif.dll）。
    readonly property bool animatedSource: /\.gif$/i.test(root.source)
    // 是否播放。启动页在最小化/切到后台时由上层关掉 —— 动图每帧都要解码，不能一直烧。
    property bool playing: true
    // 已播到第几帧（只用于日志/排查：看不出动画时，先看这个有没有在变）
    property int framesShown: 0

    signal viewChanged(real zoom, real cx, real cy)

    readonly property real natW: root.animatedSource ? anim.implicitWidth : img.imageWidth
    readonly property real natH: root.animatedSource ? anim.implicitHeight : img.imageHeight
    readonly property real coverScale: (natW > 0 && natH > 0 && width > 0 && height > 0)
        ? Math.max(width / natW, height / natH) : 1
    readonly property real drawW: natW * coverScale * Math.max(1.0, root.zoom)
    readonly property real drawH: natH * coverScale * Math.max(1.0, root.zoom)

    Rectangle {
        anchors.fill: parent
        color: root.fallbackColor
    }

    Image {
        id: img
        // 原生尺寸用 implicitWidth/Height：Image 的隐式尺寸就是图片原始像素；
        // sourceSize 在异步加载完成前是 0，首帧会算不出布局。
        readonly property real imageWidth: implicitWidth
        readonly property real imageHeight: implicitHeight
        visible: !root.animatedSource
        // 动图时清空 source：两个加载器同时读同一个文件会白占一份解码内存
        source: root.animatedSource ? "" : root.source
        asynchronous: true
        smooth: true
        // 几何由我们自己算（保持比例），所以这里必须用 Stretch ——
        // 用 Image.Pad 的话 Qt 会按**原始像素尺寸**绘制、忽略我们设的宽高，
        // 默认极光图就变成"放大后裁切"（用户实测报的缩放不对）。
        fillMode: Image.Stretch
        width: Math.max(root.width, root.drawW)
        height: Math.max(root.height, root.drawH)
        x: (root.width - width) * Math.max(0, Math.min(1, root.cropX))
        y: (root.height - height) * Math.max(0, Math.min(1, root.cropY))
    }

    AnimatedImage {
        id: anim
        visible: root.animatedSource
        source: root.animatedSource ? root.source : ""
        // 不整段缓存帧：1080p、上百帧的 GIF 全缓存要几百 MB 内存。
        // 背景动图通常 480p~720p，逐帧解码足够，且内存恒定。
        cache: false
        paused: !root.playing
        smooth: true
        // 与 Image 同样必须用 Stretch：几何是我们自己算的（见文件头公式）
        fillMode: Image.Stretch
        width: img.width
        height: img.height
        x: img.x
        y: img.y
        onFrameChanged: {
            root.framesShown++
            // 只在开头和每隔一段时间记一笔：动图每秒十几帧，逐帧打日志会把日志淹掉
            if (root.framesShown === 1 || root.framesShown % 300 === 1) {
                console.info("[背景] 动图帧", root.framesShown, "共", anim.frameCount, "帧，播放中=" + root.playing)
            }
        }
    }

    // ── 交互：拖动平移 + 滚轮缩放 ──
    // 正在拖动（供外层 Flickable 判断是否让路：拖图时页面绝不能被带着滚）
    readonly property bool dragActive: dragArea.pressed

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.interactive
        // ── 关键：阻止父级 Flickable 抢走拖拽 ──
        // 没有这行时，鼠标拖到图片/取景框边缘后再继续拖，Flickable 会把这次拖动
        // 判成「翻页手势」并抢走 grab，表现就是整个设置页跟着上下滚动（用户实测）。
        preventStealing: root.interactive
        cursorShape: root.interactive ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                      : Qt.ArrowCursor
        property real lastX: 0
        property real lastY: 0

        // 拖动 = 图片跟着手走；可移动范围只有图片超出框的那部分，
        // 换算成 crop 的增量（crop 0 = 取景窗贴左/上，1 = 贴右/下）。
        onPressed: (mouse) => {
            lastX = mouse.x
            lastY = mouse.y
        }
        onPositionChanged: (mouse) => {
            if (!pressed) return
            const rangeX = root.width - img.width    // 负数：图片比框宽
            const rangeY = root.height - img.height
            const dx = mouse.x - lastX
            const dy = mouse.y - lastY
            lastX = mouse.x
            lastY = mouse.y
            let nx = root.cropX
            let ny = root.cropY
            if (rangeX < -0.5) nx = Math.max(0, Math.min(1, root.cropX + dx / rangeX))
            if (rangeY < -0.5) ny = Math.max(0, Math.min(1, root.cropY + dy / rangeY))
            if (Math.abs(nx - root.cropX) > 0.0005 || Math.abs(ny - root.cropY) > 0.0005) {
                root.cropX = nx
                root.cropY = ny
                root.viewChanged(root.zoom, nx, ny)
            }
        }
    }

    WheelHandler {
        enabled: root.interactive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            // 只有按住 Ctrl 才缩放取景；否则把滚轮让给外层 Flickable 正常滚页面。
            // （之前无修饰键也缩放，导致"鼠标停在预览上就滚不动设置页"，而缩放条还在下面）
            if (!(event.modifiers & Qt.ControlModifier)) {
                event.accepted = false
                return
            }
            const step = event.angleDelta.y > 0 ? 1.1 : (1 / 1.1)
            const next = Math.max(1.0, Math.min(root.maxZoom, root.zoom * step))
            if (Math.abs(next - root.zoom) < 0.001) {
                // 已经到缩放极限：不吞滚轮，让页面正常滚动（否则在预览上滚不动页面）
                event.accepted = false
                return
            }
            root.zoom = next
            root.viewChanged(next, root.cropX, root.cropY)
        }
    }
}
