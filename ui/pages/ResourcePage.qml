// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import ShadowLauncher.Next

// 资源库列表（A 方案「货架式」）：五类共用，按 tabIndex 参数化
//   1=Mod 2=光影 3=资源包 4=整合包 5=数据包
// 数据全部走已验证的后端池子接口：池子已经是去重+全局加权排序的全量，本页只负责切片渲染。
// 加载中间态统一：busy 上报给外壳 → 顶部 SLoadingBar（StageShell.root.loading）。
Item {
    id: page
    property int tabIndex: 1
    property var toast: null
    readonly property var b: (typeof backend !== "undefined") ? backend : null

    readonly property var kindList: ["", "mod", "shader", "resourcepack", "modpack", "datapack"]
    readonly property string kind: kindList[tabIndex] || "mod"
    readonly property bool narrow: parent ? parent.width < 900 : false

    property string query: ""
    property int source: 0           // 0 全部 1 Modrinth 2 CurseForge
    property int pageNo: 0
    readonly property int pageSize: tabIndex === 2 ? 20 : (tabIndex === 2 ? 20 : 30)
    property var pool: []
    property bool busy: false

    signal openDetail(string kind, var item)

    readonly property int cols: width >= 1000 ? 4 : (width >= 740 ? 3 : 2)

    function sourceArg() { return page.source === 1 ? "modrinth" : (page.source === 2 ? "curseforge" : "") }

    function doSearch(pageNum) {
        if (!page.b) return
        page.pageNo = (pageNum === undefined) ? 0 : Math.max(0, pageNum)
        page.busy = true
        var q = page.query.trim()
        var off = page.pageNo * page.pageSize
        if (page.tabIndex === 1) {
            page.b.searchModsEx(q, "", "", [], "", "", off, page.pageSize, page.sourceArg())
        } else if (page.tabIndex === 2) {
            page.b.searchShadersEx(q, [], [], [], [], off, page.pageSize, page.sourceArg())
        } else if (page.tabIndex === 3) {
            page.b.searchResourcepacks(q, "", off, [], page.sourceArg())
        } else if (page.tabIndex === 4) {
            page.b.searchModpacksEx(q, "", "", [], off, page.pageSize, page.sourceArg())
        } else if (page.tabIndex === 5) {
            page.b.searchDatapacksEx(q, "", [], "", off, page.pageSize, page.sourceArg())
        }
        settleTimer.restart()
    }

    // 结果到达：按池子切片（后端已经是全量有序池）
    function applyPool(items) {
        page.pool = items || []
        listModel.clear()
        var start = page.pageNo * page.pageSize
        var end = Math.min(start + page.pageSize, page.pool.length)
        for (var i = start; i < end; ++i) {
            var r = page.pool[i] || ({})
            // 图标走司南缓存（原始 cdn .webp Qt 解不了，会整片空白）
            var iconUrl = r.icon || ""
            if (iconUrl && page.b) iconUrl = page.b.resolveIconUrl(iconUrl)
            listModel.append({
                title: r.title || r.slug || "",
                zh: r.zh || "",
                desc: r.desc || "",
                icon: iconUrl,
                iconRaw: r.icon || "",
                slug: r.slug || "",
                downloads: r.downloads || 0,
                source: r.source || "Modrinth",
                dateModified: r.dateModified || ""
            })
        }
    }

    function hasMore() {
        try {
            var st = page.b ? page.b.resourcePoolState(page.kind) : null
            if (st && st.hasMore !== undefined) return !!st.hasMore
        } catch (e) {}
        return page.pool.length > (page.pageNo + 1) * page.pageSize
    }

    onTabIndexChanged: {
        listModel.clear(); page.pool = []; page.pageNo = 0; page.query = ""; page.source = 0
        page.doSearch(0)
    }

    Component.onCompleted: page.doSearch(0)

    // 后端还在拉（progressive emit）：轮询 pending，归零才关条
    Timer {
        id: settleTimer
        interval: 300; repeat: true
        running: page.busy
        property int ticks: 0
        onTriggered: {
            ticks++
            var pending = 0
            try {
                var st = page.b ? page.b.resourcePoolState(page.kind) : null
                pending = st ? st.pending : 0
            } catch (e) {}
            if (pending === 0 || ticks > 30) {
                ticks = 0
                page.busy = false
                running = false
            }
        }
        onRunningChanged: if (running) ticks = 0
    }

    Connections {
        target: page.b
        enabled: page.b !== null
        function onModSearchResultsReady(results) { if (page.tabIndex === 1) page.applyPool(results) }
        function onShaderSearchResultsReady(results) { if (page.tabIndex === 2) page.applyPool(results) }
        function onResourcepackSearchCompleted(results, totalHits) { if (page.tabIndex === 3) page.applyPool(results) }
        function onModpackSearchResultsReady(results) { if (page.tabIndex === 4) page.applyPool(results) }
        function onDatapackSearchResultsReady(results) { if (page.tabIndex === 5) page.applyPool(results) }
        // 司南异步下完图标 → 回填对应行（原始 URL 命中则换成本地路径）
        function onIconReady(url, localPath) {
            for (var i = 0; i < listModel.count; ++i) {
                if (listModel.get(i).iconRaw === url)
                    listModel.setProperty(i, "icon", localPath)
            }
        }
    }

    ListModel { id: listModel }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // ── 搜索 + 来源 ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: Theme.rSm
                color: "#0d1016"
                border.width: 1
                border.color: searchInput.activeFocus ? Theme.accent : Theme.line2
                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    selectByMouse: true
                    clip: true
                    Text {
                        visible: searchInput.text.length === 0
                        text: "搜索名称 / 英文名 / 标签"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    onTextChanged: page.query = text
                    Keys.onReturnPressed: page.doSearch(0)
                }
            }

            Repeater {
                model: [{ t: "全部来源", v: 0 }, { t: "Modrinth", v: 1 }, { t: "CurseForge", v: 2 }]
                delegate: Rectangle {
                    Layout.preferredHeight: 36
                    implicitWidth: srcTxt.implicitWidth + 24
                    radius: Theme.rSm
                    color: page.source === modelData.v ? "#1b2433" : "#0d1016"
                    border.width: 1
                    border.color: page.source === modelData.v ? "#2c3a4f" : Theme.line2
                    Text {
                        id: srcTxt
                        anchors.centerIn: parent
                        text: modelData.t
                        color: page.source === modelData.v ? Theme.fg : Theme.fg2
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { page.source = modelData.v; page.doSearch(0) }
                    }
                }
            }

            Rectangle {
                Layout.preferredHeight: 36
                implicitWidth: resetTxt.implicitWidth + 24
                radius: Theme.rSm
                color: resetHover.containsMouse ? "#141922" : "transparent"
                border.width: 1
                border.color: Theme.line2
                Text {
                    id: resetTxt
                    anchors.centerIn: parent
                    text: "重置筛选"
                    color: Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                MouseArea {
                    id: resetHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { searchInput.text = ""; page.query = ""; page.source = 0; page.doSearch(0) }
                }
            }
        }

        // ── 网格 ──
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: listModel
            readonly property int gap: 10
            cellWidth: Math.floor((width - (page.cols - 1) * gap) / page.cols)
            cellHeight: 156

            delegate: ResourceTile {
                width: grid.cellWidth - grid.gap
                height: grid.cellHeight - grid.gap
                title: model.title
                zh: model.zh
                description: model.desc
                iconUrl: model.icon
                slug: model.slug
                downloads: model.downloads
                source: model.source
                dateModified: model.dateModified
                onClicked: page.openDetail(page.kind, {
                    slug: model.slug, title: model.title, zh: model.zh,
                    desc: model.desc, icon: model.icon, downloads: model.downloads,
                    source: model.source, dateModified: model.dateModified
                })
            }
        }

        // ── 空态 / 加载态 ──
        Column {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            visible: listModel.count === 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.busy ? "正在加载…" : "没有找到匹配的资源"
                color: page.busy ? Theme.fg2 : Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !page.busy
                width: 96; height: 30
                radius: Theme.rSm
                color: retryHover.containsMouse ? "#141922" : "transparent"
                border.width: 1
                border.color: Theme.line2
                Text {
                    anchors.centerIn: parent
                    text: "重新加载"
                    color: Theme.fg2
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                MouseArea {
                    id: retryHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.doSearch(page.pageNo)
                }
            }
        }

        // ── 分页 ──
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            visible: listModel.count > 0
            Item { Layout.fillWidth: true }
            Text {
                text: (page.pageNo + 1) + " / " + Math.max(1, Math.ceil(page.pool.length / page.pageSize))
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
            Rectangle {
                Layout.preferredWidth: 64; Layout.preferredHeight: 28
                radius: Theme.rSm
                color: prevHover.containsMouse ? "#141922" : "transparent"
                border.width: 1; border.color: Theme.line2
                Text {
                    anchors.centerIn: parent
                    text: "上一页"
                    color: page.pageNo > 0 ? Theme.fg2 : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 11
                }
                MouseArea {
                    id: prevHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (page.pageNo > 0) page.doSearch(page.pageNo - 1)
                }
            }
            Rectangle {
                Layout.preferredWidth: 64; Layout.preferredHeight: 28
                radius: Theme.rSm
                color: nextHover.containsMouse ? "#141922" : "transparent"
                border.width: 1; border.color: Theme.line2
                Text {
                    anchors.centerIn: parent
                    text: "下一页"
                    color: page.hasMore() ? Theme.fg2 : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 11
                }
                MouseArea {
                    id: nextHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (page.hasMore()) page.doSearch(page.pageNo + 1)
                }
            }
        }
    }
}
