import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Botones")
        icon: "input-gaming"
        source: "configButtons.qml"
    }
    ConfigCategory {
        name: i18n("Apariencia")
        icon: "preferences-desktop-theme"
        source: "configAppearance.qml"
    }
}
