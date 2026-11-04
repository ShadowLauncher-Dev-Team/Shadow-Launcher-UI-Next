// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import QtQuick.Effects
import ShadowLauncher.Next

Item {
    id: root
    property string name: "play"
    property color color: Theme.fg2
    property int size: 17
    implicitWidth: size
    implicitHeight: size

    Image {
        id: src
        anchors.fill: parent
        visible: false
        smooth: true
        sourceSize: Qt.size(Math.round(root.size * 2), Math.round(root.size * 2))
        // 空 name 不要拼出 ".../lucide/.svg" 去加载：那是每个空图标一条 Image 错误警告，
        // 启动日志里连刷 3 条，会盖住真正的 QML 报错。
        source: root.name.length > 0
                ? "qrc:/qt/qml/ShadowLauncher/qml/icons/lucide/" + root.name + ".svg"
                : ""
        onStatusChanged: if (status === Image.Error) console.info("[ui] icon missing:", root.name)
    }

    MultiEffect {
        anchors.fill: parent
        source: src
        colorization: 1.0
        colorizationColor: root.color
    }
}