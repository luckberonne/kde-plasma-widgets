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

    // Umbrales bajos: en el escritorio siempre se ve la botonera completa; solo en un
    // panel (donde el widget mide apenas un icono) se usa el icono con desplegable.
    switchWidth: Kirigami.Units.gridUnit * 4
    switchHeight: Kirigami.Units.gridUnit * 4


    readonly property var buttons: {
        try { return JSON.parse(Plasmoid.configuration.buttons) } catch (e) { return [] }
    }
    readonly property int columns: Math.max(1, Plasmoid.configuration.columns)
    // Tamaño base de las teclas: solo define el tamaño inicial; después se adaptan al del widget
    readonly property int baseCell: Math.max(48, Plasmoid.configuration.buttonSize)
    readonly property int rows: Math.max(Math.max(1, Plasmoid.configuration.rows), Math.ceil(buttons.length / columns))
    readonly property int slots: columns * rows

    // Estado por botón: { status: "running" | "ok" | "fail", until: ms }
    property var states: ({})
    property real nowMs: Date.now()
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

    // Reloj que hace expirar los avisos ok/fail; compara contra la hora real, así que
    // también se limpian si el widget estuvo congelado (por ejemplo, con la pantalla bloqueada)
    Timer {
        id: clearTimer
        interval: 400
        repeat: true
        running: Object.keys(root.states).length > 0
        onTriggered: {
            var now = Date.now()
            root.nowMs = now
            var s = {}, changed = false
            Object.keys(root.states).forEach(function (k) {
                var e = root.states[k]
                if (e.status === "running" || e.until > now) s[k] = e
                else changed = true
            })
            if (changed) root.states = s
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

        readonly property int bodyPad: 6
        readonly property int gap: 6
        readonly property real footerH: Kirigami.Units.gridUnit * 1.8
        readonly property int minCell: 36

        // Las teclas se ajustan al tamaño del widget
        readonly property real cell: Math.max(minCell, Math.floor(Math.min(
            (width - bodyPad * 2 - (root.columns - 1) * gap) / root.columns,
            (height - bodyPad * 2 - footerH - (root.rows - 1) * gap) / root.rows)))
        readonly property real gridW: root.columns * cell + (root.columns - 1) * gap
        readonly property real gridH: root.rows * cell + (root.rows - 1) * gap
        readonly property bool labels: Plasmoid.configuration.showLabels && cell >= 56

        Layout.minimumWidth: root.columns * minCell + (root.columns - 1) * gap + bodyPad * 2
        Layout.minimumHeight: root.rows * minCell + (root.rows - 1) * gap + bodyPad * 2 + footerH
        Layout.preferredWidth: root.columns * root.baseCell + (root.columns - 1) * gap + bodyPad * 2
        Layout.preferredHeight: root.rows * root.baseCell + (root.rows - 1) * gap + bodyPad * 2 + footerH

        Grid {
            id: grid
            x: Math.round((view.width - view.gridW) / 2)
            y: Math.round((view.height - view.footerH - view.gridH) / 2)
            columns: root.columns
            spacing: view.gap

            Repeater {
                model: root.slots

                delegate: Item {
                    id: btn
                    width: view.cell
                    height: view.cell

                    readonly property var b: index < root.buttons.length ? root.buttons[index] : null
                    readonly property bool empty: b === null
                    readonly property color accent: b && b.color ? b.color : "#38bdf8"
                    readonly property var st: root.states[index]
                    readonly property string status: st && (st.status === "running" || st.until > root.nowMs) ? st.status : ""
                    readonly property bool confirming: root.pendingConfirm === index

                    // Tecla de vidrio translúcido
                    Rectangle {
                        id: key
                        anchors.fill: parent
                        radius: view.cell * 0.2
                        scale: mouse.pressed && !btn.empty ? 0.93 : 1
                        Behavior on scale { NumberAnimation { duration: 80 } }
                        color: btn.empty ? (mouse.containsMouse ? "#22ffffff" : "#0fffffff") : "#1affffff"
                        border.width: btn.status === "ok" || btn.status === "fail" || btn.confirming ? 3 : 1
                        border.color: btn.status === "ok" ? "#22c55e"
                                    : btn.status === "fail" ? "#ef4444"
                                    : btn.confirming ? "#f59e0b"
                                    : btn.empty ? "#22ffffff"
                                    : Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, 0.7)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        // Tinte del color del botón
                        Rectangle {
                            visible: !btn.empty
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, mouse.containsMouse ? 0.5 : 0.36) }
                                GradientStop { position: 1; color: Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, mouse.containsMouse ? 0.3 : 0.16) }
                            }
                        }

                        // Brillo superior
                        Rectangle {
                            visible: !btn.empty
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 2
                            height: parent.height * 0.4
                            radius: parent.radius - 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#26ffffff" }
                                GradientStop { position: 1; color: "#00ffffff" }
                            }
                        }

                        // Ranura vacía: "+" tenue
                        Text {
                            visible: btn.empty
                            anchors.centerIn: parent
                            text: "+"
                            color: "white"
                            font.pixelSize: view.cell * 0.4
                            opacity: mouse.containsMouse ? 0.7 : 0.25
                        }

                        ColumnLayout {
                            visible: !btn.empty
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.smallSpacing * 2
                            spacing: Math.round(view.cell * 0.04)

                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: view.cell * (view.labels ? 0.44 : 0.58)
                                Layout.preferredHeight: Layout.preferredWidth
                                source: btn.status === "ok" ? "dialog-ok-apply"
                                      : btn.status === "fail" ? "dialog-error"
                                      : btn.confirming ? "dialog-question"
                                      : (btn.b && btn.b.icon ? btn.b.icon : "system-run")
                                opacity: btn.status === "running" ? 0.3 : 1
                            }

                            Text {
                                visible: view.labels
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: btn.confirming ? "¿Seguro?" : (btn.b ? btn.b.name : "")
                                color: "white"
                                elide: Text.ElideRight
                                font.pixelSize: Math.max(9, view.cell * 0.13)
                                font.bold: true
                                layer.enabled: true
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
                            width: view.cell * 0.5
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

                    QQC2.ToolTip.visible: mouse.containsMouse && btn.status === ""
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
                    color: root.pendingConfirm >= 0 ? "#fbbf24"
                         : root.messageIsError ? "#fca5a5" : "white"
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    layer.enabled: true
                    layer.effect: DropShadow {
                        verticalOffset: 1
                        radius: 4
                        samples: 9
                        color: "#cc000000"
                    }
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
