import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_updateInterval: intervalSpin.value
    property alias cfg_showOffline: offlineCheck.checked

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Intervalo de actualización (ms):")
        from: 2000
        to: 60000
        stepSize: 1000
    }

    QQC2.CheckBox {
        id: offlineCheck
        Kirigami.FormData.label: i18n("Dispositivos:")
        text: i18n("Mostrar también los desconectados")
    }
}
