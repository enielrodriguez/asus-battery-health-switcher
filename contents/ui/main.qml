import QtQuick 2.0
import QtQuick.Layouts 1.0
import QtQuick.Controls 2.0
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
 

PlasmoidItem {
    id: root

    // Icons for different status: "maximum," "balanced," "full," and "error"
    property var icons: ({
        "maximum": Qt.resolvedUrl("./image/maximum.png"),
        "balanced": Qt.resolvedUrl("./image/balanced.png"),
        "full": Qt.resolvedUrl("./image/full.png"),
        "error": Qt.resolvedUrl("./image/error.png")
    })

    // The desired status for Asus Battery Health Charging
    property string desiredStatus: ""

    // A flag indicating if an operation is in progress
    property bool loading: false

    // The currently displayed icon based on the current status. Default to error (incompatible)
    property string icon: root.icons["error"]
    // Set the icon for the Plasmoid
    Plasmoid.icon: root.icon

    // Executed when the component is completed
    Component.onCompleted: {
        init()
    }    

    // CustomDataSource for querying the current Asus Battery Health Charging status
    CustomDataSource {
        id: queryStatusDataSource
        command: "cat " + plasmoid.configuration.batteryHealthConfigPath
    }

    // CustomDataSource for setting the Asus Battery Health Charging status
    CustomDataSource {
        id: setStatusDataSource

        // Dynamically set in switchStatus(). Set a default value to avoid errors at startup.
        property string status: "full"

        // Commands to set different Asus Battery Health Charging modes
        property var cmds: {
            "maximum": `echo 60 | ${plasmoid.configuration.elevatedPivilegesTool} tee ${plasmoid.configuration.batteryHealthConfigPath} 1>/dev/null`,
            "balanced": `echo 80 | ${plasmoid.configuration.elevatedPivilegesTool} tee ${plasmoid.configuration.batteryHealthConfigPath} 1>/dev/null`,
            "full": `echo 100 | ${plasmoid.configuration.elevatedPivilegesTool} tee ${plasmoid.configuration.batteryHealthConfigPath} 1>/dev/null`
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
        id: findBatteryHealthConfigFileDataSource
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
            "zenity": `zenity --notification --text='${title}\\n${message}'`
        }
        command: cmds[tool]
    }


    // Connection for handling the queryStatusDataSource
    Connections {
        target: queryStatusDataSource
        function onExited(exitCode, exitStatus, stdout, stderr) {
            root.loading = false
    
            if (stderr) {
                root.icon = root.icons.error
                showNotification(root.icons.error, stderr, stderr)
                return
            }
    
            var value = stdout.trim()
            var statusMap = {
                "60": "maximum",
                "80": "balanced",
                "100": "full"
            }
            
            var currentStatus = statusMap[value]
            var savedStatus = plasmoid.configuration.currentStatus
    
            if (savedStatus && savedStatus !== currentStatus) {
                root.desiredStatus = savedStatus
                switchStatus()
            } else {
                plasmoid.configuration.currentStatus = root.desiredStatus = currentStatus
                refreshIcon()
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
                root.desiredStatus = plasmoid.configuration.currentStatus
                return
            }

            if (stderr) {
                showNotification(root.icons.error, stderr, stdout)
                return
            }
            
            plasmoid.configuration.currentStatus = root.desiredStatus
            refreshIcon()
            showNotification(root.icons[plasmoid.configuration.currentStatus], i18n("Status switched to %1.", plasmoid.configuration.currentStatus.toUpperCase()))
            
        }
    }


    // Connection for finding the notification tool
    Connections {
        target: findNotificationToolDataSource
        function onExited(exitCode, exitStatus, stdout, stderr) {
            root.loading = false
    
            var notificationTool = ""
            const NOTIFY_SEND = "notify-send"
            const ZENITY = "zenity"
    
            if (stdout) {
                var paths = stdout.trim().split("\n")
    
                // Many Linux distros have two notification tools: notify-send and zenity
                // Prefer notify-send because it allows using an icon; zenity v3.44.0 does not accept an icon option
                for (let currentPath of paths) {
                    currentPath = currentPath.trim()
    
                    if (currentPath.endsWith(NOTIFY_SEND)) {
                        notificationTool = NOTIFY_SEND
                        break
                    } else if (currentPath.endsWith(ZENITY)) {
                        notificationTool = ZENITY
                    }
                }
            }
    
            if (notificationTool) {
                plasmoid.configuration.notificationToolPath = notificationTool
            } else {
                console.warn("No compatible notification tool found.")
            }
    
            findBatteryHealthConfigFile()
        }
    }
    


    // Connection for finding the Asus Battery Health configuration file
    Connections {
        target: findBatteryHealthConfigFileDataSource
        function onExited(exitCode, exitStatus, stdout, stderr) {
            root.loading = false
    
            const trimmedOutput = stdout.trim()
    
            // We assume that there can only be a single charge_control_end_threshold file.
            if (trimmedOutput) {
                plasmoid.configuration.batteryHealthConfigPath = trimmedOutput
                plasmoid.configuration.isCompatible = true
                queryStatus()
            } else {
                root.icon = root.icons.error
            }
        }
    }

    Connections {
        target: plasmoid.configuration
        function onBatteryHealthConfigPathChanged(){
            if(plasmoid.configuration.batteryHealthConfigPath){
                plasmoid.configuration.isCompatible = true
            }else {
                plasmoid.configuration.isCompatible = false
            }
            findBatteryHealthConfigFile()
        }
    }


    function refreshIcon(){
        root.icon = root.icons[plasmoid.configuration.currentStatus ? plasmoid.configuration.currentStatus : "error"]
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
        if(plasmoid.configuration.notificationToolPath){
            sendNotification.tool = plasmoid.configuration.notificationToolPath

            sendNotification.iconURL = iconURL
            sendNotification.title = title
            sendNotification.message = message
            sendNotification.options = options

            sendNotification.exec()
        }else{
            console.warn(title + ": " + message)
        }
    }

    // Find the notification tool and init the process
    function init() {
        if(!plasmoid.configuration.notificationToolPath){
            findNotificationToolDataSource.exec()
        } else {
            findBatteryHealthConfigFile ()
        }
    }

    // Find the Asus Battery Health configuration file by executing the findBatteryHealthConfigFileDataSource
    function findBatteryHealthConfigFile() {
        if(!plasmoid.configuration.batteryHealthConfigPath && !plasmoid.configuration.isCompatible){
            root.loading = true
            findBatteryHealthConfigFileDataSource.exec()
            return
        }

        queryStatus()
        
    }

    // Compact representation of the Plasmoid
    compactRepresentation: Item {
        Kirigami.Icon {
            height: plasmoid.configuration.iconSize
            width: plasmoid.configuration.iconSize
            anchors.centerIn: parent

            source: root.icon
            active: compactMouse.containsMouse

            MouseArea {
                id: compactMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    expanded = !expanded
                }
            }
        }
    }

    // Full representation of the Plasmoid
    fullRepresentation: Item {
        Layout.preferredWidth: 400
        Layout.preferredHeight: 300

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
                text: plasmoid.configuration.isCompatible ? i18n("Asus Battery Health Charging is set to %1.", plasmoid.configuration.currentStatus.toUpperCase()) : i18n("The Asus Battery Health Charging feature is not available.")
            }


            PlasmaComponents3.ComboBox {
                Layout.alignment: Qt.AlignCenter

                enabled: !root.loading && plasmoid.configuration.isCompatible
                model: ListModel {
                        ListElement { text: "Full Capacity"; value: "full" }
                        ListElement { text: "Balanced (80%)"; value: "balanced" }
                        ListElement { text: "Maximum Lifespan (60%)"; value: "maximum" }
                }
                
                textRole: "text"
                valueRole: "value"

                Component.onCompleted: {
                    // Manually iterate to find the index
                    for (var i = 0; i < model.count; i++) {
                        if (model.get(i).value === root.desiredStatus) {
                            currentIndex = i;
                            break;
                        }
                    }
                }

                onActivated: {
                    root.desiredStatus = currentValue
                    if (plasmoid.configuration.currentStatus && root.desiredStatus !== plasmoid.configuration.currentStatus) {
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
    toolTipMainText: i18n("Switch Asus Battery Health Charging.")

    // Subtext for the tooltip, indicating the current status
    toolTipSubText: plasmoid.configuration.isCompatible ? i18n("Asus Battery Health Charging is set to %1.", plasmoid.configuration.currentStatus.toUpperCase()) : i18n("The Asus Battery Health Charging feature is not available.")
}
