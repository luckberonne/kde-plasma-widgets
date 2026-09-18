/*
 * Glass Dock — task manager con magnificación estilo dock
 * SPDX-License-Identifier: MIT
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
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
    // Borde de la pantalla donde está el panel: el punto indicador va entre ese
    // borde y el icono, y el icono crece alejándose de él.
    readonly property int edge: Plasmoid.location
    readonly property bool edgeTop: edge === PlasmaCore.Types.TopEdge
    readonly property bool edgeLeft: edge === PlasmaCore.Types.LeftEdge
    readonly property bool edgeRight: edge === PlasmaCore.Types.RightEdge
    readonly property real dotSpace: thickness * 0.12

    // El icono base se limita para que, magnificado y con el espacio del punto,
    // nunca quede recortado contra el panel.
    readonly property real baseIcon: Math.max(16, Math.min(thickness * Plasmoid.configuration.iconSizeRatio,
                                                           (thickness - dotSpace) * 0.96 / maxScale))
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
    property int dropIndex: -1
    // El tooltip recuerda su tarea aunque el puntero ya haya salido del dock:
    // si no, se cerraría justo cuando vas a hacer clic en una miniatura.
    property int tipIndex: -1

    preferredRepresentation: fullRepresentation


    // Sólo se fija el eje largo. El transversal lo decide el panel: si se ataba
    // a la propia altura/ancho del applet, quedaba congelado en su valor inicial
    // y al agrandar el panel los iconos no crecían.
    Layout.fillWidth:       vertical
    Layout.fillHeight:      !vertical
    Layout.preferredWidth:  vertical ? -1 : dockLength
    Layout.preferredHeight: vertical ? dockLength : -1
    Layout.minimumWidth:    vertical ? -1 : dockLength
    Layout.minimumHeight:   vertical ? dockLength : -1
    Layout.maximumWidth:    vertical ? Infinity : dockLength
    Layout.maximumHeight:   vertical ? dockLength : Infinity

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

        onCountChanged: if (root.tipIndex >= count) root.tipIndex = -1
    }


    // Lee las ventanas de un grupo sin crear delegados: DelegateModel expone los
    // roles de cada hijo vía items.get(j).model.
    DelegateModel {
        id: groupProbe
        model: tasksModel
        delegate: Item {}
    }

    // Índice hijo de la ventana usada más recientemente dentro del grupo i.
    // Se usa el orden de apilado de KWin (activar una ventana la sube al tope)
    // y no LastActivated: ése sólo se registra mientras plasmashell está vivo,
    // así que tras cada reinicio de sesión o de Plasma viene vacío.
    function mostRecentChild(i) {
        groupProbe.rootIndex = tasksModel.makeModelIndex(i)
        let best = -1
        let top = -1
        for (let j = 0; j < groupProbe.items.count; j++) {
            const order = groupProbe.items.get(j).model.StackingOrder
            if (order !== undefined && order > top) {
                top = order
                best = j
            }
        }
        return best
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



    // Soltar archivos sobre un icono los abre con esa aplicación. Si te quedás
    // un momento encima sin soltar, la ventana se trae al frente (spring-loading)
    // para poder soltar directamente adentro.
    DropArea {
        id: dropArea
        anchors.fill: parent

        Timer {
            id: springTimer
            interval: 750
            onTriggered: {
                if (root.dropIndex < 0) return
                const t = repeater.itemAt(root.dropIndex)
                if (t && !t.isLauncher) tasksModel.requestActivate(tasksModel.makeModelIndex(root.dropIndex))
            }
        }

        function updateTarget(x, y) {
            const pos = root.vertical ? y : x
            const i = root.indexAt(pos)
            root.pointer = pos          // el dock también se magnifica al arrastrar
            if (i !== root.dropIndex) {
                root.dropIndex = i
                springTimer.restart()
            }
        }

        onPositionChanged: drag => updateTarget(drag.x, drag.y)
        onEntered: drag => {
            // Los widgets arrastrados desde el panel no son archivos: que los maneje Plasma.
            if (drag.formats.indexOf("text/x-plasmoidservicename") >= 0) {
                drag.accepted = false
                return
            }
            updateTarget(drag.x, drag.y)
        }
        onExited: {
            springTimer.stop()
            root.dropIndex = -1
            root.pointer = -1000
        }

        onDropped: drop => {
            springTimer.stop()
            const target = root.dropIndex
            root.dropIndex = -1
            root.pointer = -1000
            if (target < 0 || !drop.hasUrls) return

            const t = repeater.itemAt(target)
            tasksModel.requestOpenUrls(tasksModel.makeModelIndex(target), drop.urls)
            if (t) t.bounce()
            drop.accept(Qt.CopyAction)
        }

        MouseArea {
            id: dockArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

            function track(mouse) {
                root.pointer = root.vertical ? mouse.y : mouse.x
                root.focusedIndex = root.indexAt(root.pointer)
                if (root.focusedIndex >= 0) root.tipIndex = root.focusedIndex
            }

            onPositionChanged: mouse => track(mouse)
            onEntered: {
                root.pointer = root.vertical ? mouseY : mouseX
                root.focusedIndex = root.indexAt(root.pointer)
                if (root.focusedIndex >= 0) root.tipIndex = root.focusedIndex
            }
            onExited: {
                // tipIndex NO se limpia acá: el tooltip sigue siendo interactivo
                // mientras el puntero viaja hacia él.
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
                    return
                }

                // En un grupo se actúa sobre la ventana usada por última vez: activar
                // el grupo en sí no trae ninguna ventana al frente.
                let target = idx
                if (item.isGroup) {
                    const child = root.mostRecentChild(i)
                    if (child >= 0) target = tasksModel.makeModelIndex(i, child)
                }

                // Si esa ventana ya está al frente, el clic la minimiza (como en el
                // resto de las ventanas); si no, la trae.
                if (item.isActive) {
                    tasksModel.requestToggleMinimized(target)
                } else {
                    tasksModel.requestActivate(target)
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
                    readonly property var launcherUrl: model.LauncherUrlWithoutIcon
                    readonly property string appName: model.AppName ? model.AppName : model.display
                    readonly property string title: model.display ? model.display : ""
                    readonly property var iconSource: model.decoration
                    readonly property bool isActive: model.IsActive === true
                    readonly property bool isMinimized: model.IsMinimized === true
                    readonly property bool needsAttention: model.IsDemandingAttention === true
                    readonly property real magnify: root.scaleAt(index)
                    property real shift: root.offsetAt(index)

                    width: root.vertical ? root.width : root.cell
                    height: root.vertical ? root.cell : root.height
                    z: Math.round(magnify * 100)

                    x: root.vertical ? 0 : root.baseCenter(index) - root.cell / 2 + shift
                    y: root.vertical ? root.baseCenter(index) - root.cell / 2 + shift : 0

                    Behavior on shift { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                    function bounce() {
                        if (Plasmoid.configuration.bounceOnLaunch) bounceAnim.restart()
                    }

                    Kirigami.Icon {
                        id: icon
                        source: model.decoration
                        active: root.focusedIndex === dockItem.index
                        // Sin esto Kirigami redondea hacia abajo al tamaño estándar más
                        // cercano (45 px -> 32 px) y el zoom avanza a saltos.
                        roundToIconSize: false
                        opacity: dockItem.isMinimized ? 0.55 : 1.0

                        width: root.baseIcon * dockItem.magnify
                        height: width

                        // Anclado al borde de la pantalla (dejando lugar para el punto):
                        // el icono crece "hacia adentro", como en un dock.
                        x: !root.vertical ? (parent.width - width) / 2
                           : root.edgeRight ? parent.width - root.dotSpace - width - bounceAnim.hop
                           : root.dotSpace + bounceAnim.hop
                        y: root.vertical ? (parent.height - height) / 2
                           : root.edgeTop ? root.dotSpace + bounceAnim.hop
                           : parent.height - root.dotSpace - height - bounceAnim.hop

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

                    // Realce del destino mientras se arrastra algo encima.
                    Rectangle {
                        anchors.centerIn: icon
                        width: icon.width * 1.25
                        height: width
                        radius: Kirigami.Units.cornerRadius
                        color: Kirigami.Theme.highlightColor
                        opacity: root.dropIndex === dockItem.index ? 0.35 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    // Punto indicador de ventana abierta.
                    Rectangle {
                        visible: !dockItem.isLauncher
                        readonly property real longSide: dockItem.isActive ? root.baseIcon * 0.26 : root.baseIcon * 0.11
                        readonly property real shortSide: root.baseIcon * 0.11
                        width: root.vertical ? shortSide : longSide
                        height: root.vertical ? longSide : shortSide
                        radius: Math.min(width, height) / 2
                        color: dockItem.needsAttention ? Kirigami.Theme.negativeTextColor
                                                       : Kirigami.Theme.textColor
                        opacity: dockItem.isActive ? 0.95 : 0.6

                        x: !root.vertical ? (parent.width - width) / 2
                           : root.edgeRight ? parent.width - (root.dotSpace + width) / 2
                           : (root.dotSpace - width) / 2
                        y: root.vertical ? (parent.height - height) / 2
                           : root.edgeTop ? (root.dotSpace - height) / 2
                           : parent.height - (root.dotSpace + height) / 2

                        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    }
                }
            }

            PlasmaCore.ToolTipArea {
                id: taskTip
                anchors.fill: parent
                active: Plasmoid.configuration.showLabels && root.tipIndex >= 0 && !dropArea.containsDrag
                interactive: true
                location: Plasmoid.location

                readonly property var task: root.tipIndex >= 0 ? repeater.itemAt(root.tipIndex) : null
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
                                            ? tasksModel.makeModelIndex(root.tipIndex, index)
                                            : tasksModel.makeModelIndex(root.tipIndex)
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
                const t = repeater.itemAt(contextMenu.taskIndex)
                if (!t) return
                if (contextMenu.isLauncher) tasksModel.requestRemoveLauncher(t.launcherUrl)
                else tasksModel.requestAddLauncher(t.launcherUrl)
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
