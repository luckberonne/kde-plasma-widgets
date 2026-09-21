import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_iconSizeRatio: iconSize.value
    property alias cfg_maxScale: zoom.value
    property alias cfg_influenceFactor: influence.value
    property alias cfg_spread: spread.value
    property alias cfg_showLabels: labels.checked
    property alias cfg_showPreviews: previews.checked
    property alias cfg_showOnlyCurrentScreen: currentScreen.checked
    property alias cfg_showOnlyCurrentDesktop: currentDesktop.checked
    property alias cfg_bounceOnLaunch: bounce.checked
    property alias cfg_showBadges: badges.checked
    property alias cfg_showAudio: audio.checked
    property alias cfg_cycleIconPreview: cyclePreview.checked
    property alias cfg_peekOnHover: peek.checked
    property alias cfg_hidePanelBackground: hideBackground.checked

    Kirigami.FormLayout {
        anchors.fill: parent

        QQC2.Slider {
            id: iconSize
            Kirigami.FormData.label: i18n("Tamaño del icono:")
            from: 0.35; to: 0.9; stepSize: 0.01
            implicitWidth: Kirigami.Units.gridUnit * 14
        }
        QQC2.Label {
            text: i18n("%1 % del alto del panel", Math.round(iconSize.value * 100))
            opacity: 0.7
        }

        QQC2.Slider {
            id: zoom
            Kirigami.FormData.label: i18n("Magnificación:")
            from: 1.0; to: 2.0; stepSize: 0.05
            implicitWidth: Kirigami.Units.gridUnit * 14
        }
        QQC2.Label {
            text: zoom.value <= 1.001 ? i18n("desactivada") : i18n("×%1", zoom.value.toFixed(2))
            opacity: 0.7
        }

        QQC2.Slider {
            id: influence
            Kirigami.FormData.label: i18n("Alcance:")
            from: 0.8; to: 4.0; stepSize: 0.1
            implicitWidth: Kirigami.Units.gridUnit * 14
        }
        QQC2.Label {
            text: i18n("afecta ~%1 iconos a cada lado", influence.value.toFixed(1))
            opacity: 0.7
        }

        QQC2.Slider {
            id: spread
            Kirigami.FormData.label: i18n("Separación de vecinos:")
            from: 0.0; to: 1.0; stepSize: 0.05
            implicitWidth: Kirigami.Units.gridUnit * 14
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: labels
            Kirigami.FormData.label: i18n("Mostrar:")
            text: i18n("Nombre de la aplicación al pasar el mouse")
        }
        QQC2.CheckBox {
            id: previews
            text: i18n("Miniatura en vivo de las ventanas abiertas")
        }
        QQC2.CheckBox {
            id: badges
            text: i18n("Notificaciones sin leer y progreso de descargas/copias")
        }
        QQC2.CheckBox {
            id: cyclePreview
            text: i18n("En apps con varias ventanas, mostrarlas por turnos en el icono al pasar el mouse")
        }
        QQC2.CheckBox {
            id: peek
            text: i18n("Al mantener el mouse sobre una miniatura, traer esa ventana al frente temporalmente")
        }
        QQC2.CheckBox {
            id: audio
            text: i18n("Indicador de audio (clic para silenciar)")
        }
        QQC2.CheckBox {
            id: bounce
            text: i18n("Rebote al abrir una aplicación")
        }
        QQC2.CheckBox {
            id: currentDesktop
            text: i18n("Solo ventanas del escritorio actual")
        }
        QQC2.CheckBox {
            id: currentScreen
            text: i18n("Solo ventanas de esta pantalla")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: hideBackground
            Kirigami.FormData.label: i18n("Panel:")
            text: i18n("Ocultar el fondo del panel (completamente transparente)")
        }
    }
}
