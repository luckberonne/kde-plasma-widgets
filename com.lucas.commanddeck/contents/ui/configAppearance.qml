import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_columns: colsSpin.value
    property alias cfg_rows: rowsSpin.value
    property alias cfg_buttonSize: sizeSpin.value
    property alias cfg_showLabels: labelsCheck.checked

    QQC2.SpinBox {
        id: colsSpin
        Kirigami.FormData.label: i18n("Columnas:")
        from: 1
        to: 10
    }

    QQC2.SpinBox {
        id: rowsSpin
        Kirigami.FormData.label: i18n("Filas:")
        from: 1
        to: 8
    }

    QQC2.SpinBox {
        id: sizeSpin
        Kirigami.FormData.label: i18n("Tamaño inicial de los botones (px):")
        from: 48
        to: 200
        stepSize: 4
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.7
        text: i18n("Las teclas se adaptan al tamaño del widget: arrastrá sus bordes en el escritorio para agrandarlo o achicarlo.")
    }

    QQC2.CheckBox {
        id: labelsCheck
        Kirigami.FormData.label: i18n("Etiquetas:")
        text: i18n("Mostrar el nombre debajo del icono")
    }
}
