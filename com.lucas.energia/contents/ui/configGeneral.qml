import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_updateInterval: intervalSpin.value
    property alias cfg_showGraph: graphCheck.checked
    property alias cfg_showPercentInPanel: percentCheck.checked

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Intervalo de actualización (ms):")
        from: 1000
        to: 30000
        stepSize: 1000
    }

    QQC2.CheckBox {
        id: graphCheck
        Kirigami.FormData.label: i18n("Gráfico:")
        text: i18n("Mostrar el gráfico de consumo")
    }

    QQC2.CheckBox {
        id: percentCheck
        Kirigami.FormData.label: i18n("Panel:")
        text: i18n("Mostrar el porcentaje junto al icono")
    }
}
