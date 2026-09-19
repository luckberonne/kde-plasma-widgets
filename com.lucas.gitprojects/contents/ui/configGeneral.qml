import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_rootPath: rootField.text
    property alias cfg_searchDepth: depthSpin.value
    property alias cfg_editorCommand: editorField.text
    property alias cfg_updateInterval: intervalSpin.value
    property alias cfg_onlyAttention: attentionCheck.checked

    QQC2.TextField {
        id: rootField
        Kirigami.FormData.label: i18n("Carpeta de proyectos:")
        placeholderText: "~/Proyectos"
        implicitWidth: Kirigami.Units.gridUnit * 16
    }

    QQC2.SpinBox {
        id: depthSpin
        Kirigami.FormData.label: i18n("Profundidad de búsqueda:")
        from: 1
        to: 6
    }

    QQC2.TextField {
        id: editorField
        Kirigami.FormData.label: i18n("Comando del editor:")
        placeholderText: "code"
        implicitWidth: Kirigami.Units.gridUnit * 16
    }

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("Intervalo de actualización (ms):")
        from: 3000
        to: 120000
        stepSize: 1000
    }

    QQC2.CheckBox {
        id: attentionCheck
        Kirigami.FormData.label: i18n("Lista:")
        text: i18n("Mostrar solo repos con cambios o commits sin pushear")
    }
}
