import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

Item {
    id: page

    property string cfg_buttons

    readonly property var palette: ["#38bdf8", "#22c55e", "#f59e0b", "#f97316", "#ef4444", "#ec4899", "#c084fc", "#818cf8", "#2dd4bf", "#94a3b8"]
    property bool loading: false

    implicitWidth: Kirigami.Units.gridUnit * 34
    implicitHeight: Kirigami.Units.gridUnit * 22

    ListModel { id: buttonModel }

    function load() {
        loading = true
        buttonModel.clear()
        var arr = []
        try { arr = JSON.parse(cfg_buttons) } catch (e) {}
        arr.forEach(function (b) {
            buttonModel.append({
                name: b.name || "", icon: b.icon || "system-run", color: b.color || "#38bdf8",
                cmd: b.cmd || "", app: !!b.app, terminal: !!b.terminal, confirm: !!b.confirm
            })
        })
        loading = false
        list.currentIndex = buttonModel.count ? 0 : -1
        syncFields()
    }

    function save() {
        if (loading) return
        var arr = []
        for (var i = 0; i < buttonModel.count; i++) {
            var b = buttonModel.get(i)
            arr.push({ name: b.name, icon: b.icon, color: b.color, cmd: b.cmd,
                       app: b.app, terminal: b.terminal, confirm: b.confirm })
        }
        cfg_buttons = JSON.stringify(arr)
    }

    function setField(key, value) {
        if (loading || list.currentIndex < 0) return
        buttonModel.setProperty(list.currentIndex, key, value)
        save()
    }

    function syncFields() {
        loading = true
        var i = list.currentIndex
        var b = i >= 0 ? buttonModel.get(i) : null
        nameField.text = b ? b.name : ""
        cmdField.text = b ? b.cmd : ""
        appCheck.checked = b ? b.app : false
        termCheck.checked = b ? b.terminal : false
        confirmCheck.checked = b ? b.confirm : false
        loading = false
    }

    Component.onCompleted: load()

    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: if (iconName.length) page.setField("icon", iconName)
    }

    RowLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        // Lista de botones
        ColumnLayout {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            Layout.fillHeight: true

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    model: buttonModel
                    clip: true
                    onCurrentIndexChanged: page.syncFields()

                    delegate: QQC2.ItemDelegate {
                        width: list.width
                        highlighted: ListView.isCurrentItem
                        onClicked: list.currentIndex = index
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle {
                                Layout.preferredWidth: 4
                                Layout.fillHeight: true
                                radius: 2
                                color: model.color
                            }
                            Kirigami.Icon {
                                source: model.icon
                                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: model.name.length ? model.name : i18n("(sin nombre)")
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                QQC2.ToolButton {
                    icon.name: "list-add"
                    onClicked: {
                        buttonModel.append({ name: i18n("Nuevo"), icon: "system-run", color: "#38bdf8",
                                       cmd: "", app: false, terminal: false, confirm: false })
                        list.currentIndex = buttonModel.count - 1
                        page.save()
                    }
                    QQC2.ToolTip.text: i18n("Añadir botón")
                    QQC2.ToolTip.visible: hovered
                }
                QQC2.ToolButton {
                    icon.name: "go-up"
                    enabled: list.currentIndex > 0
                    onClicked: {
                        var i = list.currentIndex
                        buttonModel.move(i, i - 1, 1)
                        list.currentIndex = i - 1
                        page.save()
                    }
                }
                QQC2.ToolButton {
                    icon.name: "go-down"
                    enabled: list.currentIndex >= 0 && list.currentIndex < buttonModel.count - 1
                    onClicked: {
                        var i = list.currentIndex
                        buttonModel.move(i, i + 1, 1)
                        list.currentIndex = i + 1
                        page.save()
                    }
                }
                Item { Layout.fillWidth: true }
                QQC2.ToolButton {
                    icon.name: "edit-delete"
                    enabled: list.currentIndex >= 0
                    onClicked: {
                        var i = list.currentIndex
                        buttonModel.remove(i)
                        list.currentIndex = Math.min(i, buttonModel.count - 1)
                        page.save()
                        page.syncFields()
                    }
                    QQC2.ToolTip.text: i18n("Eliminar botón")
                    QQC2.ToolTip.visible: hovered
                }
            }
        }

        // Editor del botón seleccionado
        Kirigami.FormLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            enabled: list.currentIndex >= 0

            QQC2.TextField {
                id: nameField
                Kirigami.FormData.label: i18n("Nombre:")
                Layout.fillWidth: true
                onTextEdited: page.setField("name", text)
            }

            QQC2.Button {
                Kirigami.FormData.label: i18n("Icono:")
                icon.name: list.currentIndex >= 0 ? buttonModel.get(list.currentIndex).icon : "system-run"
                text: list.currentIndex >= 0 ? buttonModel.get(list.currentIndex).icon : ""
                onClicked: iconDialog.open()
            }

            Flow {
                Kirigami.FormData.label: i18n("Color:")
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: page.palette
                    delegate: Rectangle {
                        readonly property bool selected: list.currentIndex >= 0 && buttonModel.get(list.currentIndex).color === modelData
                        width: Kirigami.Units.gridUnit * 1.4
                        height: width
                        radius: width / 2
                        color: modelData
                        border.width: selected ? 3 : 1
                        border.color: selected ? Kirigami.Theme.textColor : "#44000000"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: page.setField("color", modelData)
                        }
                    }
                }
            }

            QQC2.TextArea {
                id: cmdField
                Kirigami.FormData.label: i18n("Comando:")
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                wrapMode: TextEdit.Wrap
                font.family: "monospace"
                placeholderText: "loginctl lock-session"
                onTextChanged: if (activeFocus) page.setField("cmd", text)
            }

            QQC2.CheckBox {
                id: appCheck
                Kirigami.FormData.label: i18n("Opciones:")
                text: i18n("Es una aplicación (no esperar a que termine)")
                onToggled: {
                    if (checked) termCheck.checked = false
                    page.setField("app", checked)
                    page.setField("terminal", termCheck.checked)
                }
            }
            QQC2.CheckBox {
                id: termCheck
                text: i18n("Abrir en una terminal (Konsole) y dejarla abierta")
                onToggled: {
                    if (checked) appCheck.checked = false
                    page.setField("terminal", checked)
                    page.setField("app", appCheck.checked)
                }
            }
            QQC2.CheckBox {
                id: confirmCheck
                text: i18n("Pedir confirmación antes de ejecutar")
                onToggled: page.setField("confirm", checked)
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.7
                text: i18n("Los comandos se ejecutan con «sh -c», con tus permisos de usuario.")
            }
        }
    }
}
