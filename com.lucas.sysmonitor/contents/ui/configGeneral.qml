import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_diskPath: diskPathField.text
    property alias cfg_updateInterval: intervalSpin.value

    QQC2.TextField {
        id: diskPathField
        Kirigami.FormData.label: i18n("Disco a monitorear:")
        placeholderText: "/"
    }

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Intervalo de actualización (ms):")
        from: 1000
        to: 10000
        stepSize: 500
    }
}
