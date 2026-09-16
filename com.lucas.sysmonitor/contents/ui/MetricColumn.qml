import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: col

    property real value: 0
    property color accentColor: "#ffffff"
    property string label: ""
    property string detail: "--"
    property real gaugeSize: 64

    spacing: Kirigami.Units.smallSpacing

    Item {
        Layout.preferredWidth: col.gaugeSize
        Layout.preferredHeight: col.gaugeSize
        Layout.alignment: Qt.AlignHCenter

        Gauge {
            anchors.fill: parent
            value: col.value
            valueColor: col.accentColor
        }

        Text {
            anchors.centerIn: parent
            text: Math.round(col.value) + "%"
            color: "#ffffff"
            font.bold: true
            font.family: "Noto Sans"
            font.pixelSize: col.gaugeSize * 0.22

            layer.enabled: true
            layer.effect: DropShadow {
                radius: 8
                samples: 17
                verticalOffset: 1
                color: "#b3000000"
                transparentBorder: true
            }
        }
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: col.label
        color: "#ffffff"
        font.bold: true
        font.family: "Noto Sans"
        font.pixelSize: col.gaugeSize * 0.16

        layer.enabled: true
        layer.effect: DropShadow {
            radius: 6
            samples: 13
            verticalOffset: 1
            color: "#b3000000"
            transparentBorder: true
        }
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: col.detail
        color: "#ffffff"
        opacity: 0.85
        font.family: "Noto Sans"
        font.pixelSize: col.gaugeSize * 0.13

        layer.enabled: true
        layer.effect: DropShadow {
            radius: 6
            samples: 13
            verticalOffset: 1
            color: "#b3000000"
            transparentBorder: true
        }
    }
}
