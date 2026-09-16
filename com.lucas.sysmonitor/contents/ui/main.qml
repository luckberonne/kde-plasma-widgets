import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    switchWidth: Kirigami.Units.gridUnit * 24
    switchHeight: Kirigami.Units.gridUnit * 8

    toolTipMainText: "Monitor del sistema"
    toolTipTextFormat: Text.RichText
    toolTipSubText: {
        var gpuLine = root.hasGpu
            ? Math.round(root.gpuPercent) + "% · " + (isNaN(root.gpuTemp) ? "--" : Math.round(root.gpuTemp) + "°C") + " · VRAM " + root.gpuMemUsedGB.toFixed(1) + "/" + root.gpuMemTotalGB.toFixed(0) + " GB"
            : "no disponible"
        var igpuLine = root.hasIgpu
            ? Math.round(root.igpuPercent) + "% · " + (isNaN(root.igpuTemp) ? "--" : Math.round(root.igpuTemp) + "°C")
            : "no disponible"
        return "<b>CPU</b>&nbsp;&nbsp;" + Math.round(root.cpuPercent) + "% · " + (isNaN(root.cpuTemp) ? "--" : Math.round(root.cpuTemp) + "°C") + "<br>" +
               "<b>RAM</b>&nbsp;" + root.ramUsedGB.toFixed(1) + "/" + root.ramTotalGB.toFixed(0) + " GB (" + Math.round(root.ramPercent) + "%)<br>" +
               "<b>GPU NVIDIA</b> (dedicada)&nbsp;" + gpuLine + "<br>" +
               "<b>GPU AMD</b> (integrada)&nbsp;" + igpuLine + "<br>" +
               "<b>Disco</b>&nbsp;" + root.diskUsedGB.toFixed(0) + "/" + root.diskTotalGB.toFixed(0) + " GB (" + Math.round(root.diskPercent) + "%)"
    }

    property var prevCpu: null
    property real cpuPercent: 0
    property real cpuTemp: NaN
    property real ramPercent: 0
    property real ramUsedGB: 0
    property real ramTotalGB: 0
    property bool hasGpu: false
    property real gpuPercent: 0
    property real gpuTemp: NaN
    property real gpuMemUsedGB: 0
    property real gpuMemTotalGB: 0
    property bool hasIgpu: false
    property real igpuPercent: 0
    property real igpuTemp: NaN
    property real diskPercent: 0
    property real diskUsedGB: 0
    property real diskTotalGB: 0

    function localPath(url) {
        var s = url.toString()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        return s
    }

    readonly property string scriptPath: localPath(Qt.resolvedUrl("../code/stats.sh"))

    function parseStats(text) {
        var lines = text.split("\n")
        var map = {}
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var idx = line.indexOf("=")
            if (idx < 0) continue
            map[line.substring(0, idx)] = line.substring(idx + 1)
        }

        if (map.CPU_RAW) {
            var f = map.CPU_RAW.trim().split(/\s+/).map(Number)
            var idle = f[3] + f[4]
            var nonIdle = f[0] + f[1] + f[2] + f[5] + f[6] + f[7]
            var total = idle + nonIdle
            if (root.prevCpu) {
                var totald = total - root.prevCpu.total
                var idled = idle - root.prevCpu.idle
                if (totald > 0) {
                    root.cpuPercent = Math.max(0, Math.min(100, (totald - idled) / totald * 100))
                }
            }
            root.prevCpu = { idle: idle, total: total }
        }

        if (map.CPU_TEMP !== undefined) root.cpuTemp = parseFloat(map.CPU_TEMP)

        if (map.RAM_TOTAL_KB !== undefined && map.RAM_AVAIL_KB !== undefined) {
            var totalKb = parseFloat(map.RAM_TOTAL_KB)
            var availKb = parseFloat(map.RAM_AVAIL_KB)
            var usedKb = Math.max(0, totalKb - availKb)
            root.ramPercent = totalKb > 0 ? (usedKb / totalKb * 100) : 0
            root.ramUsedGB = usedKb / (1024 * 1024)
            root.ramTotalGB = totalKb / (1024 * 1024)
        }

        if (map.DISK_TOTAL !== undefined && map.DISK_USED !== undefined) {
            var dTotal = parseFloat(map.DISK_TOTAL)
            var dUsed = parseFloat(map.DISK_USED)
            root.diskPercent = dTotal > 0 ? (dUsed / dTotal * 100) : 0
            root.diskUsedGB = dUsed / (1024 * 1024 * 1024)
            root.diskTotalGB = dTotal / (1024 * 1024 * 1024)
        }

        if (map.GPU_UTIL !== undefined) {
            root.hasGpu = true
            root.gpuPercent = parseFloat(map.GPU_UTIL)
            root.gpuTemp = parseFloat(map.GPU_TEMP)
            root.gpuMemUsedGB = parseFloat(map.GPU_MEM_USED) / 1024
            root.gpuMemTotalGB = parseFloat(map.GPU_MEM_TOTAL) / 1024
        }

        if (map.IGPU_UTIL !== undefined) {
            root.hasIgpu = true
            root.igpuPercent = parseFloat(map.IGPU_UTIL)
        }
        if (map.IGPU_TEMP !== undefined) {
            root.hasIgpu = true
            root.igpuTemp = parseFloat(map.IGPU_TEMP)
        }
    }

    Plasma5Support.DataSource {
        id: statsSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = data["stdout"] ? data["stdout"].toString() : ""
            if (out.length) root.parseStats(out)
        }
    }

    function refresh() {
        var diskPath = (Plasmoid.configuration.diskPath && Plasmoid.configuration.diskPath.length) ? Plasmoid.configuration.diskPath : "/"
        statsSource.connectSource("sh " + JSON.stringify(root.scriptPath) + " " + JSON.stringify(diskPath))
    }

    Timer {
        interval: Math.max(1000, Plasmoid.configuration.updateInterval)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: Item {
        id: compact

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real dotSize: Math.max(12, Math.min(vertical ? compact.width * 0.8 : compact.height * 0.8, 22))

        Layout.minimumWidth: vertical ? dotSize + Kirigami.Units.smallSpacing : compactLayout.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: vertical ? compactLayout.implicitHeight + Kirigami.Units.smallSpacing * 2 : dotSize + Kirigami.Units.smallSpacing
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }

        GridLayout {
            id: compactLayout
            anchors.centerIn: parent
            columns: compact.vertical ? 1 : 5
            rowSpacing: 3
            columnSpacing: 3

            Gauge {
                Layout.preferredWidth: compact.dotSize
                Layout.preferredHeight: compact.dotSize
                ringWidth: Math.max(2, compact.dotSize * 0.16)
                value: root.cpuPercent
                valueColor: "#7dd3fc"
            }
            Gauge {
                Layout.preferredWidth: compact.dotSize
                Layout.preferredHeight: compact.dotSize
                ringWidth: Math.max(2, compact.dotSize * 0.16)
                value: root.ramPercent
                valueColor: "#c084fc"
            }
            Gauge {
                Layout.preferredWidth: compact.dotSize
                Layout.preferredHeight: compact.dotSize
                ringWidth: Math.max(2, compact.dotSize * 0.16)
                value: root.hasGpu ? root.gpuPercent : 0
                valueColor: "#76b900"
            }
            Gauge {
                Layout.preferredWidth: compact.dotSize
                Layout.preferredHeight: compact.dotSize
                ringWidth: Math.max(2, compact.dotSize * 0.16)
                value: root.hasIgpu ? root.igpuPercent : 0
                valueColor: "#ef4444"
            }
            Gauge {
                Layout.preferredWidth: compact.dotSize
                Layout.preferredHeight: compact.dotSize
                ringWidth: Math.max(2, compact.dotSize * 0.16)
                value: root.diskPercent
                valueColor: "#2dd4bf"
            }
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 8
        Layout.preferredWidth: Kirigami.Units.gridUnit * 36
        Layout.preferredHeight: Kirigami.Units.gridUnit * 11

        readonly property real gaugeSize: Math.max(48, Math.min(view.height * 0.62, view.width / 6.4))

        RowLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            MetricColumn {
                value: root.cpuPercent
                accentColor: "#7dd3fc"
                label: "CPU"
                detail: isNaN(root.cpuTemp) ? "--" : Math.round(root.cpuTemp) + "°C"
                gaugeSize: view.gaugeSize
            }

            MetricColumn {
                value: root.ramPercent
                accentColor: "#c084fc"
                label: "RAM"
                detail: root.ramUsedGB.toFixed(1) + "/" + root.ramTotalGB.toFixed(0) + " GB"
                gaugeSize: view.gaugeSize
            }

            MetricColumn {
                value: root.hasGpu ? root.gpuPercent : 0
                accentColor: "#76b900"
                label: "NVIDIA"
                detail: root.hasGpu ? (isNaN(root.gpuTemp) ? "--" : Math.round(root.gpuTemp) + "°C") : "N/D"
                gaugeSize: view.gaugeSize
            }

            MetricColumn {
                value: root.hasIgpu ? root.igpuPercent : 0
                accentColor: "#ef4444"
                label: "AMD"
                detail: root.hasIgpu ? (isNaN(root.igpuTemp) ? "--" : Math.round(root.igpuTemp) + "°C") : "N/D"
                gaugeSize: view.gaugeSize
            }

            MetricColumn {
                value: root.diskPercent
                accentColor: "#2dd4bf"
                label: "DISCO"
                detail: root.diskUsedGB.toFixed(0) + "/" + root.diskTotalGB.toFixed(0) + " GB"
                gaugeSize: view.gaugeSize
            }
        }
    }
}
