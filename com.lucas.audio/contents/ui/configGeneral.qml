import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_updateInterval: intervalSpin.value
    property alias cfg_showHdmi: hdmiCheck.checked
    property alias cfg_maxVolume: maxSpin.value
    property alias cfg_showNotice: noticeCheck.checked
    property alias cfg_noticeSeconds: noticeSpin.value

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

    QQC2.CheckBox {
        id: noticeCheck
        Kirigami.FormData.label: i18n("Aviso:")
        text: i18n("Mostrar aviso de salida y entrada en uso")
    }

    QQC2.SpinBox {
        id: noticeSpin
        enabled: noticeCheck.checked
        Kirigami.FormData.label: i18n("Duración del aviso (s):")
        from: 1
        to: 15
    }
}
