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

    readonly property string statusCmd: "tailscale status --json 2>&1"

    // En un panel se muestra dentro del desplegable de Plasma (con su tema);
    // en el escritorio, con el estilo glass propio.
    readonly property bool inPopup: Plasmoid.location !== PlasmaCore.Types.Floating
    readonly property color fg: inPopup ? Kirigami.Theme.textColor : "white"
    readonly property color cardColor: inPopup ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "#26ffffff"

    property string backend: "Unknown"   // Running | Stopped | NeedsLogin | Starting | NoState ...
    property string error: ""            // tailscale no disponible o sin permisos
    property string notice: ""           // mensaje temporal (copiado, errores de acción)
    property string authUrl: ""
    property string selfName: ""
    property string selfIp: ""
    property string selfDns: ""
    property string tailnet: ""
    property var peers: []
    property var health: []
    property bool busy: false

    readonly property bool connected: backend === "Running"
    readonly property int onlineCount: peers.filter(p => p.online).length
    readonly property var shownPeers: peers.filter(p => p.online || Plasmoid.configuration.showOffline)

    readonly property color statusColor: error.length ? "#6b7280"
        : connected ? "#22c55e"
        : (backend === "Stopped") ? "#6b7280" : "#f59e0b"
    readonly property string statusText: error.length ? "No disponible"
        : connected ? "Conectado"
        : backend === "Stopped" ? "Desconectado"
        : backend === "NeedsLogin" ? "Requiere inicio de sesión"
        : backend === "Starting" ? "Conectando…" : backend

    toolTipMainText: "Tailscale · " + statusText
    toolTipSubText: connected ? (selfName + " · " + selfIp + "\n" + onlineCount + " de " + peers.length + " dispositivos en línea") : error

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function osIcon(os) {
        switch (String(os).toLowerCase()) {
        case "linux": return "computer"
        case "windows": return "computer"
        case "android": case "ios": return "smartphone"
        case "macos": return "computer-laptop"
        default: return "network-server"
        }
    }

    function ago(iso) {
        var t = Date.parse(iso)
        if (isNaN(t) || t < 86400000) return "nunca visto"
        var s = Math.floor((Date.now() - t) / 1000)
        if (s < 90) return "hace un momento"
        var m = Math.floor(s / 60)
        if (m < 60) return "hace " + m + " min"
        var h = Math.floor(m / 60)
        if (h < 48) return "hace " + h + " h"
        return "hace " + Math.floor(h / 24) + " d"
    }

    function firstIPv4(ips) {
        for (var i = 0; i < ips.length; i++) if (ips[i].indexOf(":") < 0) return ips[i]
        return ips.length ? ips[0] : ""
    }

    function parseStatus(out) {
        var d
        try { d = JSON.parse(out) } catch (e) {
            root.error = out.trim().split("\n")[0] || "tailscale no responde"
            root.backend = "Unknown"
            root.peers = []
            return
        }
        root.error = ""
        root.backend = d.BackendState || "Unknown"
        root.authUrl = d.AuthURL || ""
        root.health = d.Health || []
        root.tailnet = d.CurrentTailnet ? (d.CurrentTailnet.Name || "") : ""
        var self = d.Self
        root.selfName = self ? self.HostName : ""
        root.selfIp = self ? firstIPv4(self.TailscaleIPs || []) : ""
        root.selfDns = self ? String(self.DNSName || "").replace(/\.$/, "") : ""

        var list = []
        var map = d.Peer || {}
        Object.keys(map).forEach(function (k) {
            var p = map[k]
            list.push({
                name: p.HostName, os: p.OS || "", ip: firstIPv4(p.TailscaleIPs || []),
                dns: String(p.DNSName || "").replace(/\.$/, ""),
                online: !!p.Online, lastSeen: p.LastSeen || "",
                exitNode: !!p.ExitNode, exitOption: !!p.ExitNodeOption
            })
        })
        list.sort(function (a, b) {
            if (a.online !== b.online) return a.online ? -1 : 1
            return a.name.localeCompare(b.name)
        })
        root.peers = list
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var out = data["stdout"] ? data["stdout"].toString() : ""
            if (sourceName === root.statusCmd) {
                root.parseStatus(out)
            } else {
                root.busy = false
                if (/denied|operator|access/i.test(out))
                    root.flash("Sin permiso. Ejecutá una vez: sudo tailscale set --operator=$USER", 12000)
                else if (data["exit code"] !== 0 && out.trim().length)
                    root.flash(out.trim().split("\n")[0], 8000)
                root.refresh()
            }
        }
    }

    function refresh() { exec.connectSource(root.statusCmd) }

    function toggle() {
        busy = true
        exec.connectSource("timeout 20 tailscale " + (connected ? "down" : "up") + " 2>&1")
    }

    function flash(msg, ms) {
        notice = msg
        noticeTimer.interval = ms || 2000
        noticeTimer.restart()
    }

    function copy(text, what) {
        clip.text = text
        clip.selectAll()
        clip.copy()
        flash("Copiado " + what + ": " + text, 2000)
    }

    TextEdit { id: clip; visible: false }

    Timer { id: noticeTimer; onTriggered: root.notice = "" }

    Timer {
        interval: Math.max(2000, Plasmoid.configuration.updateInterval)
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
            source: "network-vpn"
            opacity: root.connected ? 1 : 0.5
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(8, parent.height * 0.34)
            height: width
            radius: width / 2
            color: root.statusColor
            border.color: "#66000000"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
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

            // Encabezado: estado + interruptor
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Rectangle {
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    radius: 5
                    color: root.statusColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    GlassText {
                        Layout.fillWidth: true
                        text: "Tailscale · " + root.statusText
                        font.bold: true
                        font.pixelSize: Kirigami.Units.gridUnit * 1.1
                    }
                    GlassText {
                        Layout.fillWidth: true
                        visible: root.tailnet.length > 0
                        text: root.tailnet
                        opacity: 0.65
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    }
                }

                QQC2.BusyIndicator {
                    visible: root.busy
                    running: root.busy
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.6
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                }

                QQC2.Switch {
                    enabled: !root.busy && root.error.length === 0
                    checked: root.connected
                    onToggled: {
                        root.toggle()
                        checked = Qt.binding(() => root.connected)
                    }
                }

                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh()
                    QQC2.ToolTip.text: "Actualizar"
                    QQC2.ToolTip.visible: hovered
                }
            }

            // Este equipo
            Rectangle {
                Layout.fillWidth: true
                visible: root.connected
                height: selfRow.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.mediumSpacing
                color: root.cardColor

                RowLayout {
                    id: selfRow
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        source: "computer"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        GlassText {
                            Layout.fillWidth: true
                            text: root.selfName + "  (este equipo)"
                            font.bold: true
                        }
                        GlassText {
                            Layout.fillWidth: true
                            text: root.selfIp
                            color: root.inPopup ? Kirigami.Theme.highlightColor : "#7dd3fc"
                            font.pixelSize: Kirigami.Units.gridUnit * 0.75
                        }
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-copy"
                        onClicked: root.copy(root.selfIp, "IP")
                        QQC2.ToolTip.text: "Copiar IP"
                        QQC2.ToolTip.visible: hovered
                    }
                }
            }

            // Inicio de sesión pendiente
            QQC2.Button {
                Layout.fillWidth: true
                visible: root.authUrl.length > 0
                icon.name: "dialog-password"
                text: "Iniciar sesión en Tailscale"
                onClicked: Qt.openUrlExternally(root.authUrl)
            }

            // Mensaje vacío / error
            GlassText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.connected
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                opacity: 0.7
                text: root.error.length ? "⚠ " + root.error
                    : root.backend === "Stopped" ? "Tailscale está desconectado.\nActivá el interruptor para conectarte."
                    : ""
            }

            // Dispositivos
            GlassText {
                visible: root.connected
                text: "DISPOSITIVOS · " + root.onlineCount + " de " + root.peers.length + " en línea"
                opacity: 0.65
                font.pixelSize: Kirigami.Units.gridUnit * 0.65
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.connected
                clip: true
                spacing: Kirigami.Units.smallSpacing
                model: root.shownPeers
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                delegate: Rectangle {
                    id: card
                    width: list.width - Kirigami.Units.largeSpacing
                    height: row.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: Kirigami.Units.mediumSpacing
                    color: root.cardColor
                    opacity: modelData.online ? 1 : 0.55

                    RowLayout {
                        id: row
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: modelData.online ? "#22c55e" : "#6b7280"
                        }
                        Kirigami.Icon {
                            source: root.osIcon(modelData.os)
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            GlassText {
                                Layout.fillWidth: true
                                text: modelData.name + (modelData.exitNode ? "  · exit node" : "")
                                font.bold: true
                            }
                            GlassText {
                                Layout.fillWidth: true
                                text: modelData.ip + " · " + modelData.os +
                                      (modelData.online ? "" : " · " + root.ago(modelData.lastSeen))
                                opacity: 0.7
                                font.pixelSize: Kirigami.Units.gridUnit * 0.7
                            }
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-copy"
                            onClicked: root.copy(modelData.ip, "IP")
                            QQC2.ToolTip.text: "Copiar IP"
                            QQC2.ToolTip.visible: hovered
                        }
                        QQC2.ToolButton {
                            icon.name: "internet-services"
                            enabled: modelData.dns.length > 0
                            onClicked: root.copy(modelData.dns, "nombre")
                            QQC2.ToolTip.text: "Copiar nombre MagicDNS"
                            QQC2.ToolTip.visible: hovered
                        }
                    }
                }
            }

            // Avisos de salud / mensajes temporales
            GlassText {
                Layout.fillWidth: true
                visible: root.notice.length > 0
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                text: root.notice
                color: root.inPopup ? Kirigami.Theme.highlightColor : "#7dd3fc"
                font.pixelSize: Kirigami.Units.gridUnit * 0.7
            }
            GlassText {
                Layout.fillWidth: true
                visible: root.notice.length === 0 && root.health.length > 0
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                maximumLineCount: 2
                text: "⚠ " + root.health[0]
                color: "#f59e0b"
                font.pixelSize: Kirigami.Units.gridUnit * 0.65
            }
        }
    }
}
