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
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.private.volume as PlasmaPa
import org.kde.plasma.plasma5support as Plasma5Support

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

    // Los iconos que aparecen después de esto entran con animación; los del
    // arranque del panel aparecen ya en su lugar.
    property bool settled: false
    Timer { running: true; interval: 2500; onTriggered: root.settled = true }

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



    // ---------- insignias ----------
    // Un único modelo con todas las notificaciones y trabajos de Plasma, contado
    // por app (desktopEntry). No sirve filtrar con whitelistedDesktopEntries: esa
    // lista es de excepciones al bloqueo, no un filtro. Tampoco se puede usar la
    // API Unity LauncherEntry: cada app la emite desde su propio servicio y ruta,
    // y el SignalWatcher de Plasma exige servicio y ruta fijos.
    NotificationManager.Notifications {
        id: allNotifs
        showNotifications: true
        showJobs: true
        showExpired: true
        onCountChanged: badgeTimer.restart()
        onDataChanged: badgeTimer.restart()
        onModelReset: badgeTimer.restart()
    }
    DelegateModel {
        id: notifProbe
        model: allNotifs
        delegate: Item {}
    }

    readonly property date startedAt: new Date()
    property var seenAt: ({})      // desktopEntry -> última vez que se usó la app
    property var appBadges: ({})   // desktopEntry -> { unread, jobs, percent }

    Timer {
        id: badgeTimer
        interval: 150
        onTriggered: root.recomputeBadges()
    }

    function markSeen(entry) {
        if (!entry) return
        const m = Object.assign({}, seenAt)
        m[entry] = new Date()
        seenAt = m
        recomputeBadges()
    }

    function recomputeBadges() {
        const out = {}
        for (let j = 0; j < notifProbe.items.count; j++) {
            const m = notifProbe.items.get(j).model
            const entry = m.desktopEntry
            if (!entry) continue
            const b = out[entry] || (out[entry] = { unread: 0, jobs: 0, percent: 0 })
            if (m.type === NotificationManager.Notifications.NotificationType) {
                // "Sin leer" = llegó después de la última vez que usaste la app.
                if (!m.read && m.created > (seenAt[entry] || startedAt)) b.unread++
            } else if (m.type === NotificationManager.Notifications.JobType
                       && m.jobState === NotificationManager.Notifications.JobStateRunning) {
                b.jobs++
                b.percent += m.percentage || 0
            }
        }
        appBadges = out
    }


    // ---------- audio ----------
    // Flujos de audio de PipeWire/PulseAudio, igual que el task manager oficial.
    // Se asocian a cada tarea por PID; si no coincide (Firefox reproduce desde un
    // subproceso), por nombre de la app o por el app id del portal.
    Instantiator {
        id: audioStreams
        active: Plasmoid.configuration.showAudio
        model: PlasmaPa.PulseObjectFilterModel {
            filters: [ { role: "VirtualStream", value: false } ]
            sourceModel: PlasmaPa.SinkInputModel {}
        }
        delegate: QtObject {
            required property var model
            readonly property int pid: model.Client?.properties["application.process.id"] ?? 0
            readonly property string appName: (model.Client?.properties["application.name"] ?? "").toLowerCase()
            readonly property string portalAppId: model.Client?.properties["pipewire.access.portal.app_id"] ?? ""
            readonly property bool muted: model.Muted
            readonly property bool corked: model.Corked
            function setMuted(m) { model.Muted = m }
        }
        onObjectAdded: root.audioRevision++
        onObjectRemoved: root.audioRevision++
    }
    property int audioRevision: 0

    function streamsFor(pid, appName, entry) {
        root.audioRevision  // dependencia explícita: altas y bajas de flujos
        const name = (appName || "").toLowerCase()
        const out = []
        for (let k = 0; k < audioStreams.count; k++) {
            const st = audioStreams.objectAt(k)
            if (!st) continue
            if ((pid > 0 && st.pid === pid) || (name !== "" && st.appName === name)
                    || (entry !== "" && st.portalAppId === entry)) {
                out.push(st)
            }
        }
        return out
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

    // ---------- peek de ventana ----------
    // Resalta una ventana con el efecto "Resaltar ventana" de KWin (el mismo que
    // usa el task manager oficial): la ventana queda al frente y las demás se
    // desvanecen, sin cambiar el foco ni el orden de apilado. Al soltar, todo
    // vuelve a como estaba. Se llama a KWin por D-Bus con busctl.
    property int peekSeq: 0
    property bool peeking: false

    function peekWindow(winId) {
        if (!Plasmoid.configuration.peekOnHover || !winId) return
        peeking = true
        exec.connectSource("busctl --user call org.kde.KWin /org/kde/KWin/HighlightWindow "
                           + "org.kde.KWin.HighlightWindow highlightWindows as 1 "
                           + shellQuote(String(winId)) + " # " + (++peekSeq))
    }

    function clearPeek() {
        peekTimer.stop()
        if (!peeking) return
        peeking = false
        exec.connectSource("busctl --user call org.kde.KWin /org/kde/KWin/HighlightWindow "
                           + "org.kde.KWin.HighlightWindow highlightWindows as 0 # " + (++peekSeq))
    }

    property var peekTarget: null
    Timer {
        id: peekTimer
        interval: 350
        onTriggered: root.peekWindow(root.peekTarget)
    }
    Component.onDestruction: clearPeek()

    function hideTips() {
        clearPeek()
        for (let i = 0; i < repeater.count; i++) {
            const it = repeater.itemAt(i)
            if (it) it.hideTip()
        }
    }

    property Item tipContent: Item {
        id: tipRoot

        readonly property var task: root.tipTask
        readonly property var windows: root.tipWindows
        onVisibleChanged: if (!visible) root.clearPeek()
        property bool dragInside: false
        function pingDragInside() { dragInside = true; dragInsideTimer.restart() }
        Timer { id: dragInsideTimer; interval: 500; onTriggered: tipRoot.dragInside = false }

        DropArea {
            id: tipBackgroundDrop
            anchors.fill: parent
            z: -1
            onEntered: tipRoot.pingDragInside()
            onExited: root.dragMightHaveLeft()
            onPositionChanged: tipRoot.pingDragInside()
        }
        readonly property bool hasPreviews: Plasmoid.configuration.showPreviews && windows.length > 0
        readonly property real previewW: Kirigami.Units.gridUnit * 12
        readonly property real previewH: previewW * 0.6
        // Hasta 12 miniaturas en una grilla de hasta 4 columnas.
        readonly property int shown: Math.min(windows.length, 12)
        readonly property int columns: Math.max(1, Math.min(shown, 4))
        readonly property int rows: Math.ceil(shown / columns)
        readonly property real gap: Kirigami.Units.smallSpacing

        implicitWidth: hasPreviews
            ? columns * previewW + (columns - 1) * gap + Kirigami.Units.largeSpacing * 2
            : heading.implicitWidth + Kirigami.Units.largeSpacing * 2
        implicitHeight: heading.implicitHeight + Kirigami.Units.largeSpacing * 2
                        + (hasPreviews ? rows * previewH + (rows - 1) * gap + gap : 0)

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

            Grid {
                id: previewGrid
                columns: tipRoot.columns
                spacing: tipRoot.gap
                anchors.horizontalCenter: parent.horizontalCenter
                visible: tipRoot.hasPreviews

                Repeater {
                    model: tipRoot.hasPreviews ? tipRoot.windows.slice(0, tipRoot.shown) : []

                    delegate: MouseArea {
                        id: previewItem
                        required property var modelData
                        required property int index

                        width: tipRoot.previewW
                        height: tipRoot.previewH
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                        // Quedarse sobre la miniatura muestra esa ventana al frente; salir
                        // (o hacer clic) lo deshace.
                        onContainsMouseChanged: {
                            if (containsMouse) {
                                root.peekTarget = modelData
                                peekTimer.restart()
                            } else if (root.peekTarget === modelData) {
                                root.peekTarget = null
                                root.clearPeek()
                            }
                        }

                        onClicked: mouse => {
                            root.clearPeek()
                            // Una ventana suelta se direcciona por su fila; dentro de un
                            // grupo hace falta el índice hijo.
                            const t = tipRoot.task
                            const idx = (t && t.isGroup)
                                ? tasksModel.makeModelIndex(root.tipIndex, index)
                                : tasksModel.makeModelIndex(root.tipIndex)

                            // Clic derecho: acciones de esa ventana.
                            if (mouse.button === Qt.RightButton) {
                                root.openWindowMenu(root.tipIndex, idx)
                                return
                            }

                            // Rueda del medio sobre una miniatura: cierra sólo esa ventana
                            // y deja el tooltip abierto con las demás.
                            if (mouse.button === Qt.MiddleButton) {
                                tasksModel.requestClose(idx)
                                return
                            }
                            tasksModel.requestActivate(idx)
                            root.hideTips()
                            root.closeDragPreview()
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Kirigami.Units.cornerRadius
                            color: Kirigami.Theme.highlightColor
                            opacity: previewDrop.containsDrag ? 0.35 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        // Al quedarte parado sobre una miniatura, la trae al frente sin
                        // cerrar el popup ni soltar nada -- para poder soltar directo en la
                        // ventana real en vez de en la miniatura chica, si se prefiere.
                        Timer {
                            id: raiseWindowTimer
                            interval: 700
                            onTriggered: {
                                const t = tipRoot.task
                                const idx = (t && t.isGroup)
                                    ? tasksModel.makeModelIndex(root.tipIndex, previewItem.index)
                                    : tasksModel.makeModelIndex(root.tipIndex)
                                tasksModel.requestActivate(idx)
                            }
                        }

                        // Soltar un archivo acá lo abre en esta ventana en particular.
                        DropArea {
                            id: previewDrop
                            anchors.fill: parent
                            onEntered: drag => {
                                tipRoot.pingDragInside()
                                raiseWindowTimer.restart()
                            }
                            onPositionChanged: drag => tipRoot.pingDragInside()
                            onExited: {
                                raiseWindowTimer.stop()
                                root.dragMightHaveLeft()
                            }
                            onDropped: drop => {
                                raiseWindowTimer.stop()
                                exitGraceTimer.stop()
                                root.dropIndex = -1
                                root.pointer = -1000
                                root.closeDragPreview()
                                if (!drop.hasUrls) return
                                const t = tipRoot.task
                                const idx = (t && t.isGroup)
                                    ? tasksModel.makeModelIndex(root.tipIndex, previewItem.index)
                                    : tasksModel.makeModelIndex(root.tipIndex)
                                tasksModel.requestOpenUrls(idx, drop.urls)
                                drop.accept(Qt.CopyAction)
                                root.hideTips()
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Kirigami.Units.cornerRadius
                            color: Kirigami.Theme.textColor
                            opacity: previewItem.containsMouse ? 0.14 : 0.06
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Kirigami.Units.cornerRadius
                            color: "transparent"
                            border.width: 1
                            border.color: Kirigami.Theme.highlightColor
                            opacity: previewItem.containsMouse ? 0.8 : 0
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


    // Clic izquierdo (y atajo Meta+número): lanza, trae al frente o minimiza.
    function activateTask(i) {
        const item = repeater.itemAt(i)
        if (!item) return
        const idx = tasksModel.makeModelIndex(i)
        if (item.isLauncher) {
            tasksModel.requestActivate(idx)
            item.bounce()
            return
        }

        // En un grupo se actúa sobre la ventana que el icono está mostrando en ese
        // momento (si está recorriéndolas) o, si no, la usada por última vez:
        // activar el grupo en sí no trae ninguna ventana al frente.
        let target = idx
        if (item.isGroup) {
            const child = item.previewIndex >= 0 ? item.previewIndex : root.mostRecentChild(i)
            if (child >= 0) target = tasksModel.makeModelIndex(i, child)
        }

        // Si esa ventana ya está al frente se minimiza; si no, se trae.
        if (item.isActive) {
            tasksModel.requestToggleMinimized(target)
        } else {
            tasksModel.requestActivate(target)
        }
    }

    // Trae al frente la ventana más reciente de la tarea i sin minimizarla nunca
    // (a diferencia de activateTask, que alterna). Restaura si estaba minimizada.
    function raiseTask(i) {
        const item = repeater.itemAt(i)
        if (!item || item.isLauncher) return
        let target = tasksModel.makeModelIndex(i)
        if (item.isGroup) {
            const child = root.mostRecentChild(i)
            if (child >= 0) target = tasksModel.makeModelIndex(i, child)
        }
        tasksModel.requestActivate(target)
    }

    // Trae al frente la ventana siguiente (dir = 1) o anterior (dir = -1) de la
    // tarea i. Sin ninguna activa, empieza por la usada más recientemente.
    function cycleWindows(i, dir) {
        const item = repeater.itemAt(i)
        if (!item || item.isLauncher) return
        if (!item.isGroup) {
            tasksModel.requestActivate(tasksModel.makeModelIndex(i))
            return
        }
        groupProbe.rootIndex = tasksModel.makeModelIndex(i)
        const n = groupProbe.items.count
        if (n === 0) return
        let current = -1
        for (let j = 0; j < n; j++) {
            if (groupProbe.items.get(j).model.IsActive === true) { current = j; break }
        }
        const next = current < 0 ? root.mostRecentChild(i) : (current + dir + n) % n
        tasksModel.requestActivate(tasksModel.makeModelIndex(i, next))
    }

    // Llamada por plasmashell para los atajos Meta+1…9 ("Activar la entrada N del
    // gestor de tareas"). Requiere declarar org.kde.plasma.multitasking en metadata.
    function activateTaskAtIndex(index) {
        if (typeof index !== "number") return
        activateTask(index)
    }

    // ---------- popup de arrastre ----------
    // El tooltip normal de hover (PlasmaCore.ToolTipArea) es una ventana marcada
    // como "Tooltip": KWin no le enruta el drag-and-drop de Wayland a ese tipo de
    // ventana (el popup abría, pero el arrastre se perdía en el mismo instante).
    // Este es un PlasmaCore.Dialog aparte, sin ese tipo, que sí participa del
    // protocolo de arrastre -- por eso el arrastre necesita su propio popup en
    // vez de reusar el tooltip de hover normal.
    PlasmaCore.Dialog {
        id: dragPreviewDialog
        location: Plasmoid.location
        visible: false
        // Respaldo: si el popup se cierra por cualquier motivo que no sea nuestro
        // propio closeDragPreview() -- por ejemplo, al soltar directamente sobre la
        // ventana real que se trajo al frente, drop que nunca pasa por ninguno de
        // nuestros DropArea -- igual hay que soltar el estado del arrastre, si no
        // el resaltado del icono queda pegado para siempre.
        onVisibleChanged: if (!visible) root.dragPreviewClosed()
    }

    function dragPreviewClosed() {
        exitGraceTimer.stop()
        springTimer.stop()
        root.dropIndex = -1
        root.pointer = -1000
    }

    // Cualquier "salió" -- del dock, del fondo del popup o de una miniatura en
    // particular -- puede ser la última señal antes de que el arrastre se haya
    // ido de verdad (por ejemplo, hacia la ventana real que se acaba de traer al
    // frente). Se agenda siempre el mismo margen de gracia; si el arrastre sigue
    // en algún lado válido, el propio timer lo cancela al chequear.
    function dragMightHaveLeft() {
        exitGraceTimer.restart()
    }

    function openDragPreview(i) {
        const t = repeater.itemAt(i)
        if (!t) return
        dragPreviewDialog.visualParent = t
        dragPreviewDialog.mainItem = root.tipContent
        dragPreviewDialog.visible = true
    }
    function closeDragPreview() {
        dragPreviewDialog.visible = false
        dragPreviewDialog.mainItem = null
    }

    // Fija cada .desktop de la lista como lanzador nuevo; ignora el resto (no
    // tiene sentido fijar una imagen o un documento suelto). Devuelve true si
    // fijó al menos uno, para poder confirmar el drop sólo en ese caso.
    function toggleAppExcluded(entry) {
        if (!entry) return
        const list = Plasmoid.configuration.excludedApps.slice()
        const i = list.indexOf(entry)
        if (i >= 0) list.splice(i, 1)
        else list.push(entry)
        Plasmoid.configuration.excludedApps = list
    }

    function pinDroppedLaunchers(urls) {
        let pinned = false
        for (const url of urls) {
            if (String(url).toLowerCase().endsWith(".desktop") && tasksModel.requestAddLauncher(url)) {
                pinned = true
            }
        }
        return pinned
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

    // El icono bajo el puntero según lo que se DIBUJA (con zoom y empuje de los
    // vecinos), no según las celdas base: si no, con muchas apps el icono que ves
    // debajo del cursor no es el que recibe el clic. Se elige el centro visual más
    // cercano; `pointer` ya es el del evento en curso, así offsetAt() coincide.
    function indexAt(pos) {
        const n = tasksModel.count
        if (pos < edgePad || pos > edgePad + n * cell) return -1
        let best = -1
        let bestDist = Infinity
        for (let i = 0; i < n; i++) {
            const d = Math.abs(pos - (baseCenter(i) + offsetAt(i)))
            if (d < bestDist) { bestDist = d; best = i }
        }
        return best
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
            // Sólo para apps de una única ventana: la trae al frente (restaurándola
            // si estaba minimizada) para poder soltar directamente adentro. Con
            // varias ventanas se usa el popup de arrastre en su lugar (más abajo).
            interval: 750
            onTriggered: {
                if (root.dropIndex < 0) return
                root.raiseTask(root.dropIndex)
            }
        }

        function updateTarget(x, y) {
            exitGraceTimer.stop()
            const pos = root.vertical ? y : x
            root.pointer = pos          // el dock también se magnifica al arrastrar
            const i = root.indexAt(pos)
            if (i !== root.dropIndex) {
                root.dropIndex = i
                springTimer.stop()
                const t = i >= 0 ? repeater.itemAt(i) : null
                if (t && !t.isLauncher && t.isGroup && t.winIds.length > 1) {
                    // El popup ya deja elegir la ventana exacta: no hace falta ir
                    // trayendo ventanas reales al frente por su cuenta mientras tanto,
                    // eso solo compite con lo que se está mirando en el popup.
                    root.tipIndex = i
                    root.openDragPreview(i)
                } else {
                    root.closeDragPreview()
                    if (t && !t.isLauncher) springTimer.restart()
                }
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
            root.dragMightHaveLeft()
        }

        Timer {
            id: exitGraceTimer
            interval: 200
            onTriggered: {
                if (dropArea.containsDrag) return
                if (root.tipContent.dragInside) return
                root.closeDragPreview()
                root.dropIndex = -1
                root.pointer = -1000
            }
        }

        onDropped: drop => {
            springTimer.stop()
            exitGraceTimer.stop()
            root.closeDragPreview()
            const target = root.dropIndex
            root.dropIndex = -1
            root.pointer = -1000

            // Lanzador arrastrado desde el dock de otra pantalla: se fija acá.
            if (drop.formats.indexOf("application/x-glassdock-launcher") >= 0) {
                const url = drop.getDataAsString("application/x-glassdock-launcher")
                if (url && tasksModel.requestAddLauncher(url)) drop.accept(Qt.MoveAction)
                return
            }

            if (!drop.hasUrls) return

            // Soltar en un espacio vacío del dock (sin ningún icono debajo) fija los
            // .desktop que traiga el arrastre, como agregar un lanzador nuevo.
            if (target < 0) {
                if (root.pinDroppedLaunchers(drop.urls)) drop.accept(Qt.CopyAction)
                return
            }

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

                // Si el lanzador se va fuera del propio dock, deja de ser un
                // reordenamiento interno y pasa a ser un arrastre real del sistema,
                // para poder soltarlo sobre el dock de otra pantalla.
                const outside = mouse.x < 0 || mouse.x > root.width
                              || mouse.y < 0 || mouse.y > root.height
                const item = repeater.itemAt(root.reorderIndex)
                if (outside && item && item.isLauncher) {
                    reordering = false
                    root.reorderIndex = -1
                    item.startExternalDrag()
                    return
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
                contextMenu.visible = false
                track(mouse)
                const i = root.focusedIndex
                if (i < 0) return

                // Rueda del medio: cierra todas las ventanas de la app.
                if (mouse.button === Qt.MiddleButton) {
                    root.closeAll(i)
                    return
                }
                if (mouse.button === Qt.RightButton) {
                    contextMenu.taskIndex = i
                    contextMenu.isLauncher = repeater.itemAt(i).isLauncher
                    root.openContextMenu(repeater.itemAt(i).desktopEntry)
                    return
                }

                root.activateTask(i)
            }

            // Rueda del mouse sobre un icono: recorre las ventanas de esa app.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                property real accumulated: 0
                onWheel: event => {
                    const i = root.focusedIndex
                    if (i < 0) return
                    // 120 = un "paso" de rueda; acumular hace que los touchpads,
                    // que mandan deltas chicos, no salten ventana con cada evento.
                    accumulated += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                    while (Math.abs(accumulated) >= 120) {
                        root.cycleWindows(i, accumulated > 0 ? -1 : 1)
                        accumulated -= accumulated > 0 ? 120 : -120
                    }
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
                    // Nombre de la entrada .desktop (sin extensión): es la clave con la
                    // que Plasma asocia notificaciones y trabajos a cada app.
                    readonly property string desktopEntry: (model.AppId || "").replace(/\.desktop$/, "")
                    readonly property var winIds: model.WinIdList !== undefined ? model.WinIdList : []
                    readonly property bool isGroup: model.IsGroupParent === true
                    readonly property var launcherUrl: model.LauncherUrlWithoutIcon

                    // ---- arrastrar a otra pantalla ----
                    // Sólo tiene sentido para lanzadores fijos: una ventana real no
                    // "vive" en un dock, así que no hay nada que mover al otro lado.
                    Drag.dragType: Drag.None
                    Drag.supportedActions: Qt.MoveAction
                    Drag.proposedAction: Qt.MoveAction
                    Drag.keys: ["application/x-glassdock-launcher"]

                    function startExternalDrag() {
                        if (!isLauncher || !launcherUrl) return
                        Drag.mimeData = { "application/x-glassdock-launcher": String(launcherUrl) }
                        Drag.dragType = Drag.Automatic
                        Drag.start()
                    }

                    // El dock destino acepta con Qt.MoveAction; si el que soltó ahí
                    // confirma esa acción, el lanzador se quita de este dock.
                    Drag.onDragFinished: dropAction => {
                        Drag.dragType = Drag.None
                        if (dropAction === Qt.MoveAction) tasksModel.requestRemoveLauncher(launcherUrl)
                    }
                    readonly property string appName: model.AppName ? model.AppName : model.display
                    readonly property string title: model.display ? model.display : ""
                    readonly property var iconSource: model.decoration
                    readonly property bool isActive: model.IsActive === true
                    readonly property bool isMinimized: model.IsMinimized === true
                    readonly property bool needsAttention: model.IsDemandingAttention === true
                    readonly property real magnify: root.scaleAt(index)
                    property real shift: root.offsetAt(index)

                    // ---- auto-switch en el icono ----
                    // Con varias ventanas, al quedarte parado sobre el icono empieza a
                    // mostrar una miniatura en vivo de cada una por turnos, para ver de
                    // un vistazo qué hay abierto sin tener que abrir el tooltip.
                    property int previewIndex: -1
                    readonly property bool canCycle: Plasmoid.configuration.cycleIconPreview
                        && isGroup && winIds.length > 1
                    readonly property bool shouldDwell: canCycle && root.focusedIndex === index
                        && root.reorderIndex < 0 && !dropArea.containsDrag

                    // No se liga `running` del Timer a esta expresión: un Timer sin
                    // repetición pone running=false por su cuenta al disparar, lo que
                    // rompería el binding y, en el mismo instante, dispararía el reset
                    // de más abajo -- deshaciendo el índice recién puesto. Se arranca y
                    // se para a mano en cambios de shouldDwell.
                    onShouldDwellChanged: {
                        if (shouldDwell) {
                            dwellTimer.restart()
                        } else {
                            dwellTimer.stop()
                            cycleTimer.stop()
                            previewIndex = -1
                        }
                    }
                    onWinIdsChanged: if (previewIndex >= winIds.length) previewIndex = -1

                    Timer {
                        id: dwellTimer
                        interval: 400
                        onTriggered: {
                            dockItem.previewIndex = root.mostRecentChild(dockItem.index)
                            cycleTimer.restart()
                        }
                    }
                    Timer {
                        id: cycleTimer
                        interval: 1600
                        repeat: true
                        onTriggered: {
                            if (dockItem.winIds.length === 0) { dockItem.previewIndex = -1; return }
                            dockItem.previewIndex = (dockItem.previewIndex + 1) % dockItem.winIds.length
                        }
                    }

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
                    onNeedsAttentionChanged: if (needsAttention && !isStartup) bounce()
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

                    // Al mantener apretado el botón izquierdo el icono se hunde un poco,
                    // salvo que ya se esté reordenando (ahí el icono sigue al puntero).
                    property real pressScale: dockArea.pressed && !dockArea.reordering
                        && root.reorderIndex === index ? 0.9 : 1.0
                    Behavior on pressScale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                    // 0 -> 1 al aparecer un icono nuevo (app que se abre o se fija).
                    property real appear: 1
                    NumberAnimation {
                        id: appearAnim
                        target: dockItem; property: "appear"; to: 1
                        duration: 320; easing.type: Easing.OutBack
                    }

                    Component.onCompleted: {
                        if (root.settled) { appear = 0; appearAnim.start() }
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
                        opacity: (dockItem.previewIndex >= 0 ? 0 : (dockItem.isMinimized ? 0.55 : 1.0))
                                 * Math.min(1, dockItem.appear)
                        scale: (0.6 + 0.4 * dockItem.appear) * dockItem.pressScale

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

                    Loader {
                        id: previewLoader
                        active: dockItem.previewIndex >= 0
                        anchors.fill: icon
                        opacity: active ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        sourceComponent: WindowPreview {
                            windowId: dockItem.previewIndex >= 0 && dockItem.winIds[dockItem.previewIndex]
                                      ? dockItem.winIds[dockItem.previewIndex] : ""
                            fallbackIcon: dockItem.iconSource
                        }
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

                    // ---- insignias y progreso ----
                    // Calculadas en root.appBadges a partir de las notificaciones de Plasma.
                    readonly property var badgeInfo: root.appBadges[desktopEntry] || null
                    readonly property bool excludedFromExtras: desktopEntry !== ""
                        && Plasmoid.configuration.excludedApps.indexOf(desktopEntry) >= 0
                    readonly property bool badgesOn: Plasmoid.configuration.showBadges && desktopEntry !== ""
                        && !excludedFromExtras
                    readonly property int unread: badgesOn && badgeInfo ? badgeInfo.unread : 0
                    readonly property bool busy: badgesOn && badgeInfo !== null && badgeInfo.jobs > 0
                    readonly property real progress: busy ? badgeInfo.percent / badgeInfo.jobs : 0
                    // Usar la app "lee" sus notificaciones: la insignia se limpia.
                    onIsActiveChanged: if (isActive) root.markSeen(desktopEntry)

                    Rectangle {
                        id: badge
                        visible: scale > 0
                        scale: dockItem.unread > 0 ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        z: 2
                        height: Math.round(icon.height * 0.36)
                        width: Math.max(height, badgeText.implicitWidth + height * 0.5)
                        radius: height / 2
                        color: Kirigami.Theme.negativeTextColor
                        x: icon.x + icon.width - width * 0.75
                        y: icon.y - height * 0.2

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: dockItem.unread > 99 ? "99+" : dockItem.unread
                            color: "white"
                            font.pixelSize: parent.height * 0.62
                            font.bold: true
                        }
                    }

                    Rectangle {
                        id: progressTrack
                        visible: opacity > 0
                        opacity: dockItem.busy ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        z: 2
                        width: icon.width * 0.8
                        height: Math.max(3, Math.round(icon.height * 0.09))
                        radius: height / 2
                        x: icon.x + (icon.width - width) / 2
                        y: icon.y + icon.height - height * 1.6
                        color: Qt.rgba(0, 0, 0, 0.55)

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(100, dockItem.progress)) / 100
                            height: parent.height
                            radius: parent.radius
                            color: Kirigami.Theme.highlightColor
                            Behavior on width { NumberAnimation { duration: 200 } }
                        }
                    }

                    // ---- audio ----
                    readonly property var streams: Plasmoid.configuration.showAudio && !isLauncher && !excludedFromExtras
                        ? root.streamsFor(model.AppPid || 0, appName, desktopEntry) : []
                    readonly property bool playing: streams.some(st => !st.corked)
                    readonly property bool muted: streams.length > 0 && streams.every(st => st.muted)

                    Rectangle {
                        id: audioBadge
                        visible: scale > 0
                        scale: dockItem.playing || dockItem.muted ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        z: 3
                        width: Math.round(icon.width * 0.38)
                        height: width
                        radius: width / 2
                        color: Qt.rgba(0, 0, 0, 0.6)
                        x: icon.x - width * 0.25
                        y: icon.y - height * 0.2

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: parent.width * 0.7
                            height: width
                            roundToIconSize: false
                            color: "white"
                            isMask: true
                            source: dockItem.muted ? "audio-volume-muted" : "audio-volume-high"
                        }

                        // Encima del área del dock: este clic no activa la app.
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -2
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const target = !dockItem.muted
                                dockItem.streams.forEach(st => st.setMuted(target))
                            }
                        }
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

                    // Un punto por ventana abierta, acotado a 3 -- más que eso satura
                    // visualmente el borde sin aportar información extra.
                    property int dotCount: Math.min(dockItem.winIds.length, 3)
                    readonly property real dotSize: root.baseIcon * (dockItem.isActive ? 0.13 : 0.11)
                    readonly property real dotGap: root.baseIcon * 0.05

                    Loader {
                        active: !dockItem.isLauncher && dockItem.dotCount > 0
                        sourceComponent: dots

                        x: !root.vertical ? (parent.width - width) / 2
                           : root.edgeRight ? parent.width - (root.dotSpace + width) / 2
                           : (root.dotSpace - width) / 2
                        y: root.vertical ? (parent.height - height) / 2
                           : root.edgeTop ? (root.dotSpace - height) / 2
                           : parent.height - (root.dotSpace + height) / 2
                    }

                    Component {
                        id: dots
                        Grid {
                            // Una fila en un dock horizontal, una columna en uno vertical.
                            columns: root.vertical ? 1 : Math.max(1, dockItem.dotCount)
                            spacing: dockItem.dotGap
                            Repeater {
                                model: dockItem.dotCount
                                delegate: Rectangle {
                                    width: dockItem.dotSize
                                    height: width
                                    radius: width / 2
                                    color: dockItem.needsAttention ? Kirigami.Theme.negativeTextColor
                                         : dockItem.isActive ? Kirigami.Theme.highlightColor
                                                             : Kirigami.Theme.textColor
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    opacity: dockItem.isActive ? 0.95 : 0.6
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    // ---- acciones de la app (Actions= del .desktop) ----
    // Se consultan con un script al hacer clic derecho y el menú se abre cuando
    // llega la respuesta; si el script falla o tarda, se abre igual sin acciones.
    readonly property string actionsScript:
        Qt.resolvedUrl("../scripts/actions.py").toString().replace(/^file:\/\//, "")
    property string pendingActionsCmd: ""

    function shellQuote(str) { return "'" + String(str).replace(/'/g, "'\\''") + "'" }

    // Menú de una ventana concreta (clic derecho en su miniatura). Se ancla al
    // icono del dock y no a la miniatura: ésa vive en la ventana del tooltip,
    // que se cierra al abrir esto.
    function openWindowMenu(i, winIdx) {
        root.hideTips()
        root.closeDragPreview()
        contextMenu.taskIndex = i
        contextMenu.isLauncher = false
        contextMenu.appActions = []
        contextMenu.winIdx = winIdx
        contextMenu.windowMode = true
        contextMenu.popup()
    }

    function openContextMenu(entry) {
        contextMenu.windowMode = false
        contextMenu.appActions = []
        if (entry === "") { contextMenu.popup(); return }
        pendingActionsCmd = "python3 " + shellQuote(actionsScript) + " " + shellQuote(entry)
        actionsFallback.restart()
        exec.connectSource(pendingActionsCmd)
    }

    Timer {
        id: actionsFallback
        interval: 1500
        onTriggered: { root.pendingActionsCmd = ""; contextMenu.popup() }
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            if (sourceName !== root.pendingActionsCmd) return
            root.pendingActionsCmd = ""
            actionsFallback.stop()
            let list = []
            try { list = JSON.parse(data["stdout"] ? data["stdout"].toString() : "[]") } catch (e) {}
            contextMenu.appActions = list.filter(a => a.name !== i18n("Nueva ventana"))
            contextMenu.popup()
        }
    }

    // Popup de acciones: un PlasmaCore.Dialog anclado al icono, como el tooltip, así
    // se abre del lado de adentro del panel (arriba, si el dock está abajo) y sin
    // scroll, en vez del menú nativo que se dibujaba encima del dock.
    PlasmaCore.Dialog {
        id: contextMenu
        property var appActions: []
        property int taskIndex: -1
        property bool isLauncher: false
        property bool excluded: false
        // Modo ventana: acciones de una ventana puntual (winIdx) en vez de la app.
        property bool windowMode: false
        property var winIdx: null
        property bool winMinimized: false
        property bool winMaximized: false
        property bool winAbove: false
        property string winTitle: ""
        // desktopEntry de la tarea sobre la que se abrió el menú; "" cuando no
        // hay ninguna app que excluir.
        readonly property string entry: {
            const t = taskIndex >= 0 ? repeater.itemAt(taskIndex) : null
            return t ? t.desktopEntry : ""
        }

        location: Plasmoid.location
        visible: false
        hideOnWindowDeactivate: true

        function popup() {
            const t = taskIndex >= 0 ? repeater.itemAt(taskIndex) : null
            if (!t) return
            excluded = entry !== "" && Plasmoid.configuration.excludedApps.indexOf(entry) >= 0
            if (windowMode && winIdx) {
                const A = TaskManager.AbstractTasksModel
                winMinimized = tasksModel.data(winIdx, A.IsMinimized) === true
                winMaximized = tasksModel.data(winIdx, A.IsMaximized) === true
                winAbove = tasksModel.data(winIdx, A.IsKeepAbove) === true
                winTitle = tasksModel.data(winIdx, Qt.DisplayRole) || ""
            }
            visualParent = t
            visible = true
        }
        function run(fn) {
            visible = false
            fn()
        }

        mainItem: ColumnLayout {
            id: menuColumn
            spacing: 0
            Layout.minimumWidth: Kirigami.Units.gridUnit * 13

            component Entry: QQC2.ItemDelegate {
                Layout.fillWidth: true
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
            }

            // ---- modo ventana ----
            QQC2.Label {
                visible: contextMenu.windowMode
                text: contextMenu.winTitle
                elide: Text.ElideRight
                font.bold: true
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                Layout.margins: Kirigami.Units.smallSpacing
            }
            Entry {
                visible: contextMenu.windowMode
                text: i18n("Traer al frente")
                icon.name: "window"
                onClicked: contextMenu.run(() => tasksModel.requestActivate(contextMenu.winIdx))
            }
            Entry {
                visible: contextMenu.windowMode
                text: contextMenu.winMinimized ? i18n("Restaurar") : i18n("Minimizar")
                icon.name: contextMenu.winMinimized ? "window-restore" : "window-minimize"
                onClicked: contextMenu.run(() => tasksModel.requestToggleMinimized(contextMenu.winIdx))
            }
            Entry {
                visible: contextMenu.windowMode
                text: contextMenu.winMaximized ? i18n("Dejar de maximizar") : i18n("Maximizar")
                icon.name: contextMenu.winMaximized ? "window-restore" : "window-maximize"
                onClicked: contextMenu.run(() => tasksModel.requestToggleMaximized(contextMenu.winIdx))
            }
            Entry {
                visible: contextMenu.windowMode
                text: contextMenu.winAbove ? i18n("Dejar de mantener encima") : i18n("Mantener encima")
                icon.name: "window-keep-above"
                onClicked: contextMenu.run(() => tasksModel.requestToggleKeepAbove(contextMenu.winIdx))
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: contextMenu.windowMode }
            Entry {
                visible: contextMenu.windowMode
                text: i18n("Cerrar ventana")
                icon.name: "window-close"
                onClicked: contextMenu.run(() => tasksModel.requestClose(contextMenu.winIdx))
            }

            // ---- modo app ----
            Entry {
                visible: !contextMenu.windowMode
                text: i18n("Nueva ventana")
                icon.name: "window-new"
                onClicked: contextMenu.run(() =>
                    tasksModel.requestNewInstance(tasksModel.makeModelIndex(contextMenu.taskIndex)))
            }
            Repeater {
                model: contextMenu.appActions
                delegate: Entry {
                    required property var modelData
                    text: modelData.name
                    icon.name: modelData.icon
                    // setsid -f: la app queda desligada de plasmashell.
                    onClicked: contextMenu.run(() =>
                        exec.connectSource("setsid -f sh -c " + root.shellQuote(modelData.exec)))
                }
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: !contextMenu.windowMode }
            Entry {
                visible: !contextMenu.windowMode
                text: contextMenu.isLauncher ? i18n("Quitar del dock") : i18n("Fijar al dock")
                icon.name: contextMenu.isLauncher ? "window-unpin" : "window-pin"
                onClicked: contextMenu.run(() => {
                    const t = repeater.itemAt(contextMenu.taskIndex)
                    if (!t) return
                    if (contextMenu.isLauncher) tasksModel.requestRemoveLauncher(t.launcherUrl)
                    else tasksModel.requestAddLauncher(t.launcherUrl)
                })
            }
            Entry {
                visible: !contextMenu.windowMode
                text: contextMenu.excluded ? i18n("Volver a mostrar insignias y audio")
                                           : i18n("Sin insignias ni audio para esta app")
                icon.name: "notifications-disabled"
                enabled: contextMenu.entry !== ""
                onClicked: contextMenu.run(() => root.toggleAppExcluded(contextMenu.entry))
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: !contextMenu.isLauncher && !contextMenu.windowMode }
            Entry {
                visible: !contextMenu.isLauncher && !contextMenu.windowMode
                text: i18n("Cerrar")
                icon.name: "window-close"
                onClicked: contextMenu.run(() =>
                    tasksModel.requestClose(tasksModel.makeModelIndex(contextMenu.taskIndex)))
            }
        }
    }
}
