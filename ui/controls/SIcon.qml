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
        source: "qrc:/qt/qml/ShadowLauncher/qml/icons/lucide/" + root.name + ".svg"
        onStatusChanged: if (status === Image.Error) console.info("[ui] icon missing:", root.name)
    }

    MultiEffect {
        anchors.fill: parent
        source: src
        colorization: 1.0
        colorizationColor: root.color
    }
}