import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Barra de progreso con etiqueta a la izquierda y detalle a la derecha.
ColumnLayout {
    id: bar

    property string label
    property string detail
    property real fraction: 0
    property color barColor: "#7dd3fc"
    property color textColor: "white"
    property color trackColor: "#33ffffff"

    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: bar.label
            color: bar.textColor
            opacity: 0.75
            font.pixelSize: Kirigami.Units.gridUnit * 0.7
        }
        Text {
            text: bar.detail
            color: bar.textColor
            font.pixelSize: Kirigami.Units.gridUnit * 0.7
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 6
        radius: 3
        color: bar.trackColor
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, bar.fraction))
            height: parent.height
            radius: 3
            color: bar.barColor
            Behavior on width { NumberAnimation { duration: 250 } }
        }
    }
}
