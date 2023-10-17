import QtQuick 2.0
import QtQuick.Layouts 1.0
import QtQuick.Controls 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0


Item {
    id: root

    // Path to the pkexec command-line tool for gaining root privileges
    property string pkexecPath: "/usr/bin/pkexec"

    // Path to the Asus Battery Health configuration file
    property string batteryHelthConfigPath: ""

    // Icons for different status: "maximum," "balanced," "full," and "error"
    property var icons: ({
        "maximum": Qt.resolvedUrl("./image/maximum.png"),
        "balanced": Qt.resolvedUrl("./image/balanced.png"),
        "full": Qt.resolvedUrl("./image/full.png"),
        "error": Qt.resolvedUrl("./image/error.png")
    })

    // This property represents the current Asus Battery Health Charging status
    // Note: This value can change after the execution of onCompleted().
    property string currentStatus: "full"

    // A flag indicating whether the widget is compatible with the system
    property bool isCompatible: false

    // The notification tool to use (e.g., "zenity" or "notify-send")
    property string notificationTool: ""

    // The desired status for Asus Battery Health Charging
    property string desiredStatus: "full"

    // A flag indicating if an operation is in progress
    property bool loading: false

    // The currently displayed icon based on the current status
    property string icon: root.icons[root.currentStatus]

    // Set the icon for the Plasmoid
    Plasmoid.icon: root.icon

    // Connect to Plasmoid configuration to access user settings
    Connections {
        target: Plasmoid.configuration
    }

    // Executed when the component is completed
    Component.onCompleted: {
        findNotificationTool()
        findBatteryHelthConfigFile()
    }

    // CustomDataSource for querying the current Asus Battery Health Charging status
    CustomDataSource {
        id: queryStatusDataSource
        command: "cat " + root.batteryHelthConfigPath
    }

    // CustomDataSource for setting the Asus Battery Health Charging status
    CustomDataSource {
        id: setStatusDataSource

        // Dynamically set in switchStatus(). Set a default value to avoid errors at startup.
        property string status: "full"

        // Commands to set different Asus Battery Health Charging modes
        property var cmds: {

            "maximum": `echo 60 | ${root.pkexecPath} tee ${root.batteryHelthConfigPath} 1>/dev/null`,
            "balanced": `echo 80 | ${root.pkexecPath} tee ${root.batteryHelthConfigPath} 1>/dev/null`,
            "full": `echo 100 | ${root.pkexecPath} tee ${root.batteryHelthConfigPath} 1>/dev/null`
        }
        command: cmds[status]
    }

    // CustomDataSource for finding the notification tool (notify-send or zenity)
    CustomDataSource {
        id: findNotificationToolDataSource
        command: "find /usr -type f -executable \\( -name \"notify-send\" -o -name \"zenity\" \\)"
    }

    // CustomDataSource for finding the Asus Battery Health configuration file
    CustomDataSource {
        id: findBatteryHelthConfigFileDataSource
        command: "find /sys -name \"charge_control_end_threshold\""
    }

    // CustomDataSource for sending notifications
    CustomDataSource {
        id: sendNotification

        // Dynamically set in showNotification(). Set a default value to avoid errors at startup.
        property string tool: "notify-send"

        property string iconURL: ""
        property string title: ""
        property string message: ""
        property string options: ""

        property var cmds: {
            "notify-send": `notify-send -i ${iconURL} '${title}' '${message}' ${options}`,
            "zenity": `zenity --notification --text='${title}\\n${message}' ${options}`
        }
        command: cmds[tool]
    }


    // Connection for handling the queryStatusDataSource
    Connections {
        target: queryStatusDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){
            root.loading = false

            if (stderr) {
                root.icon = root.icons.error
                showNotification(root.icons.error, stderr, stderr)
            } else {
                var value = stdout.trim()
                root.currentStatus = root.desiredStatus = value === "60" ? "maximum" : value === "80" ? "balanced" : "full"
                root.isCompatible = true
            }
        }
    }


    // Connection for handling the setStatusDataSource
    Connections {
        target: setStatusDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){
            root.loading = false


            if(exitCode === 127){
                showNotification(root.icons.error, i18n("Root privileges are required."))
                root.desiredStatus = root.currentStatus
                return
            }

            if (stderr) {
                showNotification(root.icons.error, stderr, stdout)
            } else {
                root.currentStatus = root.desiredStatus
                showNotification(root.icons[root.currentStatus], i18n("Status switched to %1.", root.currentStatus.toUpperCase()))
            }
        }
    }


    // Connection for finding the notification tool
    Connections {
        target: findNotificationToolDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){

            if (stdout) {
                // Many Linux distros have two notification tools
                var paths = stdout.trim().split("\n")
                var path1 = paths[0]
                var path2 = paths[1]

                // Prefer notify-send because it allows using an icon; zenity v3.44.0 does not accept an icon option
                if (path1 && path1.trim().endsWith("notify-send")) {
                    root.notificationTool = "notify-send"
                } else if (path2 && path2.trim().endsWith("notify-send")) {
                    root.notificationTool = "notify-send"
                } else if (path1 && path1.trim().endsWith("zenity")) {
                    root.notificationTool = "zenity"
                } else {
                    console.warn("No compatible notification tool found.")
                }
            }
        }
    }


    // Connection for finding the Asus Battery Health configuration file
    Connections {
        target: findBatteryHelthConfigFileDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){
            // We assume that there can only be a single charge_control_end_threshold file.

            if (stdout.trim()) {
                root.batteryHelthConfigPath = stdout.trim()
                queryStatus()
            }else {
                root.isCompatible = false
                root.icon = root.icons.error
            }
        }
    }


    // Get the current status by executing the queryStatusDataSource
    function queryStatus() {
        root.loading = true
        queryStatusDataSource.exec()
    }

    // Switch Asus Battery Health Charging status
    function switchStatus() {
        root.loading = true

        showNotification(root.icons[root.desiredStatus], i18n("Switching status to %1.", root.desiredStatus.toUpperCase()))

        setStatusDataSource.status = root.desiredStatus
        setStatusDataSource.exec()
    }

    // Show a notification with icon, message, and title
    function showNotification(iconURL: string, message: string, title = i18n("Asus Battery Health Switcher"), options = ""){
        sendNotification.tool = root.notificationTool

        sendNotification.iconURL = iconURL
        sendNotification.title = title
        sendNotification.message = message
        sendNotification.options = options

        sendNotification.exec()
    }

    // Find the notification tool by executing the findNotificationToolDataSource
    function findNotificationTool() {
        findNotificationToolDataSource.exec()
    }

    // Find the Asus Battery Health configuration file by executing the findBatteryHelthConfigFileDataSource
    function findBatteryHelthConfigFile() {
        // Check if the user defined the file path manually and use it if he did.
        if(Plasmoid.configuration.batteryHelthConfigFile){
            root.batteryHelthConfigPath = Plasmoid.configuration.batteryHelthConfigFile
        }else{
            findBatteryHelthConfigFileDataSource.exec()
        }

    }

    // Set the preferred representation of the Plasmoid to the compact representation
    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

    // Compact representation of the Plasmoid
    Plasmoid.compactRepresentation: Item {
        PlasmaCore.IconItem {
            height: Plasmoid.configuration.iconSize
            width: Plasmoid.configuration.iconSize
            anchors.centerIn: parent

            source: root.icon
            active: compactMouse.containsMouse

            MouseArea {
                id: compactMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    plasmoid.expanded = !plasmoid.expanded
                }
            }
        }
    }

    // Full representation of the Plasmoid
    Plasmoid.fullRepresentation: Item {
        Layout.preferredWidth: 400 * PlasmaCore.Units.devicePixelRatio
        Layout.preferredHeight: 300 * PlasmaCore.Units.devicePixelRatio

        ColumnLayout {
            anchors.centerIn: parent

            Image {
                id: mode_image
                source: root.icon
                Layout.alignment: Qt.AlignCenter
                Layout.preferredHeight: 64
                fillMode: Image.PreserveAspectFit
            }


            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignCenter
                text: root.isCompatible ? i18n("Asus Battery Health Charging is set to %1.", root.currentStatus.toUpperCase()) : i18n("The Asus Battery Health Charging feature is not available.")
            }


            PlasmaComponents3.ComboBox {
                Layout.alignment: Qt.AlignCenter

                enabled: !root.loading && root.isCompatible
                model: [
                    {text: "Full Capacity", value: "full"},
                    {text: "Balanced (80%)", value: "balanced"},
                    {text: "Maximum Lifespan (60%)", value: "maximum"}
                ]
                textRole: "text"
                valueRole: "value"
                currentIndex: model.findIndex((element) => element.value === root.desiredStatus)

                onCurrentIndexChanged: {
                    root.desiredStatus = model[currentIndex].value
                    if (root.desiredStatus !== root.currentStatus) {
                        switchStatus()
                    }
                }
            }

            BusyIndicator {
                id: loadingIndicator
                Layout.alignment: Qt.AlignCenter
                running: root.loading
            }

        }
    }

    // Main tooltip text for the Plasmoid
    Plasmoid.toolTipMainText: i18n("Switch Asus Battery Health Charging.")

    // Subtext for the tooltip, indicating the current status
    Plasmoid.toolTipSubText: root.isCompatible ? i18n("Asus Battery Health Charging is set to %1.", root.currentStatus.toUpperCase()) : i18n("The Asus Battery Health Charging feature is not available.")
}
