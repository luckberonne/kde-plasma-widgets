import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_serverUrl: urlField.text
    property alias cfg_temperature: tempSpin.realValue
    property alias cfg_systemPrompt: promptArea.text

    QQC2.TextField {
        id: urlField
        Kirigami.FormData.label: i18n("Servidor llama.cpp:")
        placeholderText: "http://127.0.0.1:8080"
        implicitWidth: Kirigami.Units.gridUnit * 18
    }

    QQC2.SpinBox {
        id: tempSpin
        Kirigami.FormData.label: i18n("Temperatura:")
        property real realValue: 0.3
        from: 0
        to: 200
        stepSize: 5
        value: Math.round(realValue * 100)
        onValueModified: realValue = value / 100
        textFromValue: function (v) { return (v / 100).toFixed(2) }
        valueFromText: function (t) { return Math.round(parseFloat(t) * 100) }
    }

    QQC2.TextArea {
        id: promptArea
        Kirigami.FormData.label: i18n("Prompt del sistema (modo chat):")
        wrapMode: TextEdit.Wrap
        implicitWidth: Kirigami.Units.gridUnit * 18
        implicitHeight: Kirigami.Units.gridUnit * 6
    }
}
