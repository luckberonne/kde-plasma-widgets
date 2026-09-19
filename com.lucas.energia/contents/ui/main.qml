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
    switchWidth: Kirigami.Units.gridUnit * 2
    switchHeight: Kirigami.Units.gridUnit * 4

    readonly property int historySize: 60

    // En un panel se muestra dentro del desplegable de Plasma (con su tema);
    // en el escritorio, con el estilo glass propio.
    readonly property bool inPopup: Plasmoid.location !== PlasmaCore.Types.Floating
    readonly property color fg: inPopup ? Kirigami.Theme.textColor : "white"
    readonly property color cardColor: inPopup ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "#26ffffff"
    readonly property color trackColor: inPopup ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15) : "#33ffffff"

    readonly property var profileInfo: ({
        "power-saver": { name: "Ahorro", icon: "battery-profile-powersave", color: "#22c55e" },
        "balanced": { name: "Equilibrado", icon: "battery-profile-balanced", color: "#38bdf8" },
        "performance": { name: "Rendimiento", icon: "battery-profile-performance", color: "#f97316" }
    })
    readonly property var profileOrder: ["power-saver", "balanced", "performance"]

    property bool hasBattery: false
    property real percent: 0
    property string status: ""        // Charging | Discharging | Full | Not charging
    property bool onAc: false
    property real watts: 0
    property real energyNow: 0        // µWh
    property real energyFull: 0
    property real energyDesign: 0
    property int cycles: -1
    property var wattHist: []
    property string profile: ""
    property var profiles: []
    property bool busy: false
    property string error: ""

    readonly property color accent: profileInfo[profile] ? profileInfo[profile].color : "#38bdf8"
    readonly property real health: energyDesign > 0 ? Math.min(100, energyFull / energyDesign * 100) : NaN

    readonly property string statusText: !hasBattery ? "Sin batería"
        : status === "Charging" ? "Cargando"
        : status === "Discharging" ? "Descargando"
        : status === "Full" ? "Completa"
        : onAc ? "Conectada" : status

    readonly property string timeText: {
        if (!hasBattery || watts < 0.5) return "--"
        var hours = -1
        if (status === "Discharging") hours = energyNow / (watts * 1e6)
        else if (status === "Charging") hours = (energyFull - energyNow) / (watts * 1e6)
        if (hours < 0) return "--"
        var m = Math.round(hours * 60)
        return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min"
    }

    toolTipMainText: hasBattery ? Math.round(percent) + "% · " + statusText : "Energía"
    toolTipSubText: (hasBattery ? watts.toFixed(1) + " W" + (timeText !== "--" ? " · " + timeText : "") + "\n" : "") +
                    (profileInfo[profile] ? "Perfil: " + profileInfo[profile].name : "")

    function localPath(url) {
        var s = url.toString()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        return s
    }
    readonly property string scriptPath: localPath(Qt.resolvedUrl("../code/energy.sh"))

    function batteryIcon() {
        var lvl = Math.max(0, Math.min(100, Math.round(percent / 10) * 10))
        var n = lvl < 100 ? (lvl < 10 ? "00" + lvl : "0" + lvl) : "100"
        return "battery-" + n + (status === "Charging" || (onAc && status !== "Discharging") ? "-charging" : "")
    }

    function parse(text) {
        var m = {}
        text.split("\n").forEach(function (line) {
            var i = line.indexOf("=")
            if (i > 0) m[line.substring(0, i)] = line.substring(i + 1).trim()
        })
        root.hasBattery = m.HAS_BAT === "1"
        root.onAc = m.AC === "1"
        if (root.hasBattery) {
            root.percent = parseFloat(m.capacity) || 0
            root.status = m.status || ""
            var w = parseFloat(m.power_now)
            if (isNaN(w) && m.current_now && m.voltage_now) w = Math.abs(parseFloat(m.current_now)) * parseFloat(m.voltage_now) / 1e6
            root.watts = isNaN(w) ? 0 : Math.abs(w) / 1e6
            root.energyNow = parseFloat(m.energy_now || m.charge_now) || 0
            root.energyFull = parseFloat(m.energy_full || m.charge_full) || 0
            root.energyDesign = parseFloat(m.energy_full_design || m.charge_full_design) || 0
            root.cycles = m.cycle_count !== undefined ? parseInt(m.cycle_count) : -1
            var h = root.wattHist.slice()
            h.push(root.watts)
            if (h.length > root.historySize) h.shift()
            root.wattHist = h
        }
        root.profile = m.PROFILE || ""
        root.profiles = m.PROFILES ? m.PROFILES.split(",").filter(x => x.length) : []
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = data["stdout"] ? data["stdout"].toString() : ""
            if (sourceName.indexOf("energy.sh") >= 0) {
                root.parse(out)
            } else {
                root.busy = false
                root.error = data["exit code"] !== 0 ? (out.trim().split("\n")[0] || "No se pudo cambiar el perfil") : ""
                root.refresh()
            }
        }
    }

    function refresh() { exec.connectSource("sh '" + root.scriptPath + "'") }

    function setProfile(name) {
        if (busy || name === profile) return
        busy = true
        exec.connectSource("powerprofilesctl set " + name + " 2>&1")
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
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property bool showText: Plasmoid.configuration.showPercentInPanel && root.hasBattery

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.preferredWidth: row.implicitWidth + Kirigami.Units.smallSpacing
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 2

            Kirigami.Icon {
                width: Math.min(compact.height, compact.width, Kirigami.Units.iconSizes.medium)
                height: width
                anchors.verticalCenter: parent.verticalCenter
                source: root.hasBattery ? root.batteryIcon() : "battery-profile-balanced"
            }
            Text {
                visible: compact.showText && !compact.vertical
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(root.percent) + "%"
                color: Kirigami.Theme.textColor
                font.pixelSize: Math.max(9, Math.min(compact.height * 0.42, 14))
                font.bold: true
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: Math.max(6, parent.height * 0.26)
            height: width
            radius: width / 2
            color: root.accent
            border.color: "#66000000"
            visible: root.profile.length > 0
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 20

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

            // Porcentaje y estado
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: root.hasBattery ? root.batteryIcon() : "battery-profile-balanced"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    GlassText {
                        text: root.hasBattery ? Math.round(root.percent) + "%" : "--"
                        font.bold: true
                        font.pixelSize: Kirigami.Units.gridUnit * 2.2
                    }
                    GlassText {
                        Layout.fillWidth: true
                        text: root.statusText + (root.timeText !== "--" ? " · " + root.timeText : "")
                        opacity: 0.75
                        font.pixelSize: Kirigami.Units.gridUnit * 0.8
                    }
                }
            }

            // Barra de carga
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: root.trackColor
                visible: root.hasBattery
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.percent / 100))
                    height: parent.height
                    radius: 4
                    color: root.percent <= 15 && root.status !== "Charging" ? "#ef4444" : root.accent
                    Behavior on width { NumberAnimation { duration: 250 } }
                }
            }

            // Datos
            GridLayout {
                Layout.fillWidth: true
                visible: root.hasBattery
                columns: 3
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: 0

                Repeater {
                    model: [
                        { label: "CONSUMO", value: root.watts.toFixed(1) + " W" },
                        { label: "SALUD", value: isNaN(root.health) ? "--" : Math.round(root.health) + "%" },
                        { label: "CICLOS", value: root.cycles >= 0 ? String(root.cycles) : "--" }
                    ]
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        GlassText {
                            Layout.fillWidth: true
                            text: modelData.label
                            opacity: 0.6
                            font.pixelSize: Kirigami.Units.gridUnit * 0.6
                        }
                        GlassText {
                            Layout.fillWidth: true
                            text: modelData.value
                            font.bold: true
                            font.pixelSize: Kirigami.Units.gridUnit * 1.1
                        }
                    }
                }
            }

            // Gráfico de consumo
            Canvas {
                id: graph
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: Plasmoid.configuration.showGraph && root.hasBattery
                readonly property var data: root.wattHist
                onDataChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var d = data
                    if (d.length < 2) return
                    var max = 5
                    for (var i = 0; i < d.length; i++) max = Math.max(max, d[i])
                    var step = width / (root.historySize - 1)
                    var x0 = width - (d.length - 1) * step
                    ctx.beginPath()
                    ctx.moveTo(x0, height - d[0] / max * (height - 2))
                    for (var j = 1; j < d.length; j++) ctx.lineTo(x0 + j * step, height - d[j] / max * (height - 2))
                    ctx.strokeStyle = root.accent
                    ctx.lineWidth = 2
                    ctx.lineJoin = "round"
                    ctx.stroke()
                    ctx.lineTo(width, height)
                    ctx.lineTo(x0, height)
                    ctx.closePath()
                    ctx.globalAlpha = 0.18
                    ctx.fillStyle = root.accent
                    ctx.fill()
                }
            }

            Item { Layout.fillHeight: true; visible: !graph.visible }

            // Perfiles de energía
            GlassText {
                visible: root.profiles.length > 0
                text: "PERFIL DE ENERGÍA"
                opacity: 0.6
                font.pixelSize: Kirigami.Units.gridUnit * 0.6
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.profiles.length > 0
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.profileOrder.filter(p => root.profiles.indexOf(p) >= 0)
                    delegate: Rectangle {
                        id: pbtn
                        readonly property var info: root.profileInfo[modelData]
                        readonly property bool active: root.profile === modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 3.2
                        radius: Kirigami.Units.mediumSpacing
                        color: active ? Qt.rgba(Qt.color(info.color).r, Qt.color(info.color).g, Qt.color(info.color).b, 0.35)
                                      : (pm.containsMouse ? root.cardColor : Qt.rgba(root.cardColor.r, root.cardColor.g, root.cardColor.b, root.cardColor.a * 0.6))
                        border.width: active ? 2 : 1
                        border.color: active ? info.color : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
                        opacity: root.busy ? 0.6 : 1

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                source: pbtn.info.icon
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            }
                            GlassText {
                                Layout.alignment: Qt.AlignHCenter
                                text: pbtn.info.name
                                font.bold: pbtn.active
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
                            }
                        }

                        MouseArea {
                            id: pm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setProfile(modelData)
                        }
                    }
                }
            }

            GlassText {
                Layout.fillWidth: true
                visible: root.error.length > 0
                text: "⚠ " + root.error
                color: "#f87171"
                font.pixelSize: Kirigami.Units.gridUnit * 0.7
            }

            GlassText {
                Layout.fillWidth: true
                visible: root.profiles.length === 0
                text: "power-profiles-daemon no está disponible"
                opacity: 0.6
                font.pixelSize: Kirigami.Units.gridUnit * 0.7
            }
        }
    }
}
