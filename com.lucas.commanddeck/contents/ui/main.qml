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

    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 8

    // En un panel se muestra dentro del desplegable de Plasma (con su tema);
    // en el escritorio, con el estilo glass propio.
    readonly property bool inPopup: Plasmoid.location !== PlasmaCore.Types.Floating
    readonly property color fg: inPopup ? Kirigami.Theme.textColor : "white"

    readonly property var buttons: {
        try { return JSON.parse(Plasmoid.configuration.buttons) } catch (e) { return [] }
    }
    readonly property int columns: Math.max(1, Plasmoid.configuration.columns)
    readonly property int cell: Math.max(48, Plasmoid.configuration.buttonSize)
    readonly property int rows: Math.max(1, Math.ceil(buttons.length / columns))

    // Estado por botón: { status: "running" | "ok" | "fail", until: ms }
    property var states: ({})
    property string message: ""
    property bool messageIsError: false
    property int pendingConfirm: -1
    property int counter: 0
    property var running: ({})   // sourceName -> índice de botón

    toolTipMainText: "Botonera de comandos"
    toolTipSubText: buttons.length + " botones"

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function setState(i, status) {
        var s = Object.assign({}, states)
        s[i] = { status: status, until: Date.now() + 2500 }
        states = s
        if (status !== "running") clearTimer.restart()
    }

    function press(i) {
        var b = buttons[i]
        if (!b || !b.cmd || !b.cmd.trim().length) {
            message = "«" + (b ? b.name : "") + "» no tiene comando configurado"
            messageIsError = true
            msgTimer.restart()
            return
        }
        if (states[i] && states[i].status === "running") return
        if (b.confirm && pendingConfirm !== i) { pendingConfirm = i; return }
        pendingConfirm = -1
        run(i)
    }

    function run(i) {
        var b = buttons[i]
        var line
        if (b.terminal)
            line = "setsid -f konsole --hold -e sh -c " + shq(b.cmd) + " >/dev/null 2>&1"
        else if (b.app)
            line = "setsid -f sh -c " + shq(b.cmd) + " >/dev/null 2>&1"
        else
            line = "sh -c " + shq(b.cmd) + " 2>&1"
        // El sufijo hace único el nombre de la fuente aunque se repita el comando
        var source = line + " #" + (++counter)
        var r = Object.assign({}, running)
        r[source] = i
        running = r
        setState(i, "running")
        exec.connectSource(source)
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var i = root.running[sourceName]
            var r = Object.assign({}, root.running)
            delete r[sourceName]
            root.running = r
            if (i === undefined) return
            var code = data["exit code"]
            var out = data["stdout"] ? data["stdout"].toString().trim() : ""
            var name = root.buttons[i] ? root.buttons[i].name : ""
            var ok = code === 0
            root.setState(i, ok ? "ok" : "fail")
            var firstLine = out.split("\n")[0]
            root.message = ok ? (firstLine.length ? name + ": " + firstLine : "✓ " + name)
                              : "✗ " + name + " (código " + code + ")" + (firstLine.length ? ": " + firstLine : "")
            root.messageIsError = !ok
            msgTimer.restart()
        }
    }

    Timer { id: msgTimer; interval: 5000; onTriggered: root.message = "" }

    // Limpia los estados ok/fail una vez cumplido su tiempo de aviso
    Timer {
        id: clearTimer
        interval: 2600
        onTriggered: {
            var s = {}, now = Date.now()
            Object.keys(root.states).forEach(function (k) {
                var e = root.states[k]
                if (e.status === "running" || e.until > now) s[k] = e
            })
            root.states = s
        }
    }

    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium

        Kirigami.Icon {
            anchors.fill: parent
            source: "input-gaming"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        id: view

        readonly property int pad: Kirigami.Units.largeSpacing
        readonly property int gap: Kirigami.Units.smallSpacing * 1.5
        readonly property real gridW: root.columns * root.cell + (root.columns - 1) * gap
        readonly property real footerH: Kirigami.Units.gridUnit * 2
        readonly property real gridH: root.rows * root.cell + (root.rows - 1) * gap

        Layout.minimumWidth: gridW + pad * 2
        Layout.minimumHeight: gridH + pad * 2 + footerH
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight

        Rectangle {
            visible: !root.inPopup
            anchors.fill: parent
            radius: Kirigami.Units.largeSpacing
            color: "#66000000"
            border.color: "#33ffffff"
        }

        Grid {
            id: grid
            x: view.pad
            y: view.pad
            columns: root.columns
            spacing: view.gap

            Repeater {
                model: root.buttons

                delegate: Item {
                    id: btn
                    width: root.cell
                    height: root.cell

                    readonly property var b: modelData
                    readonly property color accent: b.color || "#38bdf8"
                    readonly property var st: root.states[index]
                    readonly property string status: st ? st.status : ""
                    readonly property bool confirming: root.pendingConfirm === index

                    Rectangle {
                        id: face
                        anchors.fill: parent
                        radius: Kirigami.Units.largeSpacing
                        scale: mouse.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        color: Qt.rgba(accent.r, accent.g, accent.b, mouse.pressed ? 0.5 : mouse.containsMouse ? 0.36 : 0.22)
                        border.width: btn.status === "ok" || btn.status === "fail" || btn.confirming ? 3 : 1
                        border.color: btn.status === "ok" ? "#22c55e"
                                    : btn.status === "fail" ? "#ef4444"
                                    : btn.confirming ? "#f59e0b"
                                    : Qt.rgba(accent.r, accent.g, accent.b, 0.65)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.smallSpacing * 2
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: root.cell * (Plasmoid.configuration.showLabels ? 0.42 : 0.55)
                                Layout.preferredHeight: Layout.preferredWidth
                                source: btn.status === "ok" ? "dialog-ok-apply"
                                      : btn.status === "fail" ? "dialog-error"
                                      : btn.confirming ? "dialog-question"
                                      : (b.icon || "system-run")
                                opacity: btn.status === "running" ? 0.35 : 1
                            }

                            Text {
                                visible: Plasmoid.configuration.showLabels
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: btn.confirming ? "¿Seguro?" : (b.name || "")
                                color: root.fg
                                elide: Text.ElideRight
                                font.pixelSize: Math.max(9, root.cell * 0.13)
                                font.bold: true
                                layer.enabled: !root.inPopup
                                layer.effect: DropShadow {
                                    verticalOffset: 1
                                    radius: 4
                                    samples: 9
                                    color: "#aa000000"
                                }
                            }
                        }

                        QQC2.BusyIndicator {
                            anchors.centerIn: parent
                            running: btn.status === "running"
                            visible: running
                            width: root.cell * 0.5
                            height: width
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.press(index)
                    }

                    QQC2.ToolTip.visible: mouse.containsMouse && (b.cmd || "").length > 0
                    QQC2.ToolTip.delay: 600
                    QQC2.ToolTip.text: (b.name || "") + "\n" + (b.cmd || "")
                }
            }
        }

        // Sin botones
        Text {
            visible: root.buttons.length === 0
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: root.fg
            opacity: 0.7
            text: "No hay botones.\nAgregalos desde la configuración del widget."
        }

        // Pie: confirmación o resultado
        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: view.footerH
            clip: true

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: view.pad
                anchors.rightMargin: view.pad
                anchors.bottomMargin: view.pad / 2
                spacing: Kirigami.Units.smallSpacing

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: root.pendingConfirm >= 0 ? "#f59e0b"
                         : root.messageIsError ? "#ef4444" : root.fg
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    text: root.pendingConfirm >= 0
                        ? "¿Ejecutar «" + (root.buttons[root.pendingConfirm] ? root.buttons[root.pendingConfirm].name : "") + "»?"
                        : root.message
                }
                QQC2.Button {
                    visible: root.pendingConfirm >= 0
                    text: "Sí"
                    onClicked: root.press(root.pendingConfirm)
                }
                QQC2.Button {
                    visible: root.pendingConfirm >= 0
                    text: "No"
                    onClicked: root.pendingConfirm = -1
                }
            }
        }
    }
}
