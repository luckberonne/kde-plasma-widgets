import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 14

    readonly property var modes: [
        { name: "Chat", hint: "Preguntale algo al modelo…", system: "" },
        { name: "Traducir", hint: "Texto a traducir (es ↔ en)…",
          system: "Sos un traductor. Si el texto está en español, traducilo al inglés; si está en cualquier otro idioma, traducilo al español. Respondé únicamente con la traducción, sin comentarios." },
        { name: "Corregir", hint: "Texto a corregir…",
          system: "Sos un corrector. Corregí ortografía, gramática y puntuación del texto sin cambiar su idioma ni su sentido. Respondé únicamente con el texto corregido, sin comentarios." }
    ]
    property int mode: Plasmoid.configuration.mode
    property bool busy: false
    property var currentXhr: null

    toolTipMainText: "Chat con LLM local"
    toolTipSubText: Plasmoid.configuration.serverUrl

    ListModel { id: messages }

    function apiMessages() {
        var sys = mode === 0 ? Plasmoid.configuration.systemPrompt : modes[mode].system
        var out = []
        if (sys.length) out.push({ role: "system", content: sys })
        if (mode === 0) {
            // el último mensaje es el placeholder vacío del asistente
            for (var i = 0; i < messages.count - 1; i++)
                out.push({ role: messages.get(i).role, content: messages.get(i).text })
        } else {
            out.push({ role: "user", content: messages.get(messages.count - 2).text })
        }
        return out
    }

    function send(text) {
        text = text.trim()
        if (!text.length || busy) return
        if (mode !== 0) messages.clear()
        messages.append({ role: "user", text: text })
        messages.append({ role: "assistant", text: "" })
        var idx = messages.count - 1
        busy = true

        var xhr = new XMLHttpRequest()
        currentXhr = xhr
        var url = Plasmoid.configuration.serverUrl.replace(/\/+$/, "") + "/v1/chat/completions"
        var seen = 0
        var buffer = ""

        function consume() {
            buffer += xhr.responseText.substring(seen)
            seen = xhr.responseText.length
            var lines = buffer.split("\n")
            buffer = lines.pop()
            lines.forEach(function (line) {
                if (line.indexOf("data:") !== 0) return
                var payload = line.substring(5).trim()
                if (payload === "[DONE]" || !payload.length) return
                try {
                    var delta = JSON.parse(payload).choices[0].delta
                    if (delta && delta.content)
                        messages.setProperty(idx, "text", messages.get(idx).text + delta.content)
                } catch (e) {}
            })
        }

        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.LOADING || xhr.readyState === XMLHttpRequest.DONE)
                consume()
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 0 && messages.get(idx).text === "" && currentXhr === xhr)
                    messages.setProperty(idx, "text", "⚠ No se pudo conectar con " + Plasmoid.configuration.serverUrl)
                else if (xhr.status >= 400)
                    messages.setProperty(idx, "text", "⚠ Error " + xhr.status + " del servidor")
                busy = false
                currentXhr = null
            }
        }

        xhr.open("POST", url)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify({
            messages: apiMessages(),
            stream: true,
            temperature: Plasmoid.configuration.temperature
        }))
    }

    function stop() {
        if (currentXhr) { var x = currentXhr; currentXhr = null; x.abort() }
        busy = false
    }

    component GlassText: Text {
        color: "white"
        wrapMode: Text.Wrap
        layer.enabled: true
        layer.effect: DropShadow {
            verticalOffset: 1
            radius: 5
            samples: 11
            color: "#aa000000"
        }
    }

    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.iconSizes.medium
        Layout.minimumHeight: Kirigami.Units.iconSizes.medium
        Kirigami.Icon {
            anchors.fill: parent
            source: "im-user-online"
            active: hover.hovered
        }
        HoverHandler { id: hover }
        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30

        TextEdit { id: clip; visible: false }

        Rectangle {
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
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.modes
                    delegate: QQC2.Button {
                        text: modelData.name
                        checkable: true
                        checked: root.mode === index
                        enabled: !root.busy
                        onClicked: Plasmoid.configuration.mode = index
                    }
                }

                Item { Layout.fillWidth: true }

                QQC2.ToolButton {
                    icon.name: "edit-clear-all"
                    enabled: !root.busy && messages.count > 0
                    onClicked: messages.clear()
                    QQC2.ToolTip.text: "Limpiar"
                    QQC2.ToolTip.visible: hovered
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Kirigami.Units.smallSpacing
                model: messages
                onCountChanged: positionViewAtEnd()
                onContentHeightChanged: if (root.busy) positionViewAtEnd()
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                GlassText {
                    anchors.centerIn: parent
                    visible: messages.count === 0
                    width: parent.width * 0.8
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.6
                    text: "Modelo local en " + Plasmoid.configuration.serverUrl
                }

                delegate: Item {
                    width: list.width - Kirigami.Units.largeSpacing
                    implicitHeight: bubble.height

                    readonly property bool mine: model.role === "user"

                    Rectangle {
                        id: bubble
                        anchors.right: mine ? parent.right : undefined
                        anchors.left: mine ? undefined : parent.left
                        width: Math.min(parent.width * 0.92, Math.max(msg.implicitWidth, 40) + Kirigami.Units.largeSpacing * 2)
                        height: msg.implicitHeight + Kirigami.Units.largeSpacing * 2 + (mine || model.text === "" ? 0 : copyBtn.height)
                        radius: Kirigami.Units.mediumSpacing
                        color: mine ? "#557dd3fc" : "#33ffffff"

                        GlassText {
                            id: msg
                            x: Kirigami.Units.largeSpacing
                            y: Kirigami.Units.largeSpacing
                            width: bubble.width - Kirigami.Units.largeSpacing * 2
                            text: model.text === "" ? "…" : model.text
                            textFormat: Text.PlainText
                        }

                        QQC2.ToolButton {
                            id: copyBtn
                            visible: !mine && model.text !== ""
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 2
                            icon.name: "edit-copy"
                            text: "Copiar"
                            display: QQC2.AbstractButton.TextBesideIcon
                            font.pixelSize: Kirigami.Units.gridUnit * 0.65
                            onClicked: {
                                clip.text = model.text
                                clip.selectAll()
                                clip.copy()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 6, Math.max(Kirigami.Units.gridUnit * 2.4, input.implicitHeight))

                    QQC2.TextArea {
                        id: input
                        wrapMode: TextEdit.Wrap
                        placeholderText: root.modes[root.mode].hint
                        enabled: true
                        Keys.onPressed: (event) => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) &&
                                !(event.modifiers & Qt.ShiftModifier)) {
                                if (!root.busy) {
                                    root.send(input.text)
                                    input.text = ""
                                }
                                event.accepted = true
                            }
                        }
                    }
                }

                QQC2.Button {
                    icon.name: root.busy ? "media-playback-stop" : "document-send"
                    onClicked: {
                        if (root.busy) { root.stop(); return }
                        root.send(input.text)
                        input.text = ""
                    }
                    QQC2.ToolTip.text: root.busy ? "Detener" : "Enviar (Enter)"
                    QQC2.ToolTip.visible: hovered
                }
            }
        }
    }
}
