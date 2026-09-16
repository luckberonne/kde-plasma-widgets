import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_use24Hour: use24HourCheck.checked
    property alias cfg_showSeconds: showSecondsCheck.checked
    property alias cfg_showDate: showDateCheck.checked
    property alias cfg_showWeekday: showWeekdayCheck.checked
    property alias cfg_timeSeparator: separatorField.text

    QQC2.CheckBox {
        id: use24HourCheck
        Kirigami.FormData.label: i18n("Formato de hora:")
        text: i18n("Usar formato de 24 horas")
    }

    QQC2.CheckBox {
        id: showSecondsCheck
        text: i18n("Mostrar segundos")
    }

    QQC2.CheckBox {
        id: showDateCheck
        Kirigami.FormData.label: i18n("Textos:")
        text: i18n("Mostrar fecha")
    }

    QQC2.CheckBox {
        id: showWeekdayCheck
        text: i18n("Mostrar día de la semana (cursiva)")
    }

    QQC2.TextField {
        id: separatorField
        Kirigami.FormData.label: i18n("Separador de hora:")
        placeholderText: "."
        maximumLength: 1
    }
}
