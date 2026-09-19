import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 5

    readonly property int historySize: 60
    readonly property color downColor: "#7dd3fc"
    readonly property color upColor: "#f9a8d4"

    property string iface: ""
    property var prev: null
    property real downBps: 0
    property real upBps: 0
    property var downHist: []
    property var upHist: []

    toolTipMainText: "Velocidad de red"
    toolTipSubText: (iface.length ? iface + "\n" : "") +
                    "↓ " + formatSpeed(downBps) + "\n↑ " + formatSpeed(upBps)

    function formatSpeed(bps) {
        var units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var i = 0
        while (bps >= 1024 && i < units.length - 1) { bps /= 1024; i++ }
        return (i === 0 ? Math.round(bps) : bps.toFixed(bps < 10 ? 2 : 1)) + " " + units[i]
    }

    function localPath(url) {
        var s = url.toString()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        return s
    }

    readonly property string scriptPath: localPath(Qt.resolvedUrl("../code/net.sh"))

    function push(arr, v) {
        var a = arr.slice()
        a.push(v)
        if (a.length > root.historySize) a.shift()
        return a
    }

    function parse(text) {
        var map = {}
        text.split("\n").forEach(function (line) {
            var i = line.indexOf("=")
            if (i > 0) map[line.substring(0, i)] = line.substring(i + 1).trim()
        })
        root.iface = map.IFACE || ""
        if (map.RX === undefined || map.TX === undefined) return
        var now = Date.now()
        var rx = parseFloat(map.RX), tx = parseFloat(map.TX)
        if (root.prev && root.prev.iface === root.iface && now > root.prev.t) {
            var dt = (now - root.prev.t) / 1000
            root.downBps = Math.max(0, (rx - root.prev.rx) / dt)
            root.upBps = Math.max(0, (tx - root.prev.tx) / dt)
            root.downHist = push(root.downHist, root.downBps)
            root.upHist = push(root.upHist, root.upBps)
        }
        root.prev = { rx: rx, tx: tx, t: now, iface: root.iface }
    }

    Plasma5Support.DataSource {
        id: netSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = data["stdout"] ? data["stdout"].toString() : ""
            if (out.length) root.parse(out)
        }
    }

    Timer {
        interval: Math.max(500, Plasmoid.configuration.updateInterval)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: netSource.connectSource("sh " + JSON.stringify(root.scriptPath) + " " +
                                             JSON.stringify(Plasmoid.configuration.interfaceName || ""))
    }

    component SpeedText: Text {
        color: "white"
        font.bold: true
        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 1
            radius: 6
            samples: 13
            color: "#cc000000"
        }
    }

    component Graph: Canvas {
        id: cv
        property var down: []
        property var up: []
        onDownChanged: requestPaint()
        onUpChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function line(ctx, data, max, color) {
            if (data.length < 2) return
            var step = width / (root.historySize - 1)
            var x0 = width - (data.length - 1) * step
            ctx.beginPath()
            ctx.moveTo(x0, height - data[0] / max * (height - 2))
            for (var i = 1; i < data.length; i++)
                ctx.lineTo(x0 + i * step, height - data[i] / max * (height - 2))
            ctx.strokeStyle = color
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.stroke()
            ctx.lineTo(width, height)
            ctx.lineTo(x0, height)
            ctx.closePath()
            ctx.globalAlpha = 0.18
            ctx.fillStyle = color
            ctx.fill()
            ctx.globalAlpha = 1
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var max = 1024
            for (var i = 0; i < down.length; i++) max = Math.max(max, down[i])
            for (var j = 0; j < up.length; j++) max = Math.max(max, up[j])
            line(ctx, down, max, root.downColor)
            line(ctx, up, max, root.upColor)
        }
    }

    compactRepresentation: Item {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

        Layout.minimumWidth: vertical ? Kirigami.Units.gridUnit * 3 : label.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }

        SpeedText {
            id: label
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Math.max(9, Math.min(compact.height * 0.36, 14))
            textFormat: Text.RichText
            text: "<span style='color:" + root.downColor + "'>↓</span> " + root.formatSpeed(root.downBps) +
                  "<br><span style='color:" + root.upColor + "'>↑</span> " + root.formatSpeed(root.upBps)
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 5
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 9

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    SpeedText {
                        text: "↓ BAJADA"
                        color: root.downColor
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    }
                    SpeedText {
                        text: root.formatSpeed(root.downBps)
                        font.pixelSize: Kirigami.Units.gridUnit * 1.6
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    SpeedText {
                        Layout.alignment: Qt.AlignRight
                        text: "↑ SUBIDA"
                        color: root.upColor
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    }
                    SpeedText {
                        Layout.alignment: Qt.AlignRight
                        text: root.formatSpeed(root.upBps)
                        font.pixelSize: Kirigami.Units.gridUnit * 1.6
                    }
                }
            }

            Graph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Plasmoid.configuration.showGraph
                down: root.downHist
                up: root.upHist
            }

            SpeedText {
                Layout.alignment: Qt.AlignHCenter
                text: root.iface.length ? root.iface : "sin conexión"
                opacity: 0.7
                font.bold: false
                font.pixelSize: Kirigami.Units.gridUnit * 0.65
            }
        }
    }
}
