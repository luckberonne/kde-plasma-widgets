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


    readonly property string listCmd: "docker ps -a --format '{{json .}}' 2>&1"

    property var containers: []
    property string error: ""
    property string logsFor: ""
    property string logsText: ""
    property var busyNames: ({})

    // En un panel se muestra dentro del desplegable de Plasma (con su propio fondo y tema);
    // en el escritorio, con el estilo glass propio.
    readonly property bool inPopup: Plasmoid.location !== PlasmaCore.Types.Floating
    readonly property color fg: inPopup ? Kirigami.Theme.textColor : "white"
    readonly property color cardColor: inPopup ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "#26ffffff"
    readonly property color logBg: inPopup ? Qt.rgba(0, 0, 0, 0.18) : "#66000000"

    readonly property int runningCount: containers.filter(c => c.state === "running").length
    readonly property var visible_: containers.filter(c => c.state === "running" || Plasmoid.configuration.showStopped)

    toolTipMainText: "Docker"
    toolTipSubText: error.length ? error : (runningCount + " en ejecución de " + containers.length)

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function cleanPorts(p) {
        return p.split(", ").filter(x => x.indexOf("[::]") !== 0).join(", ")
    }

    // Puertos publicados que probablemente sean web (front/API): se excluyen
    // los de bases de datos, colas, SSH, etc.
    readonly property var nonWebPorts: [21, 22, 25, 53, 1433, 1521, 2181, 3306, 5432, 5672, 6379, 9092, 9042, 11211, 27017, 26257, 5671, 1883, 8883]

    function webPorts(p) {
        var res = []
        p.split(", ").forEach(function (x) {
            var m = x.match(/:(\d+)->\d+\/tcp$/)
            if (!m) return
            var port = parseInt(m[1])
            if (nonWebPorts.indexOf(port) < 0 && res.indexOf(port) < 0) res.push(port)
        })
        return res
    }

    function parseList(out) {
        var list = []
        var err = ""
        out.split("\n").forEach(function (line) {
            line = line.trim()
            if (!line.length) return
            if (line.charAt(0) !== "{") { err = line; return }
            try {
                var o = JSON.parse(line)
                list.push({
                    name: o.Names, image: o.Image, state: o.State,
                    status: o.Status, ports: cleanPorts(o.Ports || ""),
                    web: webPorts(cleanPorts(o.Ports || ""))
                })
            } catch (e) {}
        })
        list.sort(function (a, b) {
            var ra = a.state === "running" ? 0 : 1, rb = b.state === "running" ? 0 : 1
            return ra !== rb ? ra - rb : a.name.localeCompare(b.name)
        })
        root.error = list.length ? "" : err
        root.containers = list
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = data["stdout"] ? data["stdout"].toString() : ""
            if (sourceName === root.listCmd) {
                root.parseList(out)
            } else if (sourceName.indexOf("docker logs") === 0) {
                root.logsText = out.length ? out : "(sin salida)"
            } else {
                // acción sobre un contenedor: liberar el estado ocupado y refrescar
                var m = sourceName.match(/^docker \w+ '(.*)'$/)
                if (m) {
                    var b = Object.assign({}, root.busyNames)
                    delete b[m[1].replace(/'\\''/g, "'")]
                    root.busyNames = b
                }
                root.refresh()
            }
        }
    }

    function refresh() {
        exec.connectSource(root.listCmd)
        if (root.logsFor.length) fetchLogs()
    }

    function fetchLogs() {
        exec.connectSource("docker logs --tail " + Plasmoid.configuration.logLines + " " + shq(root.logsFor) + " 2>&1")
    }

    function act(action, name) {
        var b = Object.assign({}, root.busyNames)
        b[name] = true
        root.busyNames = b
        exec.connectSource("docker " + action + " " + shq(name))
    }

    function openLogs(name) {
        root.logsText = "Cargando…"
        root.logsFor = name
        fetchLogs()
    }

    Timer {
        interval: Math.max(1000, Plasmoid.configuration.updateInterval)
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
            source: "yast-docker"
            opacity: root.error.length ? 0.4 : 1
        }

        Rectangle {
            visible: root.runningCount > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(height, badge.implicitWidth + 6)
            height: Math.max(12, parent.height * 0.42)
            radius: height / 2
            color: "#22c55e"
            Text {
                id: badge
                anchors.centerIn: parent
                text: root.runningCount
                color: "white"
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

        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 22

        TextEdit { id: clip; visible: false }

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

            // Encabezado
            RowLayout {
                Layout.fillWidth: true

                QQC2.ToolButton {
                    visible: root.logsFor.length > 0
                    icon.name: "go-previous"
                    onClicked: root.logsFor = ""
                }

                GlassText {
                    Layout.fillWidth: true
                    font.bold: true
                    font.pixelSize: Kirigami.Units.gridUnit * 1.1
                    text: root.logsFor.length ? "Logs · " + root.logsFor
                                              : "Docker · " + root.runningCount + "/" + root.containers.length + " activos"
                }

                QQC2.ToolButton {
                    visible: root.logsFor.length > 0
                    icon.name: "edit-copy"
                    onClicked: {
                        clip.text = root.logsText
                        clip.selectAll()
                        clip.copy()
                    }
                    QQC2.ToolTip.text: "Copiar logs"
                    QQC2.ToolTip.visible: hovered
                }

                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh()
                    QQC2.ToolTip.text: "Actualizar"
                    QQC2.ToolTip.visible: hovered
                }
            }

            // Mensaje de error / vacío
            GlassText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.logsFor.length === 0 && root.visible_.length === 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                opacity: 0.7
                text: root.error.length ? "⚠ " + root.error : "No hay contenedores"
            }

            // Lista de contenedores
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.logsFor.length === 0 && root.visible_.length > 0
                clip: true
                spacing: Kirigami.Units.smallSpacing
                model: root.visible_
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                delegate: Rectangle {
                    id: card
                    width: list.width - Kirigami.Units.largeSpacing
                    height: cardRow.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: Kirigami.Units.mediumSpacing
                    color: root.cardColor

                    readonly property var c: modelData
                    readonly property bool running: c.state === "running"
                    readonly property bool busy: !!root.busyNames[c.name]
                    readonly property bool unhealthy: c.status.indexOf("unhealthy") >= 0

                    RowLayout {
                        id: cardRow
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Rectangle {
                            Layout.preferredWidth: 10
                            Layout.preferredHeight: 10
                            radius: 5
                            color: card.unhealthy ? "#f59e0b"
                                 : card.running ? "#22c55e"
                                 : c.state === "paused" ? "#f59e0b" : "#6b7280"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            GlassText {
                                Layout.fillWidth: true
                                text: c.name
                                font.bold: true
                            }
                            GlassText {
                                Layout.fillWidth: true
                                text: c.image + " · " + c.status
                                opacity: 0.7
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
                            }
                            GlassText {
                                Layout.fillWidth: true
                                visible: c.ports.length > 0
                                text: c.ports
                                color: root.inPopup ? Kirigami.Theme.highlightColor : "#7dd3fc"
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
                            }
                        }

                        QQC2.BusyIndicator {
                            visible: card.busy
                            running: card.busy
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.6
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                        }

                        RowLayout {
                            visible: !card.busy
                            spacing: 0

                            Repeater {
                                model: card.running ? c.web : []
                                QQC2.ToolButton {
                                    icon.name: "internet-web-browser"
                                    text: c.web.length > 1 ? modelData : ""
                                    onClicked: Qt.openUrlExternally("http://localhost:" + modelData)
                                    QQC2.ToolTip.text: "Abrir http://localhost:" + modelData
                                    QQC2.ToolTip.visible: hovered
                                }
                            }
                            QQC2.ToolButton {
                                icon.name: card.running ? "media-playback-stop" : "media-playback-start"
                                onClicked: root.act(card.running ? "stop" : "start", c.name)
                                QQC2.ToolTip.text: card.running ? "Detener" : "Iniciar"
                                QQC2.ToolTip.visible: hovered
                            }
                            QQC2.ToolButton {
                                enabled: card.running
                                icon.name: "view-refresh"
                                onClicked: root.act("restart", c.name)
                                QQC2.ToolTip.text: "Reiniciar"
                                QQC2.ToolTip.visible: hovered
                            }
                            QQC2.ToolButton {
                                icon.name: "text-x-log"
                                onClicked: root.openLogs(c.name)
                                QQC2.ToolTip.text: "Ver logs"
                                QQC2.ToolTip.visible: hovered
                            }
                        }
                    }
                }
            }

            // Vista de logs
            QQC2.ScrollView {
                id: logView
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.logsFor.length > 0

                QQC2.TextArea {
                    id: logArea
                    readOnly: true
                    text: root.logsText
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    color: root.fg
                    background: Rectangle { color: root.logBg; radius: Kirigami.Units.mediumSpacing }
                    onTextChanged: cursorPosition = length
                }
            }
        }
    }
}
