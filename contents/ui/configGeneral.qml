import QtQuick 2.0
import QtQuick.Controls 2.5
import QtQuick.Layouts 1.12
import org.kde.kirigami as Kirigami


Kirigami.FormLayout {
    id: configGeneral

    property alias cfg_batteryHealthConfigPath: batteryHealthConfigPathField.text
    property alias cfg_iconSize: iconSizeComboBox.currentValue
    property alias cfg_needSudo: needSudoField.checked

    TextField {
        id: batteryHealthConfigPathField
        Kirigami.FormData.label: i18n("Battery Health config file (if the plugin works don't touch this):")
    }

    CheckBox {
        id: needSudoField
        text: i18n("I need sudo")
        anchors.top: batteryHealthConfigPathField.bottom
        anchors.topMargin: 15
        onCheckedChanged: {
            plasmoid.configuration.elevatedPivilegesTool = checked ? "/usr/bin/pkexec" : "/usr/bin/sudo";
        }
    }

    Label {
        id: noteDisableSudo
        text: "NOTE: Uncheck if you can run 'sudo tee' without entering the root password."
        anchors.top: needSudoField.bottom
    }

    Label {
        id: labelCmdDisableSudo
        text: "TIP: Command to allow execution without root password:"
        anchors.top: noteDisableSudo.bottom
    }

    TextField {
        text: "echo \"%$(id -gn) ALL=(ALL) NOPASSWD: /usr/bin/tee " + configGeneral.cfg_batteryHealthConfigPath.replace(/:/g, "\\:") + "\" | sudo tee /etc/sudoers.d/battery_health"
        wrapMode: Text.Wrap
        readOnly: true
        Layout.fillWidth: true
        anchors.top: labelCmdDisableSudo.bottom
    }

    ComboBox {
        id: iconSizeComboBox

        Kirigami.FormData.label: i18n("Icon size:")
        model: [
            {text: "small", value: Kirigami.Units.iconSizes.small},
            {text: "small-medium", value: Kirigami.Units.iconSizes.smallMedium},
            {text: "medium", value: Kirigami.Units.iconSizes.medium},
            {text: "large", value: Kirigami.Units.iconSizes.large},
            {text: "huge", value: Kirigami.Units.iconSizes.huge},
            {text: "enormous", value: Kirigami.Units.iconSizes.enormous}
        ]
        textRole: "text"
        valueRole: "value"

        currentIndex: model.findIndex((element) => element.value === plasmoid.configuration.iconSize)
    }
}
