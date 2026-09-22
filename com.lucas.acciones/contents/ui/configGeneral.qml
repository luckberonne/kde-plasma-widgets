import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property int cfg_updateInterval
    property int cfg_updateIntervalDefault

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Actualizar cada (segundos):")
        from: 15
        to: 3600
        stepSize: 15
        value: Math.round(page.cfg_updateInterval / 1000)
        onValueModified: page.cfg_updateInterval = value * 1000
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Símbolos:")
        text: i18n("Se agregan y quitan directamente desde el widget, con el campo de texto de la vista principal.")
        wrapMode: Text.WordWrap
        width: Kirigami.Units.gridUnit * 20
        opacity: 0.7
    }
}
