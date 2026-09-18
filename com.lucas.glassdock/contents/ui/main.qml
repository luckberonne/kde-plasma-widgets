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
    property int reorderIndex: -1  // icono que se está arrastrando para reordenar
    // repeater.itemAt() no notifica cuando el Repeater recrea un delegate (pasa al
    // abrir o activar una app). Este contador se incrementa con cada cambio del
    // modelo y fuerza a volver a buscarlo, en vez de quedarse con uno destruido.
    property int modelRevision: 0

    preferredRepresentation: fullRepresentation

    // Panel sin fondo: se usa el mecanismo propio de Plasma. Si el contenedor del
    // panel declara NoBackground, la vista del panel no dibuja el fondo ni pide
    // desenfoque. Al desactivar la opción se restaura el valor anterior.
    Binding {
        target: Plasmoid.containment
        property: "backgroundHints"
        value: PlasmaCore.Types.NoBackground
        when: Plasmoid.configuration.hidePanelBackground && Plasmoid.containment !== null
        restoreMode: Binding.RestoreBindingOrValue
    }


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
        onDataChanged: root.modelRevision++
        onRowsInserted: root.modelRevision++
        onRowsRemoved: root.modelRevision++
        onRowsMoved: root.modelRevision++
        onModelReset: root.modelRevision++
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

    // Cierra todas las ventanas de la tarea i. En un grupo se cierra cada hijo
    // explícitamente; los índices se juntan antes porque el modelo cambia a
    // medida que las ventanas se van cerrando.
    function closeAll(i) {
        const item = repeater.itemAt(i)
        if (!item || item.isLauncher) return
        if (!item.isGroup) {
            tasksModel.requestClose(tasksModel.makeModelIndex(i))
            return
        }
        groupProbe.rootIndex = tasksModel.makeModelIndex(i)
        const children = []
        for (let j = 0; j < groupProbe.items.count; j++) children.push(tasksModel.makeModelIndex(i, j))
        children.forEach(idx => tasksModel.requestClose(idx))
    }


    // ---------- tooltip ----------
    // Un único contenido compartido por las áreas de tooltip de todos los iconos
    // (como el task manager oficial): Plasma ubica el tooltip sobre el icono y lo
    // desliza de uno a otro, y el contenido sigue a tipIndex.
    readonly property var tipTask: {
        root.modelRevision  // dependencia explícita, ver modelRevision
        return root.tipIndex >= 0 ? repeater.itemAt(root.tipIndex) : null
    }
    readonly property var tipWindows: tipTask && !tipTask.isLauncher ? tipTask.winIds : []

    function hideTips() {
        for (let i = 0; i < repeater.count; i++) {
            const it = repeater.itemAt(i)
            if (it) it.hideTip()
        }
    }

    property Item tipContent: Item {
        id: tipRoot

        readonly property var task: root.tipTask
        readonly property var windows: root.tipWindows
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
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                        onClicked: mouse => {
                            // Una ventana suelta se direcciona por su fila; dentro de un
                            // grupo hace falta el índice hijo.
                            const t = tipRoot.task
                            const idx = (t && t.isGroup)
                                ? tasksModel.makeModelIndex(root.tipIndex, index)
                                : tasksModel.makeModelIndex(root.tipIndex)

                            // Rueda del medio sobre una miniatura: cierra sólo esa ventana
                            // y deja el tooltip abierto con las demás.
                            if (mouse.button === Qt.MiddleButton) {
                                tasksModel.requestClose(idx)
                                return
                            }
                            tasksModel.requestActivate(idx)
                            root.hideTips()
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

            // ---- reordenar arrastrando ----
            // Pasada la distancia de arrastre del sistema, el icono presionado se
            // mueve en el modelo cada vez que el puntero entra en otra celda, como
            // en el task manager oficial. Al soltar se guarda el orden de lanzadores.
            property point pressPos: Qt.point(0, 0)
            property bool reordering: false

            onPressed: mouse => {
                track(mouse)
                pressPos = Qt.point(mouse.x, mouse.y)
                reordering = false
                root.reorderIndex = mouse.button === Qt.LeftButton ? root.focusedIndex : -1
            }

            onPositionChanged: mouse => {
                track(mouse)
                if (!pressed || root.reorderIndex < 0) return

                if (!reordering) {
                    const moved = root.vertical ? Math.abs(mouse.y - pressPos.y)
                                                : Math.abs(mouse.x - pressPos.x)
                    if (moved < Qt.styleHints.startDragDistance) return
                    reordering = true
                    root.hideTips()
                }

                const target = root.focusedIndex
                if (target >= 0 && target !== root.reorderIndex
                        && tasksModel.move(root.reorderIndex, target)) {
                    root.reorderIndex = target
                }
            }

            onReleased: {
                if (reordering) tasksModel.syncLaunchers()
                root.reorderIndex = -1
            }
            onCanceled: {
                reordering = false
                root.reorderIndex = -1
            }
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
                // Soltar después de reordenar no es un clic.
                if (reordering) {
                    reordering = false
                    return
                }
                root.hideTips()
                track(mouse)
                const i = root.focusedIndex
                if (i < 0) return
                const idx = tasksModel.makeModelIndex(i)

                // Rueda del medio: cierra todas las ventanas de la app.
                if (mouse.button === Qt.MiddleButton) {
                    root.closeAll(i)
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
                    readonly property bool isStartup: model.IsStartup === true
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
                        if (Plasmoid.configuration.bounceOnLaunch && !startupBounce.running) bounceAnim.restart()
                    }

                    // Mientras la app arranca (IsStartup), el icono rebota en bucle hasta
                    // que aparece su ventana, como en macOS; después aterriza suave.
                    function startBouncing() {
                        if (!Plasmoid.configuration.bounceOnLaunch) return
                        bounceAnim.stop()
                        startupBounce.restart()
                    }
                    onIsStartupChanged: {
                        if (isStartup) {
                            startBouncing()
                        } else if (startupBounce.running) {
                            startupBounce.stop()
                            settleAnim.restart()
                        }
                    }

                    // Área de tooltip de este icono; el contenido es el compartido.
                    PlasmaCore.ToolTipArea {
                        id: itemTip
                        anchors.fill: parent
                        mainItem: root.tipContent
                        location: Plasmoid.location
                        interactive: true
                        active: Plasmoid.configuration.showLabels && !dropArea.containsDrag
                                && dockItem.appName !== ""
                        onContainsMouseChanged: if (containsMouse) root.tipIndex = dockItem.index
                    }
                    function hideTip() { itemTip.hideToolTip() }

                    // ---- geometría para KWin ----
                    // KWin usa esta geometría como destino de la animación de minimizar
                    // (lámpara mágica, squash): sin ella la ventana no va hacia su icono.
                    // Se publica la celda en su posición de reposo, sin el desplazamiento
                    // del zoom, para que el destino no dependa de dónde esté el mouse.
                    Item {
                        id: geometryAnchor
                        x: root.vertical ? 0 : -dockItem.shift
                        y: root.vertical ? -dockItem.shift : 0
                        width: dockItem.width
                        height: dockItem.height
                    }

                    // Con demora: la posición cambia muchas veces seguidas (reacomodo del
                    // panel, cambios en la lista) y alcanza con avisar el valor final.
                    Timer {
                        id: publishTimer
                        interval: 250
                        onTriggered: dockItem.publishGeometry()
                    }

                    function publishGeometry() {
                        if (dockItem.isLauncher || !dockItem.Window.window) return
                        const p = geometryAnchor.mapToGlobal(0, 0)
                        tasksModel.requestPublishDelegateGeometry(
                            tasksModel.makeModelIndex(dockItem.index),
                            Qt.rect(Math.round(p.x), Math.round(p.y),
                                    Math.round(geometryAnchor.width), Math.round(geometryAnchor.height)),
                            geometryAnchor)
                    }

                    Component.onCompleted: {
                        publishTimer.restart()
                        // Una app lanzada desde otro lado aparece ya en estado de arranque.
                        if (isStartup) startBouncing()
                    }
                    onIndexChanged: publishTimer.restart()
                    onIsLauncherChanged: publishTimer.restart()
                    onIsGroupChanged: publishTimer.restart()
                    Connections {
                        target: root
                        function onXChanged() { publishTimer.restart() }
                        function onYChanged() { publishTimer.restart() }
                        function onWidthChanged() { publishTimer.restart() }
                        function onHeightChanged() { publishTimer.restart() }
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
                    SequentialAnimation {
                        id: startupBounce
                        loops: Animation.Infinite
                        NumberAnimation { target: bounceAnim; property: "hop"; to: root.baseIcon * 0.4; duration: 260; easing.type: Easing.OutQuad }
                        NumberAnimation { target: bounceAnim; property: "hop"; to: 0; duration: 260; easing.type: Easing.InQuad }
                        PauseAnimation { duration: 120 }
                    }
                    NumberAnimation {
                        id: settleAnim
                        target: bounceAnim; property: "hop"; to: 0
                        duration: 200; easing.type: Easing.OutQuad
                    }

                    // Realce del destino mientras se arrastra algo encima.
                    Rectangle {
                        anchors.centerIn: icon
                        width: icon.width * 1.25
                        height: width
                        radius: Kirigami.Units.cornerRadius
                        color: Kirigami.Theme.highlightColor
                        opacity: (root.dropIndex === dockItem.index || root.reorderIndex === dockItem.index) ? 0.35 : 0
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
