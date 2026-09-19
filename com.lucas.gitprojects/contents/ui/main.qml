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

    function needsAttention(r) { return r.changes > 0 || r.ahead > 0 }

    readonly property int attentionCount: repos.filter(needsAttention).length
    readonly property var shownRepos: Plasmoid.configuration.onlyAttention ? repos.filter(needsAttention) : repos

    toolTipMainText: "Proyectos Git"
    toolTipSubText: error.length ? error
        : repos.length + " repositorios" + (attentionCount ? " · " + attentionCount + " con novedades" : " · todo al día")

    function localPath(url) {
        var s = url.toString()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        return s
    }
    readonly property string scriptPath: localPath(Qt.resolvedUrl("../code/repos.sh"))

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
            if (f[0] !== "REPO" || f.length < 10) return
            list.push({
                name: f[1], path: f[2], branch: f[3], changes: parseInt(f[4]) || 0,
                ahead: parseInt(f[5]) || 0, behind: parseInt(f[6]) || 0, hasUpstream: f[7] === "1",
                ts: parseInt(f[8]) || 0, subject: f.slice(9).join(" ")
            })
        })
        list.sort(function (a, b) {
            var na = root.needsAttention(a) ? 0 : 1, nb = root.needsAttention(b) ? 0 : 1
            return na !== nb ? na - nb : b.ts - a.ts
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
            if (sourceName.indexOf("repos.sh") >= 0)
                root.parse(data["stdout"] ? data["stdout"].toString() : "")
        }
    }

    function refresh() {
        exec.connectSource("sh " + shq(root.scriptPath) + " " + shq(Plasmoid.configuration.rootPath) + " " + Plasmoid.configuration.searchDepth)
    }

    function launch(cmd) {
        // setsid -f: la aplicación queda independiente del widget
        exec.connectSource("setsid -f " + cmd + " >/dev/null 2>&1 #" + Date.now())
    }

    function openTerminal(path) { launch("konsole --workdir " + shq(path)) }
    function openEditor(path) { launch((Plasmoid.configuration.editorCommand || "code") + " " + shq(path)) }
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

        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
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
                    text: "Proyectos · " + root.repos.length +
                          (root.attentionCount ? "  (" + root.attentionCount + " con novedades)" : "  · al día")
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
                text: root.error.length ? "⚠ " + root.error : "Todo al día ✓"
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
                    height: cardRow.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: Kirigami.Units.mediumSpacing
                    color: root.cardColor

                    readonly property var r: modelData
                    readonly property color dot: r.changes > 0 ? "#f59e0b" : r.ahead > 0 ? "#38bdf8" : "#22c55e"

                    RowLayout {
                        id: cardRow
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Rectangle {
                            Layout.preferredWidth: 10
                            Layout.preferredHeight: 10
                            radius: 5
                            color: card.dot
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                GlassText {
                                    text: r.name
                                    font.bold: true
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
                        }

                        RowLayout {
                            spacing: 0
                            QQC2.ToolButton {
                                icon.name: "utilities-terminal"
                                onClicked: root.openTerminal(r.path)
                                QQC2.ToolTip.text: "Abrir terminal aquí"
                                QQC2.ToolTip.visible: hovered
                            }
                            QQC2.ToolButton {
                                icon.name: "document-edit"
                                onClicked: root.openEditor(r.path)
                                QQC2.ToolTip.text: "Abrir en el editor"
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
