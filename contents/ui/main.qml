import QtQuick 2.0
import QtQuick.Layouts 1.0
import QtQuick.Controls 2.0
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0


Item {
    id: root

    property string pkexecPath: "/usr/bin/pkexec"

    property string batteryHelthConfigPath

    readonly property var const_COMMANDS: ({
        "query": "cat " + root.batteryHelthConfigPath,
        "maximum": "echo 60 | " + root.pkexecPath + " tee " + root.batteryHelthConfigPath + " 1>/dev/null",
        "balanced": "echo 80 | " + root.pkexecPath + " tee " + root.batteryHelthConfigPath + " 1>/dev/null",
        "full": "echo 100 | " + root.pkexecPath + " tee " + root.batteryHelthConfigPath + " 1>/dev/null",
        "findBatteryHelthConfigFile": "find /home/eniel -name \"charge_control_end_threshold\"",
        "findNotificationTool": "find /usr -type f -executable \\( -name \"notify-send\" -o -name \"zenity\" \\)",
        // defined in findNotificationTool Connection
        "sendNotification": () => ""
    })

    property var icons: ({
        "maximum": Qt.resolvedUrl("./image/maximum.png"),
        "balanced": Qt.resolvedUrl("./image/balanced.png"),
        "full": Qt.resolvedUrl("./image/full.png"),
        "error": Qt.resolvedUrl("./image/error.png")
    })

    // This values can change after the execution of onCompleted().
    property string currentStatus: "full"
    property bool isCompatible: false

    property string desiredStatus
    property bool loading: false

    property string icon: root.icons[root.currentStatus]

    Plasmoid.icon: root.icon

    Connections {
        target: Plasmoid.configuration
    }

    Component.onCompleted: {
        findNotificationTool()
        findBatteryHelthConfigFile()
    }

    PlasmaCore.DataSource {
        id: queryStatusDataSource
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var exitStatus = data["exit status"]
            var stdout = data["stdout"]
            var stderr = data["stderr"]

            exited(exitCode, exitStatus, stdout, stderr)
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }

        signal exited(int exitCode, int exitStatus, string stdout, string stderr)
    }


    PlasmaCore.DataSource {
        id: setStatusDataSource
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var exitStatus = data["exit status"]
            var stdout = data["stdout"]
            var stderr = data["stderr"]

            exited(exitCode, exitStatus, stdout, stderr)
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }

        signal exited(int exitCode, int exitStatus, string stdout, string stderr)
    }


    PlasmaCore.DataSource {
        id: findNotificationToolDataSource
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var exitStatus = data["exit status"]
            var stdout = data["stdout"]
            // stderr output can contain "permission denied" errors
            var stderr = data["stderr"]

            exited(exitCode, exitStatus, stdout, stderr)
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }

        signal exited(int exitCode, int exitStatus, string stdout, string stderr)
    }


    PlasmaCore.DataSource {
        id: findBatteryHelthConfigFileDataSource
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var exitStatus = data["exit status"]
            var stdout = data["stdout"]
            // stderr output can contain "permission denied" errors
            var stderr = data["stderr"]

            exited(exitCode, exitStatus, stdout, stderr)
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }

        signal exited(int exitCode, int exitStatus, string stdout, string stderr)
    }


    PlasmaCore.DataSource {
        id: sendNotification
        engine: "executable"
        connectedSources: []

        onNewData: {
            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }
    }


    Connections {
        target: queryStatusDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){
            root.loading = false

            if (stderr) {
                root.icon = root.icons.error
                showNotification(root.icons.error, stderr, stderr)
            } else {
                var value = stdout.trim()
                root.currentStatus = value === "60" ? "maximum" : value === "80" ? "balanced" : "full"
                root.isCompatible = true
            }
        }
    }


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


    Connections {
        target: findNotificationToolDataSource
        function onExited(exitCode, exitStatus, stdout, stderr){

            if (stdout) {
                // Many Linux distros have two notification tools
                var paths = stdout.trim().split("\n")
                var path1 = paths[0]
                var path2 = paths[1]

                // prefer notify-send because it allows to use icon, zenity v3.44.0 does not accept icon option
                if (path1 && path1.trim().endsWith("notify-send")) {
                    const_COMMANDS.sendNotification = (title, message, iconURL, options) => path1.trim() + " -i " + iconURL + " '" + title + "' '" + message + "'" + options
                }if (path2 && path2.trim().endsWith("notify-send")) {
                    const_COMMANDS.sendNotification = (title, message, iconURL, options) => path2.trim() + " -i " + iconURL + " '" + title + "' '" + message + "'" + options
                }else if (path1 && path1.trim().endsWith("zenity")) {
                    const_COMMANDS.sendNotification = (title, message, iconURL, options) => path1.trim() + " --notification --text='" + title + "\\n" + message + "'"
                }
            }
        }
    }


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


    // Get the current status
    function queryStatus() {
        root.loading = true
        queryStatusDataSource.exec(const_COMMANDS.query)
    }

    // status = "full"|"balanced"|"maximum"
    function switchStatus(status: string) {
        root.desiredStatus = status
        root.loading = true

        showNotification(root.icons[status], i18n("Switching status to %1.", status.toUpperCase()))

        setStatusDataSource.exec(const_COMMANDS[status])
    }

    function showNotification(iconURL: string, message: string, title = i18n("Battery Health Switcher"), options = ""){
        sendNotification.exec(const_COMMANDS.sendNotification(title, message, iconURL, options))
    }

    function findNotificationTool() {
        findNotificationToolDataSource.exec(const_COMMANDS.findNotificationTool)
    }

    function findBatteryHelthConfigFile() {
        // Check if the user defined the file path manually and use it if he did.
        if(Plasmoid.configuration.batteryHelthConfigFile){
            root.batteryHelthConfigPath = Plasmoid.configuration.batteryHelthConfigFile
        }else{
            findBatteryHelthConfigFileDataSource.exec(const_COMMANDS.findBatteryHelthConfigFile)
        }

    }

    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

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
                text: root.isCompatible ? i18n("Battery Health Charging is set to %1.", root.currentStatus.toUpperCase()) : i18n("The Battery Health Charging feature is not available.")
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
                currentIndex: model.findIndex((element) => element.value === root.currentStatus)

                onCurrentIndexChanged: {
                    if (currentValue && currentValue !== root.currentStatus) {
                        switchStatus(currentValue)
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

    Plasmoid.toolTipMainText: i18n("Switch Battery Health Charging.")
    Plasmoid.toolTipSubText: root.isCompatible ? i18n("Battery Health Charging is set to %1.", root.currentStatus.toUpperCase()) : i18n("The Battery Health Charging feature is not available.")
}
