import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property string helperPath: ""
  property bool folderMutationBusy: false
  property string state: "checking"
  property string label: "Checking"
  property string executablePath: ""
  property bool serviceAvailable: false
  property bool serviceRunning: false
  property bool operationRunning: false
  property bool refreshing: false
  property bool packageActionRunning: false
  property string packageStatus: ""
  property string packageError: ""
  property string controlError: ""
  property int _desiredServiceState: -1
  property bool _operationSeen: false
  property string _statusOutput: ""
  property string _statusErrorOutput: ""
  property string _controlErrorOutput: ""

  readonly property bool serviceActive: _desiredServiceState === -1
    ? serviceRunning : _desiredServiceState === 1
  readonly property bool serviceActionRunning: controlProcess.running
  readonly property bool canUseRuntime: state === "existing"
    && executablePath !== ""
  readonly property bool canControlService: canUseRuntime && serviceAvailable
  readonly property bool lifecycleBusy: refreshing || packageActionRunning
    || serviceActionRunning || folderMutationBusy
  readonly property bool canInstall: state === "missing" && !lifecycleBusy

  signal runtimeUnavailable(string phase)
  signal runtimeAvailable
  signal serviceStarting
  signal serviceStopping
  signal serviceStarted

  function updateStatus() {
    if (statusProcess.running) return
    refreshing = true
    packageError = ""
    _statusOutput = ""
    _statusErrorOutput = ""
    statusProcess.running = true
  }

  function applyStatus(text) {
    var data
    try {
      data = JSON.parse(String(text || ""))
    } catch (error) {
      packageError = "Could not read Syncthing installation status"
      return false
    }
    var nextState = String(data.state || "")
    if (["existing", "incomplete", "missing"].indexOf(nextState) < 0) {
      packageError = "Syncthing installation status is invalid"
      return false
    }
    state = nextState
    label = String(data.label || "Unavailable")
    executablePath = String(data.executable || "")
    serviceAvailable = data.serviceAvailable === true
    serviceRunning = data.serviceRunning === true
    operationRunning = data.operationRunning === true
    reconcileDesiredServiceState()
    reconcilePackageOperation()
    if (!canUseRuntime) runtimeUnavailable(state)
    else if (serviceAvailable && !serviceActive) runtimeUnavailable("stopped")
    else runtimeAvailable()
    return true
  }

  function reconcileDesiredServiceState() {
    if (_desiredServiceState === -1) return
    var expectedRunning = _desiredServiceState === 1
    if (serviceRunning === expectedRunning) {
      _desiredServiceState = -1
    } else if (!controlProcess.running) {
      _desiredServiceState = -1
      controlError = expectedRunning
        ? "Syncthing did not start" : "Syncthing did not stop"
    }
  }

  function reconcilePackageOperation() {
    if (packageActionRunning && operationRunning) _operationSeen = true
    if (!packageActionRunning || !_operationSeen || operationRunning) return
    packageActionRunning = false
    packageStatus = "Installation terminal closed"
    _operationSeen = false
    operationPollTimer.stop()
    packageMessageTimer.restart()
  }

  function install() {
    if (!canInstall) return
    packageActionRunning = true
    packageError = ""
    packageStatus = "Complete installation in the Omarchy terminal"
    operationPollTimer.ticks = 0
    _operationSeen = false
    operationPollTimer.start()
    Quickshell.execDetached(["bash", helperPath, "install"])
  }

  function toggleService() {
    if (!canControlService || controlProcess.running || folderMutationBusy) return
    var start = !serviceActive
    _desiredServiceState = start ? 1 : 0
    controlError = ""
    _controlErrorOutput = ""
    controlProcess.command = [
      "systemctl", "--user", start ? "start" : "stop", "syncthing.service"
    ]
    if (start) serviceStarting()
    else serviceStopping()
    controlProcess.running = true
  }

  property Timer statusTimer: Timer {
    interval: 15000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.updateStatus()
  }

  property Timer operationPollTimer: Timer {
    property int ticks: 0
    interval: 1500
    repeat: true
    onTriggered: {
      ticks++
      root.updateStatus()
      if (ticks >= 10 && !root._operationSeen) {
        stop()
        root.packageActionRunning = false
        root.packageStatus = ""
        root.packageError = "The installation terminal did not start"
      }
    }
  }

  property Timer packageMessageTimer: Timer {
    interval: 3000
    repeat: false
    onTriggered: root.packageStatus = ""
  }

  property Process statusProcess: Process {
    id: statusProcess
    command: ["bash", root.helperPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._statusOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._statusErrorOutput = text
    }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode === 0) {
        root.applyStatus(root._statusOutput)
      } else {
        root.packageError = String(root._statusErrorOutput
          || "Could not check Syncthing installation").trim()
      }
    }
  }

  property Process controlProcess: Process {
    id: controlProcess
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._controlErrorOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.controlError = String(root._controlErrorOutput
          || "Could not change Syncthing service state").trim()
        root._desiredServiceState = -1
      } else if (root.serviceActive) {
        root.serviceStarted()
      }
      root.updateStatus()
    }
  }
}
