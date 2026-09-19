import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Umbrales bajos: en el escritorio siempre se ve la botonera completa; solo en un
    // panel (donde el widget mide apenas un icono) se usa el icono con desplegable.
    switchWidth: Kirigami.Units.gridUnit * 4
    switchHeight: Kirigami.Units.gridUnit * 4


    readonly property var buttons: {
        try { return JSON.parse(Plasmoid.configuration.buttons) } catch (e) { return [] }
    }
    readonly property int columns: Math.max(1, Plasmoid.configuration.columns)
    readonly property int cell: Math.max(48, Plasmoid.configuration.buttonSize)
    readonly property int rows: Math.max(Math.max(1, Plasmoid.configuration.rows), Math.ceil(buttons.length / columns))
    readonly property int slots: columns * rows

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

        readonly property int bodyPad: Math.round(root.cell * 0.16)
        readonly property int gap: Math.round(root.cell * 0.1)
        readonly property real gridW: root.columns * root.cell + (root.columns - 1) * gap
        readonly property real gridH: root.rows * root.cell + (root.rows - 1) * gap
        readonly property real footerH: Kirigami.Units.gridUnit * 1.8

        Layout.minimumWidth: gridW + bodyPad * 2
        Layout.minimumHeight: gridH + bodyPad * 2 + footerH
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight

        // Carcasa del dispositivo
        Rectangle {
            id: body
            anchors.fill: parent
            radius: root.cell * 0.28
            gradient: Gradient {
                GradientStop { position: 0; color: "#1b1b20" }
                GradientStop { position: 1; color: "#0b0b0e" }
            }
            border.width: 1
            border.color: "#33ffffff"
        }

        Grid {
            id: grid
            x: view.bodyPad
            y: view.bodyPad
            columns: root.columns
            spacing: view.gap

            Repeater {
                model: root.slots

                delegate: Item {
                    id: btn
                    width: root.cell
                    height: root.cell

                    readonly property var b: index < root.buttons.length ? root.buttons[index] : null
                    readonly property bool empty: b === null
                    readonly property color accent: b && b.color ? b.color : "#38bdf8"
                    readonly property var st: root.states[index]
                    readonly property string status: st ? st.status : ""
                    readonly property bool confirming: root.pendingConfirm === index

                    // Tecla
                    Rectangle {
                        id: key
                        anchors.fill: parent
                        radius: root.cell * 0.14
                        scale: mouse.pressed && !btn.empty ? 0.93 : 1
                        Behavior on scale { NumberAnimation { duration: 80 } }
                        color: "#121216"
                        border.width: btn.status === "ok" || btn.status === "fail" || btn.confirming ? 3 : 1
                        border.color: btn.status === "ok" ? "#22c55e"
                                    : btn.status === "fail" ? "#ef4444"
                                    : btn.confirming ? "#f59e0b"
                                    : btn.empty ? "#1f1f25" : "#3a3a44"

                        // Pantalla de la tecla: degradado con el color del botón
                        Rectangle {
                            visible: !btn.empty
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: parent.radius - 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, mouse.containsMouse ? 0.62 : 0.5) }
                                GradientStop { position: 1; color: Qt.rgba(btn.accent.r * 0.5, btn.accent.g * 0.5, btn.accent.b * 0.5, mouse.containsMouse ? 0.5 : 0.36) }
                            }
                        }

                        // Brillo superior
                        Rectangle {
                            visible: !btn.empty
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 3
                            height: parent.height * 0.42
                            radius: parent.radius - 3
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#22ffffff" }
                                GradientStop { position: 1; color: "#00ffffff" }
                            }
                        }

                        // Ranura vacía: "+" tenue
                        Text {
                            visible: btn.empty
                            anchors.centerIn: parent
                            text: "+"
                            color: "#2a2a32"
                            font.pixelSize: root.cell * 0.4
                            opacity: mouse.containsMouse ? 1 : 0.6
                        }

                        ColumnLayout {
                            visible: !btn.empty
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.smallSpacing * 2
                            spacing: Math.round(root.cell * 0.04)

                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: root.cell * (Plasmoid.configuration.showLabels ? 0.44 : 0.58)
                                Layout.preferredHeight: Layout.preferredWidth
                                source: btn.status === "ok" ? "dialog-ok-apply"
                                      : btn.status === "fail" ? "dialog-error"
                                      : btn.confirming ? "dialog-question"
                                      : (btn.b && btn.b.icon ? btn.b.icon : "system-run")
                                opacity: btn.status === "running" ? 0.3 : 1
                            }

                            Text {
                                visible: Plasmoid.configuration.showLabels
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: btn.confirming ? "¿Seguro?" : (btn.b ? btn.b.name : "")
                                color: "white"
                                elide: Text.ElideRight
                                font.pixelSize: Math.max(9, root.cell * 0.13)
                                font.bold: true
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
                        onClicked: {
                            if (btn.empty) Plasmoid.internalAction("configure").trigger()
                            else root.press(index)
                        }
                    }

                    QQC2.ToolTip.visible: mouse.containsMouse
                    QQC2.ToolTip.delay: 600
                    QQC2.ToolTip.text: btn.empty ? "Añadir un botón"
                        : (btn.b.name || "") + ((btn.b.cmd || "").length ? "\n" + btn.b.cmd : "")
                }
            }
        }

        // Pie: confirmación o resultado (siempre reserva su espacio)
        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: view.footerH

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: view.bodyPad
                anchors.rightMargin: view.bodyPad
                anchors.bottomMargin: view.bodyPad * 0.5
                spacing: Kirigami.Units.smallSpacing

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: root.pendingConfirm >= 0 ? "#f59e0b"
                         : root.messageIsError ? "#f87171" : "#cbd5e1"
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
