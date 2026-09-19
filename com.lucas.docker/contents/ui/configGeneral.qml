import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_updateInterval: intervalSpin.value
    property alias cfg_showStopped: stoppedCheck.checked
    property alias cfg_logLines: logSpin.value

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Intervalo de actualización (ms):")
        from: 1000
        to: 30000
        stepSize: 1000
    }

    QQC2.CheckBox {
        id: stoppedCheck
        Kirigami.FormData.label: i18n("Contenedores:")
        text: i18n("Mostrar también los detenidos")
    }

    QQC2.SpinBox {
        id: logSpin
        Kirigami.FormData.label: i18n("Líneas de log a mostrar:")
        from: 10
        to: 1000
        stepSize: 10
    }
}
