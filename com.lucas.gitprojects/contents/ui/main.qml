import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Umbrales bajos: en el escritorio siempre se ve completo; en un panel, icono con desplegable.
    switchWidth: Kirigami.Units.gridUnit * 4
    switchHeight: Kirigami.Units.gridUnit * 4

    // En un panel se muestra dentro del desplegable de Plasma (con su tema);
    // en el escritorio, con el estilo glass propio.
    readonly property bool inPopup: Plasmoid.location !== PlasmaCore.Types.Floating
    readonly property color fg: inPopup ? Kirigami.Theme.textColor : "white"
    readonly property color cardColor: inPopup ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "#26ffffff"
    readonly property color accentColor: inPopup ? Kirigami.Theme.highlightColor : "#7dd3fc"

    property var repos: []
    property string error: ""
    property string notice: ""
    property real nowMs: Date.now()
    property var expandedRepos: ({})     // ruta -> true si su historial de Claude está abierto
    property var histories: ({})         // ruta -> [{ id, ts, title }]
    property var historyRequests: ({})   // comando -> ruta

    property bool showArchived: false    // true: la lista muestra los proyectos archivados

    function needsAttention(r) { return r.changes > 0 || r.ahead > 0 }

    function parseList(s) {
        try { var a = JSON.parse(s); return Array.isArray(a) ? a : [] } catch (e) { return [] }
    }

    // Rutas archivadas / orden manual, guardados en la configuración del widget
    readonly property var archivedList: parseList(Plasmoid.configuration.archived)
    readonly property var activeRepos: repos.filter(function (r) { return archivedList.indexOf(r.path) < 0 })
    readonly property int archivedCount: repos.length - activeRepos.length
    readonly property int attentionCount: activeRepos.filter(needsAttention).length
    readonly property bool manualSort: Plasmoid.configuration.sortMode === "manual"

    readonly property var sortModes: [
        { id: "auto", label: "Novedades primero" },
        { id: "recent", label: "Último commit" },
        { id: "used", label: "Última actividad (commit, code-oss, Claude)" },
        { id: "name", label: "Nombre (A–Z)" },
        { id: "manual", label: "Manual (con flechas)" }
    ]

    function sortList(list, mode, order) {
        function auto(a, b) {
            var na = needsAttention(a) ? 0 : 1, nb = needsAttention(b) ? 0 : 1
            return na !== nb ? na - nb : b.ts - a.ts
        }
        function activity(r) { return Math.max(r.ts, r.ossTs, r.claudeTs) }
        var cmp = auto
        if (mode === "recent") cmp = function (a, b) { return b.ts - a.ts }
        else if (mode === "used") cmp = function (a, b) { return activity(b) - activity(a) }
        else if (mode === "name") cmp = function (a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) }
        else if (mode === "manual") cmp = function (a, b) {
            var ia = order.indexOf(a.path), ib = order.indexOf(b.path)
            if (ia < 0 && ib < 0) return auto(a, b)
            if (ia < 0) return 1
            if (ib < 0) return -1
            return ia - ib
        }
        return list.slice().sort(cmp)
    }

    function computeShown() {
        var arch = archivedList
        var list = repos.filter(function (r) {
            if ((arch.indexOf(r.path) >= 0) !== showArchived) return false
            return showArchived || !Plasmoid.configuration.onlyAttention || needsAttention(r)
        })
        return sortList(list, Plasmoid.configuration.sortMode, parseList(Plasmoid.configuration.manualOrder))
    }
    readonly property var shownRepos: computeShown()

    function setSort(mode) {
        if (mode === "manual" && parseList(Plasmoid.configuration.manualOrder).length === 0)
            Plasmoid.configuration.manualOrder = JSON.stringify(shownRepos.map(function (r) { return r.path }))
        Plasmoid.configuration.sortMode = mode
    }

    function moveRepo(path, delta) {
        var paths = shownRepos.map(function (r) { return r.path })
        var i = paths.indexOf(path), j = i + delta
        if (i < 0 || j < 0 || j >= paths.length) return
        var t = paths[i]; paths[i] = paths[j]; paths[j] = t
        var rest = parseList(Plasmoid.configuration.manualOrder).filter(function (p) { return paths.indexOf(p) < 0 })
        Plasmoid.configuration.manualOrder = JSON.stringify(paths.concat(rest))
    }

    function setArchived(path, on) {
        var a = archivedList.filter(function (p) { return p !== path })
        if (on) a.push(path)
        Plasmoid.configuration.archived = JSON.stringify(a)
        if (a.length === 0) showArchived = false
    }

    toolTipMainText: "Proyectos Git"
    toolTipSubText: error.length ? error
        : activeRepos.length + " repositorios" + (attentionCount ? " · " + attentionCount + " con novedades" : " · todo al día")

    function localPath(url) {
        var s = url.toString()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        return s
    }
    readonly property string scriptPath: localPath(Qt.resolvedUrl("../code/repos.sh"))
    readonly property string historyScript: localPath(Qt.resolvedUrl("../code/history.sh"))
    readonly property string openShellScript: localPath(Qt.resolvedUrl("../code/open-shell.sh"))

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function ago(ts) {
        if (!ts) return "sin commits"
        var s = Math.max(0, Math.floor(nowMs / 1000 - ts))
        if (s < 90) return "hace un momento"
        var m = Math.floor(s / 60)
        if (m < 60) return "hace " + m + " min"
        var h = Math.floor(m / 60)
        if (h < 48) return "hace " + h + " h"
        var d = Math.floor(h / 24)
        if (d < 60) return "hace " + d + " d"
        return "hace " + Math.floor(d / 30) + " meses"
    }

    function parse(out) {
        var list = []
        var err = ""
        out.split("\n").forEach(function (line) {
            var f = line.split("\t")
            if (f[0] === "ERROR") { err = f[1] || "Error"; return }
            if (f[0] !== "REPO" || f.length < 13) return
            list.push({
                name: f[1], path: f[2], branch: f[3], changes: parseInt(f[4]) || 0,
                ahead: parseInt(f[5]) || 0, behind: parseInt(f[6]) || 0, hasUpstream: f[7] === "1",
                ossTs: parseInt(f[8]) || 0, claudeCount: parseInt(f[9]) || 0, claudeTs: parseInt(f[10]) || 0,
                ts: parseInt(f[11]) || 0, subject: f.slice(12).join(" ")
            })
        })
        root.error = list.length ? "" : (err || "No se encontraron repositorios")
        root.repos = list
        root.nowMs = Date.now()
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = data["stdout"] ? data["stdout"].toString() : ""
            if (sourceName.indexOf("repos.sh") >= 0) {
                root.parse(out)
            } else if (root.historyRequests[sourceName] !== undefined) {
                root.parseHistory(root.historyRequests[sourceName], out)
                var req = Object.assign({}, root.historyRequests)
                delete req[sourceName]
                root.historyRequests = req
            }
        }
    }

    function refresh() {
        exec.connectSource("sh " + shq(root.scriptPath) + " " + shq(Plasmoid.configuration.rootPath) + " " + Plasmoid.configuration.searchDepth)
    }

    function parseHistory(path, out) {
        var list = []
        out.split("\n").forEach(function (line) {
            var f = line.split("\t")
            if (f[0] !== "SESSION" || f.length < 4) return
            list.push({ id: f[1], ts: parseInt(f[2]) || 0, title: f.slice(3).join(" ") })
        })
        var h = Object.assign({}, root.histories)
        h[path] = list
        root.histories = h
    }

    function loadHistory(path) {
        var cmd = "sh " + shq(root.historyScript) + " " + shq(path) + " 12"
        var req = Object.assign({}, root.historyRequests)
        req[cmd] = path
        root.historyRequests = req
        exec.connectSource(cmd)
    }

    function toggleHistory(path) {
        var e = Object.assign({}, root.expandedRepos)
        if (e[path]) delete e[path]
        else { e[path] = true; loadHistory(path) }
        root.expandedRepos = e
    }

    function launch(cmd) {
        // setsid -f: la aplicación queda independiente del widget
        exec.connectSource("setsid -f " + cmd + " >/dev/null 2>&1 #" + Date.now())
    }

    // fish si está instalado, si no el shell por defecto ($SHELL).
    function openTerminal(path) { launch("konsole --workdir " + shq(path) + " -e sh " + shq(root.openShellScript) + " " + shq("")) }
    function openEditor(path) { launch((Plasmoid.configuration.editorCommand || "code-oss") + " " + shq(path)) }

    // Terminal en la carpeta del proyecto, corriendo Claude Code.
    // open-shell.sh usa fish si está instalado, o el shell por defecto ($SHELL) si no,
    // y deja la shell abierta al salir de Claude.
    function openClaude(path, args) {
        var cmd = (Plasmoid.configuration.claudeCommand || "claude") + (args ? " " + args : "")
        launch("konsole --workdir " + shq(path) + " -e sh " + shq(root.openShellScript) + " " + shq(cmd))
    }
    function openFolder(path) { launch("xdg-open " + shq(path)) }

    function copyPath(path) {
        clip.text = path
        clip.selectAll()
        clip.copy()
        notice = "Ruta copiada: " + path
        noticeTimer.restart()
    }

    TextEdit { id: clip; visible: false }
    Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }

    Timer {
        interval: Math.max(3000, Plasmoid.configuration.updateInterval)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    component GlassText: Text {
        color: root.fg
        elide: Text.ElideRight
        layer.enabled: !root.inPopup
        layer.effect: DropShadow {
            verticalOffset: 1
            radius: 5
            samples: 11
            color: "#aa000000"
        }
    }

    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium

        Kirigami.Icon {
            anchors.fill: parent
            source: "vcs-branch"
        }

        Rectangle {
            visible: root.attentionCount > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(height, badge.implicitWidth + 6)
            height: Math.max(12, parent.height * 0.42)
            radius: height / 2
            color: "#f59e0b"
            Text {
                id: badge
                anchors.centerIn: parent
                text: root.attentionCount
                color: "#1a1a1a"
                font.bold: true
                font.pixelSize: parent.height * 0.7
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 28
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24

        Rectangle {
            visible: !root.inPopup
            anchors.fill: parent
            radius: Kirigami.Units.largeSpacing
            color: "#66000000"
            border.color: "#33ffffff"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                GlassText {
                    Layout.fillWidth: true
                    font.bold: true
                    font.pixelSize: Kirigami.Units.gridUnit * 1.1
                    text: root.showArchived ? "Archivados · " + root.archivedCount
                        : "Proyectos · " + root.activeRepos.length +
                          (root.attentionCount ? "  (" + root.attentionCount + " con novedades)" : "  · al día")
                }

                QQC2.ToolButton {
                    icon.name: "view-sort-ascending-name"
                    onClicked: sortMenu.popup(this, 0, height)
                    QQC2.ToolTip.text: "Ordenar"
                    QQC2.ToolTip.visible: hovered

                    QQC2.Menu {
                        id: sortMenu
                        Repeater {
                            model: root.sortModes
                            delegate: QQC2.MenuItem {
                                required property var modelData
                                text: (Plasmoid.configuration.sortMode === modelData.id ? "✓  " : "     ") + modelData.label
                                onTriggered: root.setSort(modelData.id)
                            }
                        }
                    }
                }

                QQC2.ToolButton {
                    visible: root.archivedCount > 0 || root.showArchived
                    icon.name: "archive-extract"
                    checkable: true
                    checked: root.showArchived
                    onClicked: root.showArchived = !root.showArchived
                    QQC2.ToolTip.text: root.showArchived ? "Volver a los proyectos" : "Ver archivados (" + root.archivedCount + ")"
                    QQC2.ToolTip.visible: hovered
                }

                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh()
                    QQC2.ToolTip.text: "Actualizar"
                    QQC2.ToolTip.visible: hovered
                }
            }

            GlassText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.shownRepos.length === 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                opacity: 0.7
                text: root.error.length ? "⚠ " + root.error
                    : root.showArchived ? "No hay proyectos archivados" : "Todo al día ✓"
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.shownRepos.length > 0
                clip: true
                spacing: Kirigami.Units.smallSpacing
                model: root.shownRepos
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                delegate: Rectangle {
                    id: card
                    width: list.width - Kirigami.Units.largeSpacing
                    height: cardCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: Kirigami.Units.mediumSpacing
                    color: root.cardColor

                    readonly property var r: modelData
                    readonly property color dot: r.changes > 0 ? "#f59e0b" : r.ahead > 0 ? "#38bdf8" : "#22c55e"
                    readonly property bool open: !!root.expandedRepos[r.path]
                    readonly property var sessions: root.histories[r.path] || []

                    ColumnLayout {
                        id: cardCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            Rectangle {
                                Layout.preferredWidth: 10
                                Layout.preferredHeight: 10
                                radius: 5
                                color: card.dot
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 1
                                spacing: 0

                                RowLayout {
                                    Layout.minimumWidth: 0
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    GlassText {
                                        text: r.name
                                        font.bold: true
                                        Layout.minimumWidth: 0
                                        Layout.maximumWidth: Kirigami.Units.gridUnit * 11
                                    }
                                    Rectangle {
                                        Layout.preferredWidth: branchText.implicitWidth + 10
                                        Layout.preferredHeight: branchText.implicitHeight + 2
                                        radius: 4
                                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
                                        Text {
                                            id: branchText
                                            anchors.centerIn: parent
                                            width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 9)
                                            text: r.branch
                                            color: root.fg
                                            elide: Text.ElideRight
                                            font.pixelSize: Kirigami.Units.gridUnit * 0.65
                                        }
                                    }
                                    GlassText {
                                        visible: r.changes > 0
                                        text: "● " + r.changes + (r.changes === 1 ? " cambio" : " cambios")
                                        color: "#f59e0b"
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                    }
                                    GlassText {
                                        visible: r.ahead > 0
                                        text: "↑" + r.ahead
                                        color: root.accentColor
                                        font.bold: true
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.75
                                    }
                                    GlassText {
                                        visible: r.behind > 0
                                        text: "↓" + r.behind
                                        color: "#f87171"
                                        font.bold: true
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.75
                                    }
                                    GlassText {
                                        visible: !r.hasUpstream
                                        text: "sin remoto"
                                        opacity: 0.55
                                        font.pixelSize: Kirigami.Units.gridUnit * 0.65
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                GlassText {
                                    Layout.fillWidth: true
                                    text: root.ago(r.ts) + " · " + r.subject
                                    opacity: 0.65
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                                }

                                GlassText {
                                    Layout.fillWidth: true
                                    visible: r.ossTs > 0 || r.claudeCount > 0
                                    text: (r.ossTs > 0 ? "code-oss " + root.ago(r.ossTs) : "") +
                                          (r.ossTs > 0 && r.claudeCount > 0 ? "  ·  " : "") +
                                          (r.claudeCount > 0 ? "Claude: " + r.claudeCount + (r.claudeCount === 1 ? " sesión" : " sesiones") + ", última " + root.ago(r.claudeTs) : "")
                                    color: root.accentColor
                                    opacity: 0.85
                                    font.pixelSize: Kirigami.Units.gridUnit * 0.65
                                }
                            }

                            RowLayout {
                                spacing: 0
                                QQC2.ToolButton {
                                    visible: root.manualSort && !root.showArchived
                                    enabled: index > 0
                                    icon.name: "go-up"
                                    onClicked: root.moveRepo(r.path, -1)
                                    QQC2.ToolTip.text: "Subir"
                                    QQC2.ToolTip.visible: hovered
                                }
                                QQC2.ToolButton {
                                    visible: root.manualSort && !root.showArchived
                                    enabled: index < root.shownRepos.length - 1
                                    icon.name: "go-down"
                                    onClicked: root.moveRepo(r.path, 1)
                                    QQC2.ToolTip.text: "Bajar"
                                    QQC2.ToolTip.visible: hovered
                                }
                                QQC2.ToolButton {
                                    icon.name: "utilities-terminal"
                                    onClicked: root.openTerminal(r.path)
                                    QQC2.ToolTip.text: "Abrir terminal aquí"
                                    QQC2.ToolTip.visible: hovered
                                }
                                QQC2.ToolButton {
                                    icon.name: "document-edit"
                                    onClicked: root.openEditor(r.path)
                                    QQC2.ToolTip.text: "Abrir en code-oss"
                                    QQC2.ToolTip.visible: hovered
                                }
                                QQC2.ToolButton {
                                    icon.name: "im-user-online"
                                    onClicked: root.openClaude(r.path, "")
                                    QQC2.ToolTip.text: "Nueva sesión de Claude Code aquí"
                                    QQC2.ToolTip.visible: hovered
                                }
                                QQC2.ToolButton {
                                    icon.name: "view-history"
                                    checkable: true
                                    checked: card.open
                                    onClicked: root.toggleHistory(r.path)
                                    QQC2.ToolTip.text: "Historial de Claude Code"
                                    QQC2.ToolTip.visible: hovered
                                }
                                QQC2.ToolButton {
                                    icon.name: "folder-open"
                                    onClicked: root.openFolder(r.path)
                                    QQC2.ToolTip.text: "Abrir la carpeta"
                                    QQC2.ToolTip.visible: hovered
                                }
                                QQC2.ToolButton {
                                    icon.name: "edit-copy"
                                    onClicked: root.copyPath(r.path)
                                    QQC2.ToolTip.text: "Copiar la ruta"
                                    QQC2.ToolTip.visible: hovered
                                }
                                QQC2.ToolButton {
                                    icon.name: root.showArchived ? "edit-undo" : "archive-insert"
                                    onClicked: root.setArchived(r.path, !root.showArchived)
                                    QQC2.ToolTip.text: root.showArchived ? "Restaurar" : "Archivar"
                                    QQC2.ToolTip.visible: hovered
                                }
                            }
                        }

                        // Historial de Claude Code de este proyecto
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: card.open
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                QQC2.Button {
                                    icon.name: "list-add"
                                    text: "Nueva sesión"
                                    onClicked: root.openClaude(r.path, "")
                                }
                                QQC2.Button {
                                    icon.name: "media-seek-forward"
                                    text: "Continuar la última"
                                    enabled: r.claudeCount > 0
                                    onClicked: root.openClaude(r.path, "--continue")
                                }
                                Item { Layout.fillWidth: true }
                            }

                            GlassText {
                                Layout.fillWidth: true
                                visible: card.sessions.length === 0
                                text: r.claudeCount > 0 ? "Cargando…" : "Todavía no hay sesiones de Claude Code en este proyecto."
                                opacity: 0.6
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
                            }

                            Repeater {
                                model: card.sessions
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        GlassText {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            font.pixelSize: Kirigami.Units.gridUnit * 0.75
                                        }
                                        GlassText {
                                            Layout.fillWidth: true
                                            text: root.ago(modelData.ts)
                                            opacity: 0.55
                                            font.pixelSize: Kirigami.Units.gridUnit * 0.62
                                        }
                                    }
                                    QQC2.ToolButton {
                                        icon.name: "media-playback-start"
                                        onClicked: root.openClaude(r.path, "--resume " + modelData.id)
                                        QQC2.ToolTip.text: "Reanudar esta sesión"
                                        QQC2.ToolTip.visible: hovered
                                    }
                                }
                            }
                        }
                    }
                }
            }

            GlassText {
                Layout.fillWidth: true
                visible: root.notice.length > 0
                text: root.notice
                color: root.accentColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.7
            }
        }
    }
}
