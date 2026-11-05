// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import ShadowLauncher.Next

// 资源详情页（A 方案三栏）：封面列 / 版本与文件表 + 简介 / 粘性安装面板
// 后端能力边界（docs/res-backend-report.md）：
//   · 没有项目正文/图集/作者 → 只有一句话 desc
//   · 没有"已安装/可更新"事实源 → 安装态只有 未安装 / 下载中 / 失败
//   · 数据包没有安装接口 → 只能下载到本地，手动放 world/datapacks/
Item {
    id: page
    property string kind: "mod"
    property var item: ({})
    property var toast: null
    readonly property var b: (typeof backend !== "undefined") ? backend : null

    property var versions: []
    property bool loading: false
    property int picked: 0
    property string status: ""

    signal back()

    readonly property string slug: item.slug || ""
    readonly property bool isCf: /^\d+$/.test(slug)
    readonly property string iconSrc: item.icon || ""
    readonly property string title: item.zh && item.zh.length > 0 ? item.zh : (item.title || "")
    readonly property string subTitle: item.zh && item.zh.length > 0 ? (item.title || "") : ""

    // 等一帧再拉：item 与 kind 由宿主连续赋值，立刻拉会拿到中间态
    onItemChanged: Qt.callLater(page.loadVersions)
    Component.onCompleted: if (slug.length > 0) Qt.callLater(page.loadVersions)

    function setLoading(on) { page.loading = on }

    function loadVersions() {
        page.status = ""
        if (!page.b || slug.length === 0) return
        try {
        page.versions = []
        page.picked = 0
        if (page.kind === "datapack") { page.loading = false; return }   // 无版本接口
        page.setLoading(true)
        if (page.kind === "mod") {
            if (page.isCf) page.b.fetchModVersionsCf(slug); else page.b.fetchModVersions([slug])
        } else if (page.kind === "shader") {
            if (page.isCf) page.b.fetchShaderVersionsCf(slug); else page.b.fetchShaderVersions([slug])
        } else if (page.kind === "resourcepack") {
            if (page.isCf) page.b.fetchResourcepackVersionsCf(slug); else page.b.fetchResourcepackVersions([slug])
        } else if (page.kind === "modpack") {
            page.b.fetchModpackVersions(slug)
        }
        } catch (e) {
            page.status = "调用版本接口失败：" + e
            page.setLoading(false)
        }
    }

    function applyVersions(s, vers, details) {
        if (s !== page.slug) return
        var out = []
        var list = vers || []
        for (var i = 0; i < list.length; ++i) {
            var d = details[list[i]] || ({})
            out.push({
                version: list[i],
                date: d.date_published || d.date || "",
                url: d.url || "",
                filename: d.filename || "",
                sha1: d.sha1 || "",
                size: d.size || 0,
                downloads: d.downloads || 0,
                gameVersions: d.game_version || page.joinList(d.game_versions),
                loaders: page.joinList(d.loaders)
            })
        }
        page.versions = out
        page.setLoading(false)
    }

    Connections {
        target: page.b
        enabled: page.b !== null
        function onModVersionsPartial(s, vers, details) { if (page.kind === "mod" || page.kind === "modpack") page.applyVersions(s, vers, details) }
        // 兜底：全量信号先到（只有版本号，没有 url/size）时也要把版本表填出来
        function onModVersionsLoaded(map) {
            if (page.kind !== "mod" && page.kind !== "modpack") return
            if (page.versions.length > 0) return
            var arr = map ? map[page.slug] : null
            if (!arr || arr.length === 0) return
            var out = []
            for (var i = 0; i < arr.length; ++i)
                out.push({ version: arr[i], date: "", url: "", filename: arr[i], sha1: "",
                           size: 0, downloads: 0, gameVersions: "", loaders: "" })
            page.versions = out
            page.setLoading(false)
        }
        function onShaderVersionsPartial(s, vers, details) { if (page.kind === "shader") page.applyVersions(s, vers, details) }
        function onResourcepackVersionsPartial(s, vers, details) { if (page.kind === "resourcepack") page.applyVersions(s, vers, details) }
    }

    function installDir() {
        var base = (page.b && page.b.gameDir) ? page.b.gameDir : ""
        if (page.kind === "mod") return base + "/mods"
        if (page.kind === "shader") return base + "/shaderpacks"
        if (page.kind === "resourcepack") return base + "/resourcepacks"
        if (page.kind === "modpack") return base + "/downloads"
        return base + "/datapacks"
    }

    function install() {
        var v = page.versions[page.picked] || null
        if (!v || !v.url) { page.status = "没有可下载的文件"; return }
        if (!page.b) return
        if (page.kind === "datapack") { page.status = "数据包没有安装接口：下载后请手动放入 world/datapacks/"; return }
        if (page.kind === "modpack") {
            page.b.downloadModpack(v.url, v.filename || (page.slug + ".mrpack"), v.size || 0, v.sha1 || "",
                                    page.title + " " + v.version, page.title, page.iconSrc)
            page.status = "已加入下载队列：整合包会下载到 downloads/ 后自动导入"
            return
        }
        var path = page.installDir() + "/" + (v.filename || (page.slug + ".jar"))
        page.b.downloadModFile(v.url, path, v.filename || page.title, v.size || 0, v.sha1 || "")
        page.status = "已开始下载到 " + page.installDir()
        if (page.toast) page.toast.show("开始下载 " + page.title)
    }

    function linkFor() {
        try {
            var l = page.b.resolveProjectLinks(page.title, page.slug, page.kind)
            return l && l.mrUrl ? l.mrUrl : (l && l.cfUrl ? l.cfUrl : "")
        } catch (e) { return "" }
    }

    // QStringList / QVariantList / JS array 通吃（后端 loaders 是 QStringList，
    // 直接 Array.isArray 判断会落空，取值会退化成单字符）
    function joinList(v) {
        if (!v) return ""
        if (typeof v === "string") return v
        if (Array.isArray(v)) return v.join(", ")
        if (typeof v.length === "number") {
            var out = []
            for (var i = 0; i < v.length; ++i) out.push(String(v[i]))
            return out.join(", ")
        }
        return String(v)
    }

    function fmtSize(n) {
        if (!n || n <= 0) return "—"
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
        if (n >= 1024) return (n / 1024).toFixed(0) + " KB"
        return n + " B"
    }
    function fmtDl(n) {
        if (n >= 100000000) return (n / 100000000).toFixed(1) + " 亿"
        if (n >= 10000) return (n / 10000).toFixed(0) + " 万"
        return (n || 0).toString()
    }

    // 不透明底色：详情页是覆盖层，下面还压着资源库网格，不铺底色会两层文字叠在一起
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        z: -1
    }

    // ── 顶部返回条 ──
    Row {
        id: backBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 44
        spacing: 8

        Rectangle {
            width: backLabel.width + 20; height: 28
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.rSm
            color: backHover.containsMouse ? "#141922" : "transparent"
            border.width: 1; border.color: Theme.line2
            Text {
                id: backLabel
                anchors.centerIn: parent
                text: "返回列表"
                color: Theme.fg2
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            MouseArea {
                id: backHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.back()
            }
        }
        Item { width: 1; height: 1 }
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: backBar.bottom
        anchors.bottom: parent.bottom
        spacing: 16

        // ── 左：封面列 ──
        ColumnLayout {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 96; Layout.preferredHeight: 96
                radius: Theme.rMd
                color: "#12161c"
                clip: true
                Image {
                    anchors.fill: parent
                    source: page.iconSrc
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Text {
                Layout.fillWidth: true
                text: page.title
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.weight: Font.Bold
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: page.subTitle.length > 0
                text: page.subTitle
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            Text {
                text: page.item.source === "CurseForge" ? "CurseForge" : "Modrinth"
                color: page.item.source === "CurseForge" ? Theme.warn : Theme.ok
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: Theme.rSm
                color: copyHover.containsMouse ? "#141922" : "transparent"
                border.width: 1; border.color: Theme.line2
                Text {
                    anchors.centerIn: parent
                    text: "复制链接"
                    color: Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                MouseArea {
                    id: copyHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var l = page.linkFor()
                        if (l.length > 0 && page.toast) page.toast.show("链接：" + l)
                        else if (page.toast) page.toast.show("没有可用的项目链接")
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ── 中：简介 + 版本与文件表 ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true

            Text {
                Layout.fillWidth: true
                text: page.item.desc && page.item.desc.length > 0 ? page.item.desc : "（后端只有一句话简介）"
                color: Theme.fg2
                font.family: Theme.fontFamily
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [
                        { l: "下载量", v: page.fmtDl(page.item.downloads) },
                        { l: "版本数", v: page.versions.length.toString() },
                        { l: "最近更新", v: page.item.dateModified && page.item.dateModified.length >= 10 ? page.item.dateModified.substring(0, 10) : "—" }
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        radius: Theme.rSm
                        color: "#0b0e13"
                        border.width: 1; border.color: Theme.line
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 0
                            Text { text: modelData.l; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 10 }
                            Text { text: modelData.v; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.DemiBold }
                        }
                    }
                }
            }

            Row {
                Layout.fillWidth: true
                height: 26
                spacing: 0
                Text { width: parent.width * 0.35; text: "文件"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                Text { width: parent.width * 0.15; text: "游戏版本"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                Text { width: parent.width * 0.15; text: "加载器"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                Text { width: parent.width * 0.17; text: "发布时间"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                Text { width: parent.width * 0.15; text: "大小"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: page.versions
                spacing: 2
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 34
                    radius: Theme.rSm
                    color: page.picked === index ? "#141c28" : (rowHover.containsMouse ? "#0f141b" : "transparent")
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        Text { width: parent.width * 0.35; anchors.verticalCenter: parent.verticalCenter; text: modelData.filename || modelData.version; color: page.picked === index ? Theme.fg : Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: 11; elide: Text.ElideMiddle; clip: true }
                        Text { width: parent.width * 0.15; anchors.verticalCenter: parent.verticalCenter; text: modelData.gameVersions.length > 0 ? modelData.gameVersions : "—"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11; elide: Text.ElideRight; clip: true }
                        Text { width: parent.width * 0.15; anchors.verticalCenter: parent.verticalCenter; text: modelData.loaders.length > 0 ? modelData.loaders : "—"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11; elide: Text.ElideRight; clip: true }
                        Text { width: parent.width * 0.17; anchors.verticalCenter: parent.verticalCenter; text: modelData.date.length > 0 ? modelData.date : "—"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11; elide: Text.ElideRight; clip: true }
                        Text { width: parent.width * 0.15; anchors.verticalCenter: parent.verticalCenter; text: page.fmtSize(modelData.size); color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11 }
                    }
                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.picked = index
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: page.loading
                text: "正在加载版本列表…"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                Layout.fillWidth: true
                visible: !page.loading && page.versions.length === 0 && page.kind !== "datapack"
                text: "没有取到版本列表（可能网络或镜像无响应）"
                color: Theme.warn
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Text {
                Layout.fillWidth: true
                visible: page.kind === "datapack"
                text: "数据包没有版本接口：只能下载到本地，手动放入 world/datapacks/"
                color: Theme.warn
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }

        // ── 右：安装面板 ──
        Rectangle {
            Layout.preferredWidth: 280
            Layout.fillHeight: true
            radius: Theme.rMd
            color: "#0b0e13"
            border.width: 1; border.color: Theme.line

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text { text: "安装"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text {
                    text: page.versions.length > 0 ? ("已选：" + (page.versions[page.picked] ? page.versions[page.picked].version : "")) : "未选择版本"
                    color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: "安装位置：" + page.installDir()
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Theme.rSm
                    color: btnHover.containsMouse ? "#2b6fe0" : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: page.kind === "datapack" ? "下载到本地" : "下载并安装"
                        color: "#ffffff"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: btnHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.install()
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: page.status.length > 0 ? page.status : "安装态只有 未安装 / 下载中 / 失败（后端没有已安装/可更新事实源）"
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
