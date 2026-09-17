/*
 * Glass Dock — task manager con magnificación estilo dock
 * SPDX-License-Identifier: MIT
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real thickness: vertical ? width : height
    readonly property real maxScale: Math.max(1.0, Plasmoid.configuration.maxScale)

    // El icono base se limita para que el zoom nunca quede recortado contra el borde del panel.
    readonly property real baseIcon: Math.max(16, Math.min(thickness * Plasmoid.configuration.iconSizeRatio,
                                                           thickness * 0.94 / maxScale))
    readonly property real gap: Math.round(baseIcon * 0.28)
    readonly property real cell: baseIcon + gap
    readonly property real influence: cell * Plasmoid.configuration.influenceFactor
    // Margen reservado para que el desplazamiento de los vecinos no cambie el tamaño del applet.
    readonly property real edgePad: baseIcon * (maxScale - 1.0) * 0.6
    readonly property real pushMax: baseIcon * (maxScale - 1.0) * Plasmoid.configuration.spread

    readonly property real dockLength: tasksModel.count * cell + 2 * edgePad

    // Posición del puntero sobre el eje largo del dock (-1000 = sin hover).
    property real pointer: -1000
    property int focusedIndex: -1

    preferredRepresentation: fullRepresentation

    Layout.preferredWidth:  vertical ? thickness : dockLength
    Layout.preferredHeight: vertical ? dockLength : thickness
    Layout.minimumWidth:    Layout.preferredWidth
    Layout.minimumHeight:   Layout.preferredHeight
    Layout.maximumWidth:    Layout.preferredWidth
    Layout.maximumHeight:   Layout.preferredHeight

    // ---------- modelo de tareas ----------
    TaskManager.VirtualDesktopInfo { id: virtualDesktopInfo }
    TaskManager.ActivityInfo { id: activityInfo }

    TaskManager.TasksModel {
        id: tasksModel
        virtualDesktop: virtualDesktopInfo.currentDesktop
        screenGeometry: root.screenGeometry
        activity: activityInfo.currentActivity

        filterByVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByScreen: Plasmoid.configuration.showOnlyCurrentScreen
        filterByActivity: true

        launchInPlace: true
        separateLaunchers: false
        groupMode: TaskManager.TasksModel.GroupApplications
        sortMode: TaskManager.TasksModel.SortManual

        launcherList: Plasmoid.configuration.launchers
        onLauncherListChanged: Plasmoid.configuration.launchers = launcherList
    }

    // ---------- geometría del dock ----------
    // Centro de la celda i, sin magnificar. Todo se deriva de acá, así que el
    // layout es función pura del puntero: no hay realimentación ni temblor.
    function baseCenter(i) {
        return edgePad + i * cell + cell / 2
    }

    function falloff(d) {
        if (d >= 1) return 0
        return Math.pow(Math.cos(d * Math.PI / 2), 1.7)
    }

    function scaleAt(i) {
        if (pointer < -100) return 1.0
        return 1.0 + (maxScale - 1.0) * falloff(Math.abs(pointer - baseCenter(i)) / influence)
    }

    // Empuja los vecinos hacia afuera: 0 en el icono enfocado y 0 lejos, máximo en el medio.
    function offsetAt(i) {
        if (pointer < -100) return 0
        const delta = baseCenter(i) - pointer
        const d = Math.abs(delta) / influence
        if (d >= 1) return 0
        return pushMax * Math.sin(d * Math.PI) * (delta < 0 ? -1 : 1)
    }

    function indexAt(pos) {
        const i = Math.floor((pos - edgePad) / cell)
        return (i >= 0 && i < tasksModel.count) ? i : -1
    }

    // ---------- interacción ----------
    MouseArea {
        id: dockArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        function track(mouse) {
            root.pointer = root.vertical ? mouse.y : mouse.x
            root.focusedIndex = root.indexAt(root.pointer)
        }

        onPositionChanged: mouse => track(mouse)
        onEntered: root.pointer = root.vertical ? mouseY : mouseX
        onExited: {
            root.pointer = -1000
            root.focusedIndex = -1
        }

        onClicked: mouse => {
            track(mouse)
            const i = root.focusedIndex
            if (i < 0) return
            const idx = tasksModel.makeModelIndex(i)

            if (mouse.button === Qt.MiddleButton) {
                tasksModel.requestNewInstance(idx)
                repeater.itemAt(i).bounce()
                return
            }
            if (mouse.button === Qt.RightButton) {
                contextMenu.taskIndex = i
                contextMenu.isLauncher = repeater.itemAt(i).isLauncher
                contextMenu.popup()
                return
            }

            const item = repeater.itemAt(i)
            if (item.isLauncher) {
                tasksModel.requestActivate(idx)
                item.bounce()
            } else if (item.isActive) {
                tasksModel.requestToggleMinimized(idx)
            } else {
                tasksModel.requestActivate(idx)
            }
        }

        // ---------- iconos ----------
        Repeater {
            id: repeater
            model: tasksModel

            delegate: Item {
                id: dockItem

                required property int index
                required property var model

                readonly property bool isLauncher: model.IsLauncher === true
                readonly property var winIds: model.WinIdList !== undefined ? model.WinIdList : []
                readonly property bool isGroup: model.IsGroupParent === true
                readonly property string appName: model.AppName ? model.AppName : model.display
                readonly property string title: model.display ? model.display : ""
                readonly property var iconSource: model.decoration
                readonly property bool isActive: model.IsActive === true
                readonly property bool isMinimized: model.IsMinimized === true
                readonly property bool needsAttention: model.IsDemandingAttention === true
                readonly property real magnify: root.scaleAt(index)
                property real shift: root.offsetAt(index)

                width: root.cell
                height: root.cell
                z: Math.round(magnify * 100)

                x: root.vertical ? (root.width - root.cell) / 2
                                 : root.baseCenter(index) - root.cell / 2 + shift
                y: root.vertical ? root.baseCenter(index) - root.cell / 2 + shift
                                 : (root.height - root.cell) / 2

                Behavior on shift { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                function bounce() {
                    if (Plasmoid.configuration.bounceOnLaunch) bounceAnim.restart()
                }

                Kirigami.Icon {
                    id: icon
                    source: model.decoration
                    active: root.focusedIndex === dockItem.index
                    opacity: dockItem.isMinimized ? 0.55 : 1.0

                    width: root.baseIcon * dockItem.magnify
                    height: width

                    // Anclado al borde del panel: el icono crece "hacia adentro",
                    // como en un dock, en vez de hacerlo desde el centro.
                    x: root.vertical ? parent.width - width - bounceAnim.hop
                                     : (parent.width - width) / 2
                    y: root.vertical ? (parent.height - height) / 2
                                     : parent.height - height - bounceAnim.hop

                    Behavior on width {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                SequentialAnimation {
                    id: bounceAnim
                    property real hop: 0
                    NumberAnimation { target: bounceAnim; property: "hop"; to: root.baseIcon * 0.45; duration: 220; easing.type: Easing.OutQuad }
                    NumberAnimation { target: bounceAnim; property: "hop"; to: 0; duration: 380; easing.type: Easing.OutBounce }
                }

                // Punto indicador de ventana abierta.
                Rectangle {
                    visible: !dockItem.isLauncher
                    width: dockItem.isActive ? root.baseIcon * 0.26 : root.baseIcon * 0.11
                    height: root.baseIcon * 0.11
                    radius: height / 2
                    color: dockItem.needsAttention ? Kirigami.Theme.negativeTextColor
                                                   : Kirigami.Theme.textColor
                    opacity: dockItem.isActive ? 0.95 : 0.6

                    x: root.vertical ? root.baseIcon * 0.06 : (parent.width - width) / 2
                    y: root.vertical ? (parent.height - height) / 2 : parent.height - height - root.baseIcon * 0.04

                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
            }
        }

        PlasmaCore.ToolTipArea {
            id: taskTip
            anchors.fill: parent
            active: Plasmoid.configuration.showLabels && root.focusedIndex >= 0
            interactive: true
            location: Plasmoid.location

            readonly property var task: root.focusedIndex >= 0 ? repeater.itemAt(root.focusedIndex) : null
            readonly property var windows: task && !task.isLauncher ? task.winIds : []

            mainItem: Item {
                id: tipRoot

                readonly property var task: taskTip.task
                readonly property var windows: taskTip.windows
                readonly property bool hasPreviews: Plasmoid.configuration.showPreviews && windows.length > 0
                readonly property real previewW: Kirigami.Units.gridUnit * 12
                readonly property real previewH: previewW * 0.6
                readonly property int shown: Math.min(windows.length, 4)

                implicitWidth: hasPreviews
                    ? shown * previewW + (shown - 1) * Kirigami.Units.smallSpacing + Kirigami.Units.largeSpacing * 2
                    : heading.implicitWidth + Kirigami.Units.largeSpacing * 2
                implicitHeight: heading.implicitHeight + Kirigami.Units.largeSpacing * 2
                                + (hasPreviews ? previewH + Kirigami.Units.smallSpacing : 0)

                Column {
                    id: tipColumn
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        id: heading
                        level: 5
                        text: tipRoot.task ? tipRoot.task.appName : ""
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Row {
                        id: previewRow
                        spacing: Kirigami.Units.smallSpacing
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: tipRoot.hasPreviews

                        Repeater {
                            model: tipRoot.hasPreviews ? tipRoot.windows : []

                            delegate: MouseArea {
                                id: previewItem
                                required property var modelData
                                required property int index

                                width: tipRoot.previewW
                                height: tipRoot.previewH
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    // Una ventana suelta se direcciona por su fila; dentro de un
                                    // grupo hace falta el índice hijo.
                                    const t = tipRoot.task
                                    const idx = (t && t.isGroup)
                                        ? tasksModel.makeModelIndex(root.focusedIndex, index)
                                        : tasksModel.makeModelIndex(root.focusedIndex)
                                    tasksModel.requestActivate(idx)
                                    taskTip.hideToolTip()
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Kirigami.Units.cornerRadius
                                    color: Kirigami.Theme.textColor
                                    opacity: previewItem.containsMouse ? 0.14 : 0.06
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }

                                WindowPreview {
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    windowId: previewItem.modelData
                                    fallbackIcon: tipRoot.task ? tipRoot.task.iconSource : null
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    QQC2.Menu {
        id: contextMenu
        property int taskIndex: -1
        property bool isLauncher: false

        QQC2.MenuItem {
            text: i18n("Nueva ventana")
            onTriggered: tasksModel.requestNewInstance(tasksModel.makeModelIndex(contextMenu.taskIndex))
        }
        QQC2.MenuItem {
            text: contextMenu.isLauncher ? i18n("Quitar del dock") : i18n("Fijar al dock")
            onTriggered: {
                const idx = tasksModel.makeModelIndex(contextMenu.taskIndex)
                if (contextMenu.isLauncher) tasksModel.requestRemoveLauncher(idx)
                else tasksModel.requestAddLauncher(idx)
            }
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            text: i18n("Cerrar")
            enabled: !contextMenu.isLauncher
            onTriggered: tasksModel.requestClose(tasksModel.makeModelIndex(contextMenu.taskIndex))
        }
    }
}
