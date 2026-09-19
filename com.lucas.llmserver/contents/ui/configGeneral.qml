import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_serverUrl: urlField.text
    property alias cfg_unitName: unitField.text
    property alias cfg_updateInterval: intervalSpin.value

    QQC2.TextField {
        id: urlField
        Kirigami.FormData.label: i18n("Servidor llama.cpp:")
        placeholderText: "http://127.0.0.1:8080"
        implicitWidth: Kirigami.Units.gridUnit * 18
    }

    QQC2.TextField {
        id: unitField
        Kirigami.FormData.label: i18n("Servicio systemd (usuario):")
        placeholderText: "llama-server.service"
        implicitWidth: Kirigami.Units.gridUnit * 18
    }

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Intervalo de estado del sistema (ms):")
        from: 1000
        to: 30000
        stepSize: 1000
    }
}
