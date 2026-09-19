import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "yast-docker"
        source: "configGeneral.qml"
    }
}
