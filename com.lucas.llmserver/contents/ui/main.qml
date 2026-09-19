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

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 10


    // En un panel se muestra dentro del desplegable de Plasma (con su tema);
    // en el escritorio, con el estilo glass propio.
    readonly property bool inPopup: Plasmoid.location !== PlasmaCore.Types.Floating
    readonly property color fg: inPopup ? Kirigami.Theme.textColor : "white"
    readonly property color trackColor: inPopup ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15) : "#33ffffff"

    // Estado del servicio (systemd) y del sistema
    property string unitState: "unknown"
    property real memBytes: NaN
    property real sinceEpoch: NaN
    property real vramProc: NaN
    property real vramUsed: NaN
    property real vramTotal: NaN
    property real nowEpoch: Date.now() / 1000

    // Estado del servidor HTTP
    property bool reachable: false
    property string modelName: ""
    property int nCtx: 0
    property int ctxUsed: 0
    property bool generating: false

    // Velocidad de generación
    property real tps: 0          // instantánea (suavizada) mientras genera
    property real lastAvgTps: NaN // promedio de la última generación medida
    property var track: null      // { task, tStart, tLast, nMax }

    readonly property bool running: unitState === "active"
    readonly property string statusText: !running ? (unitState === "unknown" ? "Sin datos" : "Detenido")
        : !reachable ? "Iniciando…" : generating ? "Generando" : "Listo"
    readonly property color statusColor: !running ? "#6b7280" : !reachable ? "#f59e0b" : generating ? "#38bdf8" : "#22c55e"

    toolTipMainText: "Servidor LLM · " + statusText
    toolTipSubText: {
        var l = []
        if (modelName.length) l.push(modelName)
        if (generating) l.push(tps.toFixed(1) + " tok/s")
        else if (!isNaN(lastAvgTps)) l.push("Última generación: " + lastAvgTps.toFixed(1) + " tok/s")
        if (!isNaN(vramProc)) l.push("VRAM: " + Math.round(vramProc) + " MiB")
        return l.join("\n")
    }

    function localPath(url) {
        var s = url.toString()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        return s
    }
    readonly property string scriptPath: localPath(Qt.resolvedUrl("../code/status.sh"))

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function fmtBytes(b) {
        if (isNaN(b)) return "--"
        var g = b / (1024 * 1024 * 1024)
        return g >= 1 ? g.toFixed(1) + " GB" : Math.round(b / (1024 * 1024)) + " MB"
    }

    function fmtUptime(sec) {
        if (isNaN(sec) || sec < 0) return "--"
        var d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
        return d > 0 ? d + " d " + h + " h" : h > 0 ? h + " h " + m + " min" : m + " min"
    }

    // ---- Sistema (systemctl, nvidia-smi) ----
    function parseStatus(text) {
        var map = {}
        text.split("\n").forEach(function (line) {
            var i = line.indexOf("=")
            if (i > 0) map[line.substring(0, i)] = line.substring(i + 1).trim()
        })
        root.unitState = map.ACTIVE || "unknown"
        var mem = parseFloat(map.MEM)
        root.memBytes = isNaN(mem) ? NaN : mem
        root.sinceEpoch = map.SINCE ? parseFloat(map.SINCE) : NaN
        root.vramProc = map.VRAM_PROC !== undefined ? parseFloat(map.VRAM_PROC) : NaN
        root.vramUsed = map.VRAM_USED !== undefined ? parseFloat(map.VRAM_USED) : NaN
        root.vramTotal = map.VRAM_TOTAL !== undefined ? parseFloat(map.VRAM_TOTAL) : NaN
        if (!root.running) resetServerState()
    }

    function resetServerState() {
        reachable = false
        generating = false
        tps = 0
        track = null
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = data["stdout"] ? data["stdout"].toString() : ""
            if (sourceName.indexOf("status.sh") >= 0) {
                root.parseStatus(out)
            } else {
                // start/stop/restart: refrescar de inmediato
                root.busy = false
                root.refreshSystem()
                pollSlots()
            }
        }
    }

    property bool busy: false

    function refreshSystem() {
        exec.connectSource("sh " + shq(root.scriptPath) + " " + shq(Plasmoid.configuration.unitName))
    }

    function control(action) {
        busy = true
        exec.connectSource("systemctl --user " + action + " " + shq(Plasmoid.configuration.unitName))
    }

    // ---- Servidor HTTP (/slots, /props) ----
    function baseUrl() { return Plasmoid.configuration.serverUrl.replace(/\/+$/, "") }

    function getJson(path, ok, fail) {
        var xhr = new XMLHttpRequest()
        xhr.timeout = 1500
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try { ok(JSON.parse(xhr.responseText)); return } catch (e) {}
            }
            fail()
        }
        xhr.open("GET", baseUrl() + path)
        xhr.send()
    }

    function pollSlots() {
        if (!root.running) return
        getJson("/slots", function (slots) {
            reachable = true
            // llama-server reparte las peticiones entre varios slots: nos quedamos con
            // el que esté generando (el de la tarea más reciente).
            var active = null
            slots.forEach(function (sl) {
                if (sl.n_ctx > nCtx) nCtx = sl.n_ctx
                if (sl.is_processing && (!active || sl.id_task > active.id_task)) active = sl
            })
            generating = active !== null
            var now = Date.now()

            if (active) {
                var decoded = (active.next_token && active.next_token[0]) ? active.next_token[0].n_decoded : 0
                ctxUsed = active.n_prompt_tokens || 0  // ya incluye los tokens generados
                var key = active.id + ":" + active.id_task
                if (!track || track.key !== key)
                    track = { key: key, tStart: now, tLast: now, nMax: 0, prevN: 0, prevT: now }
                if (decoded > track.prevN && now > track.prevT) {
                    var inst = (decoded - track.prevN) / ((now - track.prevT) / 1000)
                    tps = tps > 0 ? tps * 0.5 + inst * 0.5 : inst
                    track.prevN = decoded
                    track.prevT = now
                    track.nMax = decoded
                    track.tLast = now
                }
            } else if (track) {
                if (track.nMax > 3 && track.tLast > track.tStart)
                    lastAvgTps = track.nMax / ((track.tLast - track.tStart) / 1000)
                track = null
                tps = 0
            }
        }, function () {
            reachable = false
            generating = false
        })
    }

    function fetchProps() {
        if (!root.running || modelName.length) return
        getJson("/props", function (p) {
            var path = p.model_path || p.model_alias || ""
            modelName = String(path).split("/").pop().replace(/\.gguf$/i, "")
        }, function () {})
    }

    onRunningChanged: if (!running) modelName = ""

    Timer {
        interval: Math.max(1000, Plasmoid.configuration.updateInterval)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.nowEpoch = Date.now() / 1000
            root.refreshSystem()
            root.fetchProps()
        }
    }

    Timer {
        interval: 500
        running: root.running
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollSlots()
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
            source: "applications-engineering"
            opacity: root.running ? 1 : 0.45
        }

        Rectangle {
            id: dot
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(8, parent.height * 0.34)
            height: width
            radius: width / 2
            color: root.statusColor
            border.color: "#66000000"
            SequentialAnimation on opacity {
                running: root.generating
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 400 }
                NumberAnimation { to: 1; duration: 400 }
                onStopped: dot.opacity = 1
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 15
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 18

        Rectangle {
            visible: !root.inPopup
            anchors.fill: parent
            radius: Kirigami.Units.largeSpacing
            color: "#66000000"
            border.color: "#33ffffff"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 1.5
            spacing: Kirigami.Units.largeSpacing

            // Estado
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    radius: 5
                    color: root.statusColor
                }
                GlassText {
                    text: root.statusText
                    font.bold: true
                    font.pixelSize: Kirigami.Units.gridUnit * 1.1
                }
                GlassText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: root.modelName
                    opacity: 0.7
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                }
            }

            // Velocidad
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                GlassText {
                    text: "TOKENS POR SEGUNDO"
                    opacity: 0.7
                    font.pixelSize: Kirigami.Units.gridUnit * 0.65
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    GlassText {
                        text: root.generating ? root.tps.toFixed(1)
                            : isNaN(root.lastAvgTps) ? "--" : root.lastAvgTps.toFixed(1)
                        color: root.generating ? "#38bdf8" : root.fg
                        font.bold: true
                        font.pixelSize: Kirigami.Units.gridUnit * 2.4
                    }
                    GlassText {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Kirigami.Units.smallSpacing * 1.5
                        text: root.generating ? "tok/s · en vivo" : "tok/s · última generación"
                        opacity: 0.7
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    }
                }
            }

            Bar {
                Layout.fillWidth: true
                textColor: root.fg
                trackColor: root.trackColor
                barColor: "#c084fc"
                label: "Contexto (última petición)"
                detail: root.nCtx > 0 ? root.ctxUsed + " / " + root.nCtx + " tokens" : "--"
                fraction: root.nCtx > 0 ? root.ctxUsed / root.nCtx : 0
            }

            Bar {
                Layout.fillWidth: true
                textColor: root.fg
                trackColor: root.trackColor
                barColor: "#76b900"
                label: "VRAM del servidor"
                detail: isNaN(root.vramProc) ? "--" : Math.round(root.vramProc) + " / " + Math.round(root.vramTotal) + " MiB"
                fraction: !isNaN(root.vramProc) && root.vramTotal > 0 ? root.vramProc / root.vramTotal : 0
            }

            RowLayout {
                Layout.fillWidth: true
                GlassText {
                    Layout.fillWidth: true
                    text: "RAM " + root.fmtBytes(root.memBytes)
                    opacity: 0.8
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                }
                GlassText {
                    text: "Activo " + (root.running ? root.fmtUptime(root.nowEpoch - root.sinceEpoch) : "--")
                    opacity: 0.8
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                }
            }

            Item { Layout.fillHeight: true }

            // Control del servicio
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    Layout.fillWidth: true
                    enabled: !root.busy
                    icon.name: root.running ? "media-playback-stop" : "media-playback-start"
                    text: root.running ? "Detener" : "Iniciar"
                    onClicked: root.control(root.running ? "stop" : "start")
                }
                QQC2.Button {
                    Layout.fillWidth: true
                    enabled: !root.busy && root.running
                    icon.name: "view-refresh"
                    text: "Reiniciar"
                    onClicked: root.control("restart")
                }
                QQC2.BusyIndicator {
                    visible: root.busy
                    running: root.busy
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.6
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                }
            }
        }
    }
}
