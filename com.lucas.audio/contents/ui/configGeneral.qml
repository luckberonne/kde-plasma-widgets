import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_updateInterval: intervalSpin.value
    property alias cfg_showHdmi: hdmiCheck.checked
    property alias cfg_maxVolume: maxSpin.value

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Intervalo de actualización (ms):")
        from: 500
        to: 10000
        stepSize: 500
    }

    QQC2.SpinBox {
        id: maxSpin
        Kirigami.FormData.label: i18n("Volumen máximo (%):")
        from: 100
        to: 150
        stepSize: 5
    }

    QQC2.CheckBox {
        id: hdmiCheck
        Kirigami.FormData.label: i18n("Salidas:")
        text: i18n("Mostrar salidas HDMI / DisplayPort")
    }
}
