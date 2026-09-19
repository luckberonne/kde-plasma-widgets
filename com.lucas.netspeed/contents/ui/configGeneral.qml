import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_interfaceName: ifaceField.text
    property alias cfg_updateInterval: intervalSpin.value
    property alias cfg_showGraph: graphCheck.checked

    QQC2.TextField {
        id: ifaceField
        Kirigami.FormData.label: i18n("Interfaz de red:")
        placeholderText: i18n("automática (ej. wlan0)")
    }

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Intervalo de actualización (ms):")
        from: 500
        to: 10000
        stepSize: 500
    }

    QQC2.CheckBox {
        id: graphCheck
        Kirigami.FormData.label: i18n("Gráfico:")
        text: i18n("Mostrar mini gráfico")
    }
}
