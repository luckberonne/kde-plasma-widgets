import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    readonly property var diasSemana: ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
    readonly property var meses: ["ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO", "JULIO", "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE"]

    property date currentTime: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentTime = new Date()
    }

    function pad(n) {
        return n < 10 ? "0" + n : String(n)
    }

    readonly property int hours24: currentTime.getHours()
    readonly property int hours12: (hours24 % 12 === 0) ? 12 : hours24 % 12
    readonly property string ampm: hours24 >= 12 ? "PM" : "AM"
    readonly property string separator: Plasmoid.configuration.timeSeparator.length ? Plasmoid.configuration.timeSeparator : "."

    readonly property string timeText: {
        var h = Plasmoid.configuration.use24Hour ? pad(hours24) : String(hours12)
        var m = pad(currentTime.getMinutes())
        var s = Plasmoid.configuration.showSeconds ? (separator + pad(currentTime.getSeconds())) : ""
        return h + separator + m + s
    }

    readonly property string weekdayText: diasSemana[currentTime.getDay()]
    readonly property string dateText: currentTime.getDate() + " DE " + meses[currentTime.getMonth()] + " " + currentTime.getFullYear()

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: Kirigami.Units.gridUnit * 9
        Layout.preferredWidth: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16

        FontLoader {
            id: scriptFont
            source: "../fonts/DancingScript-Bold.ttf"
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width * 0.9
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: timeLabel.implicitHeight

                Text {
                    id: timeLabel
                    anchors.centerIn: parent
                    text: root.timeText
                    color: "#ffffff"
                    font.family: "Noto Sans"
                    font.bold: true
                    font.pixelSize: Math.max(28, Math.min(view.width * 0.16, view.height * 0.32))

                    layer.enabled: true
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 2
                        radius: 16
                        samples: 33
                        color: "#b3000000"
                        transparentBorder: true
                    }
                }

                Text {
                    visible: Plasmoid.configuration.showWeekday
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -timeLabel.implicitHeight * 0.06
                    text: root.weekdayText
                    color: "#2b2142"
                    font.family: scriptFont.status === FontLoader.Ready ? scriptFont.name : "Noto Serif"
                    font.italic: scriptFont.status !== FontLoader.Ready
                    font.bold: true
                    font.pixelSize: timeLabel.font.pixelSize * 0.42
                    rotation: -6

                    layer.enabled: true
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 0
                        radius: 10
                        samples: 21
                        color: "#e6ffffff"
                        transparentBorder: true
                    }
                }

                Text {
                    visible: !Plasmoid.configuration.use24Hour
                    anchors.left: timeLabel.right
                    anchors.bottom: timeLabel.bottom
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    text: root.ampm
                    color: "#ffffff"
                    font.family: "Noto Sans"
                    font.bold: true
                    font.pixelSize: timeLabel.font.pixelSize * 0.16
                    opacity: 0.85

                    layer.enabled: true
                    layer.effect: DropShadow {
                        horizontalOffset: 0
                        verticalOffset: 1
                        radius: 8
                        samples: 17
                        color: "#b3000000"
                        transparentBorder: true
                    }
                }
            }

            Text {
                visible: Plasmoid.configuration.showDate
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.largeSpacing
                text: root.dateText
                color: "#ffffff"
                opacity: 0.9
                font.family: "Noto Sans"
                font.letterSpacing: 3
                font.pixelSize: Math.max(11, Math.min(view.width * 0.035, 18))

                layer.enabled: true
                layer.effect: DropShadow {
                    horizontalOffset: 0
                    verticalOffset: 1
                    radius: 10
                    samples: 21
                    color: "#b3000000"
                    transparentBorder: true
                }
            }
        }
    }
}
