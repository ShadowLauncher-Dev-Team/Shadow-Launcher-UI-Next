// SPDX-License-Identifier: AGPL-3.0-or-later
import QtQuick
import ShadowLauncher.Next

Window {
    id: appWindow
    visible: true
    flags: Qt.FramelessWindowHint | Qt.Window
    minimumWidth: 800
    minimumHeight: 550
    width: 1375
    height: 897
    title: "Shadow Launcher"
    color: "transparent"

    StageShell {
        anchors.fill: parent
        hostWindow: appWindow
    }
}