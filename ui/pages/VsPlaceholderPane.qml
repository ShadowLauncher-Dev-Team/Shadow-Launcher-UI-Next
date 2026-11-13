// SPDX-License-Identifier: AGPL-3.0-or-later
// 版本设置分区占位：尚未施工的分区只显示名称，不做假控件
import QtQuick
import ShadowLauncher.Next

Item {
    id: pane
    property string versionId: ""
    property string title: ""

    Text {
        anchors.centerIn: parent
        text: qsTr("%1 · 待施工").arg(pane.title)
        color: Theme.fg3
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }
}
