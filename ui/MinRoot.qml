// SPDX-License-Identifier: AGPL-3.0-or-later
// 诊断用：最小根对象。用来分离「QML 引擎固定开销」和「主界面构图成本」。
// 只由 --ui-min-root 加载，不参与正常启动。
import QtQuick

Window {
    visible: true
    width: 1100
    height: 720
    color: "#08090d"
}