import QtQuick
import Quickshell
import Quickshell.Io
import "SyncthingApi.js" as Api

QtObject {
  id: root

  readonly property string baseUrl: (_useTls ? "https" : "http")
    + "://127.0.0.1:8384"
  readonly property string apiHelperPath: localPath(
    Qt.resolvedUrl("scripts/syncthing-api.sh"))
  readonly property string helperPath: localPath(
    Qt.resolvedUrl("scripts/syncthing-install.sh"))
  property string phase: "discovering"
  property string lastError: ""
  property bool refreshing: false
  property int refreshIntervalSec: 60
  property var connections: ({})
  property var devices: []
  property var folders: []
  property var pendingFolders: ({})
  property var folderStatuses: ({})
  property string localDeviceId: ""
  property var syncingFiles: []
  property var syncActions: ({})

  property bool folderMutationBusy: false
  property string folderMutationId: ""
  property string folderMutationAction: ""
  property string folderMutationError: ""
  property string folderMutationNotice: ""
  property string recentlyLinkedFolderId: ""
  property bool folderPreparationBusy: false
  property string folderPreparationError: ""
  property string folderIdSuggestion: ""
  property bool restartRequired: false

  property string installationState: "checking"
  property string installationLabel: "Checking"
  property string executablePath: ""
  property bool serviceAvailable: false
  property bool serviceRunning: false
  property bool operationRunning: false
  property bool packageRefreshing: false
  property bool packageActionRunning: false
  property string packageStatus: ""
  property string packageError: ""
  property string controlError: ""
  readonly property string recoveryWarning: _recoveryActive
    ? (_apiKey ? "Refreshing Syncthing state" : "Trying to find local API key")
      + [".", "..", "..."][_recoveryDotCount] : ""
  readonly property string syncActivityDots: syncingFiles.length > 0
    ? [".  ", ".. ", "..."][_syncDotCount] : ""
  readonly property string syncActivityPath: syncingFiles.length > 0
    ? syncTokenParts(syncingFiles[_syncFileIndex % syncingFiles.length])[1] : ""
  readonly property string syncActivityFolderId: syncingFiles.length > 0
    ? syncTokenParts(syncingFiles[_syncFileIndex % syncingFiles.length])[0] : ""
  readonly property string syncActivityFileName: syncingFiles.length > 0
    ? displayFileName(syncActivityPath) : ""
  readonly property string syncActivityAction: syncingFiles.length > 0
    ? String(syncActions[
      syncingFiles[_syncFileIndex % syncingFiles.length]] || "syncing") : ""
  readonly property string syncActivityDetail: {
    if (!syncActivityFileName) return ""
    if (syncActivityAction === "removing") {
      return "Removing " + syncActivityFileName
    }
    if (syncActivityAction === "upload") {
      return "Upload " + syncActivityFileName
    }
    return syncActivityFileName
  }
  readonly property string syncActivity: syncingFiles.length > 0
    ? "File syncing" + syncActivityDots + " " + syncActivityDetail : ""

  property string _apiKey: ""
  property bool _useTls: false
  property bool _recoveryActive: false
  property bool _apiKeyFailureLatched: false
  property int _apiKeyAttempts: 0
  property int _recoveryDotCount: 0
  property int _recoveryTicks: 0
  property bool _finishRecoveryAfterRefresh: false
  property int _generation: 0
  property int _pendingRequests: 0
  property bool _connectionRefreshing: false
  property var _localSyncFiles: []
  property var _remoteSyncFiles: ({})
  property var _changeSyncFiles: []
  property var _changeSyncActions: ({})
  property int _syncDotCount: 0
  property int _syncFileIndex: 0
  property int _syncEventSince: 0
  property bool _syncEventsInitialized: false
  property bool _syncEventPolling: false
  property int _syncEventGeneration: 0
  property var _syncEventRequest: null
  property var _requests: []
  property string _keyOutput: ""
  property string _packageOutput: ""
  property string _packageErrorOutput: ""
  property string _controlErrorOutput: ""
  property string _folderPathOutput: ""
  property string _folderPathErrorOutput: ""
  property var _pendingFolderAdd: null
  property var _folderMutationRequest: null
  property var _folderPreparationRequest: null
  property int _folderMutationGeneration: 0
  property int _desiredServiceState: -1
  property bool _operationSeen: false

  readonly property bool online: phase === "ready"
  readonly property bool serviceActive: _desiredServiceState === -1
    ? serviceRunning : _desiredServiceState === 1
  readonly property bool serviceActionRunning: controlProcess.running
  readonly property bool canUseRuntime: installationState === "existing"
    && executablePath !== ""
  readonly property bool canControlService: canUseRuntime && serviceAvailable
  readonly property bool lifecycleBusy: packageRefreshing || packageActionRunning
    || serviceActionRunning || folderMutationBusy
  readonly property bool canInstall: installationState === "missing"
    && !lifecycleBusy
  readonly property int folderCount: folders.length
  readonly property int deviceCount: devices.length
  readonly property int connectedDeviceCount: countConnectedDevices()
  readonly property int folderProblemCount: countFolderProblems()
  readonly property int syncingFolderCount: countSyncingFolders()
  readonly property string summaryText: summary()

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function displayFileName(path) {
    var parts = String(path || "").split(/[\\/]/)
    return parts.length ? parts[parts.length - 1] : ""
  }

  function syncToken(folder, path) {
    return JSON.stringify([String(folder || ""), String(path || "")])
  }

  function syncTokenParts(token) {
    try {
      var parts = JSON.parse(String(token || ""))
      if (parts instanceof Array && parts.length === 2) {
        return [String(parts[0] || ""), String(parts[1] || "")]
      }
    } catch (error) {
    }
    return ["", String(token || "")]
  }

  function countConnectedDevices() {
    var count = 0
    var values = connections && connections.connections
      ? connections.connections : {}
    for (var i = 0; i < devices.length; i++) {
      var id = String((devices[i] || {}).deviceID || "")
      if (id && id === localDeviceId) count++
      else if (id && values[id] && values[id].connected === true) count++
    }
    return count
  }

  function countFolderProblems() {
    var count = 0
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      var status = folderStatuses[ids[i]] || {}
      if (status.state === "error" || status.error
          || Number(status.errors || 0) > 0
          || Number(status.pullErrors || 0) > 0) count++
    }
    return count
  }

  function countSyncingFolders() {
    var count = 0
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      if (Number((folderStatuses[ids[i]] || {}).needTotalItems || 0) > 0) {
        count++
      }
    }
    return count
  }

  function summary() {
    if (installationState === "missing") return "Syncthing is not installed"
    if (installationState === "incomplete") {
      return "Installation needs cleanup"
    }
    if (serviceAvailable && !serviceActive) return "Syncing stopped"
    if (phase === "discovering") return "Finding Syncthing"
    if (phase === "loading") return "Reading status"
    if (phase === "error") return "Syncthing unavailable"
    if (folderProblemCount > 0) return folderProblemCount + " folder problem"
      + (folderProblemCount === 1 ? "" : "s")
    if (syncingFolderCount > 0) return syncingFolderCount + " folder"
      + (syncingFolderCount === 1 ? "" : "s") + " syncing"
    return "Up to date"
  }

  function setRefreshInterval(seconds) {
    var value = parseInt(String(seconds), 10)
    if (!isFinite(value)) value = 60
    refreshIntervalSec = Math.max(60, Math.min(3600, value))
  }

  function refresh() {
    _apiKeyFailureLatched = false
    if (phase === "error") lastError = ""
    updateInstallationStatus()
    refreshApi()
  }

  function refreshApi() {
    if (installationState === "checking") return
    if (!canUseRuntime) {
      stopApi(installationState)
      return
    }
    if (serviceAvailable && !serviceActive) {
      stopApi("stopped")
      return
    }
    if (!_apiKey) {
      discoverApiKey()
      return
    }

    _generation++
    abortRequests()
    phase = "loading"
    lastError = ""

    fetch("getSystemStatus", {}, function(data) {
      root.localDeviceId = String((data || {}).myID || "")
    })
    fetch("getConnections", {}, function(data) {
      root.connections = data || ({})
    })
    fetch("getDevices", {}, function(data) {
      root.devices = data instanceof Array ? data : []
    })
    fetch("getPendingFolders", {}, function(data) {
      root.pendingFolders = data || ({})
    })
    fetch("getRestartRequired", {}, function(data) {
      root.restartRequired = !!((data || {}).requiresRestart)
    })
    fetch("getFolders", {}, function(data) {
      root.folders = data instanceof Array ? data : []
      root.folderStatuses = ({})
      for (var i = 0; i < root.folders.length; i++) {
        root.fetchFolder(root.folders[i].id)
      }
    })
  }

  function stopApi(nextPhase) {
    if (folderMutationBusy) {
      cancelFolderMutation("Folder operation stopped because Syncthing became unavailable")
    }
    if (_folderPreparationRequest) {
      try {
        _folderPreparationRequest.abort()
      } catch (error) {
      }
    }
    _folderPreparationRequest = null
    folderPreparationBusy = false
    _generation++
    abortRequests()
    stopRecovery()
    _apiKeyFailureLatched = false
    _apiKey = ""
    connections = ({})
    devices = []
    folders = []
    pendingFolders = ({})
    folderStatuses = ({})
    recentlyLinkedFolderId = ""
    root.recentlyLinkedTimer.stop()
    localDeviceId = ""
    restartRequired = false
    stopSyncEvents()
    phase = nextPhase
    lastError = ""
  }

  function fetchFolder(folderId, showProgress) {
    fetch("getFolderStatus", { query: { folder: folderId } }, function(data) {
      root.setFolderStatus(folderId, data || ({}))
    }, function(error) {
      root.setFolderStatus(folderId, {
        state: "error",
        error: error.message
      })
    }, showProgress)
  }

  function refreshFolderStatuses(showProgress) {
    if (!_apiKey || !canUseRuntime
        || (serviceAvailable && !serviceActive)) return
    for (var i = 0; i < folders.length; i++) {
      fetchFolder(folders[i].id, showProgress)
    }
  }

  function setFolderStatus(folderId, status) {
    var next = ({})
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      next[ids[i]] = folderStatuses[ids[i]]
    }
    next[String(folderId)] = status
    folderStatuses = next
  }

  function configuredFolder(folderId) {
    var wanted = String(folderId || "")
    for (var i = 0; i < folders.length; i++) {
      if (String((folders[i] || {}).id || "") === wanted) return folders[i]
    }
    return null
  }

  function configuredDevice(deviceId) {
    var wanted = String(deviceId || "")
    for (var i = 0; i < devices.length; i++) {
      if (String((devices[i] || {}).deviceID || "") === wanted) {
        return devices[i]
      }
    }
    return null
  }

  function resolveFolderPath(value) {
    var path = String(value || "")
    var home = Quickshell.env("HOME")
    if (path === "~") return home
    if (path.indexOf("~/") === 0) return home + path.slice(1)
    if (path.charAt(0) === "/" || !home) return path
    return home + "/" + path
  }

  function safeErrorMessage(error, fallback) {
    var message = ""
    var body = error ? error.body : null
    if (typeof body === "string") message = body.trim()
    else if (body && body.error) message = String(body.error)
    else if (body && body.message) message = String(body.message)
    if (!message && error && error.message) message = String(error.message)
    if (!message) message = fallback || "Syncthing rejected the operation"
    return message.replace(
      /(?:[A-Z2-7]{7}-){7}[A-Z2-7]{7}/g,
      function(value) { return value.slice(0, 7) + "-REDACTED" })
  }

  function clearFolderMutationMessage() {
    folderMutationNoticeTimer.stop()
    folderMutationError = ""
    folderMutationNotice = ""
  }

  function clearFolderMutationNotice() {
    folderMutationNoticeTimer.stop()
    folderMutationNotice = ""
  }

  function notifyFolderResult(message) {
    if (!message) return
    Quickshell.execDetached([
      "omarchy-notification-send",
      "Syncthing",
      String(message)
    ])
  }

  function requestFolderIdSuggestion() {
    if (folderPreparationBusy || !_apiKey || !online) return
    folderPreparationBusy = true
    folderPreparationError = ""
    folderIdSuggestion = ""
    try {
      _folderPreparationRequest = requestApi(
        "getRandomString",
        { query: { length: 10 } },
        function(data) {
          root._folderPreparationRequest = null
          root.folderPreparationBusy = false
          var random = String((data || {}).random || "")
          if (random.length !== 10) {
            root.folderPreparationError = "Syncthing did not return a folder ID"
            return
          }
          var suggestion = (random.slice(0, 5) + "-" + random.slice(5))
            .toLowerCase()
          if (root.configuredFolder(suggestion)) {
            root.folderPreparationError = "Generated folder ID already exists; try again"
            return
          }
          root.folderIdSuggestion = suggestion
        },
        function(error) {
          root._folderPreparationRequest = null
          root.folderPreparationBusy = false
          root.folderPreparationError = root.safeErrorMessage(
            error, "Could not generate a folder ID")
        })
    } catch (error) {
      _folderPreparationRequest = null
      folderPreparationBusy = false
      folderPreparationError = String(error)
    }
  }

  function beginFolderMutation(action, folderId) {
    if (folderMutationBusy) return false
    if (!_apiKey || !online) {
      folderMutationError = "Syncthing must be online to manage folders"
      return false
    }
    folderMutationBusy = true
    folderMutationAction = String(action || "")
    folderMutationId = String(folderId || "")
    folderMutationError = ""
    folderMutationNoticeTimer.stop()
    folderMutationNotice = ""
    _folderMutationGeneration++
    return true
  }

  function finishFolderMutation(notice) {
    _folderMutationRequest = null
    _pendingFolderAdd = null
    folderMutationBusy = false
    folderMutationAction = ""
    folderMutationId = ""
    folderMutationNotice = String(notice || "")
    if (folderMutationNotice) folderMutationNoticeTimer.restart()
    else folderMutationNoticeTimer.stop()
    notifyFolderResult(folderMutationNotice)
    refreshApi()
  }

  function failFolderMutation(error, fallback) {
    _folderMutationRequest = null
    _pendingFolderAdd = null
    folderPathProcess.running = false
    folderDirectoryProcess.running = false
    folderMutationBusy = false
    folderMutationAction = ""
    folderMutationId = ""
    folderMutationError = safeErrorMessage(error, fallback)
    if (error && error.status === 403) _apiKey = ""
    refreshApi()
  }

  function cancelFolderMutation(reason) {
    _folderMutationGeneration++
    if (_folderMutationRequest) {
      try {
        _folderMutationRequest.abort()
      } catch (error) {
      }
    }
    _folderMutationRequest = null
    folderPathProcess.running = false
    folderDirectoryProcess.running = false
    _pendingFolderAdd = null
    folderMutationBusy = false
    folderMutationAction = ""
    folderMutationId = ""
    if (reason) folderMutationError = String(reason)
  }

  function requestFolderMutation(name, options, onSuccess, fallback) {
    var generation = _folderMutationGeneration
    try {
      _folderMutationRequest = requestApi(
        name,
        options,
        function(data, xhr) {
          if (generation !== root._folderMutationGeneration
              || !root.folderMutationBusy) return
          root._folderMutationRequest = null
          onSuccess(data, xhr)
        },
        function(error) {
          if (generation !== root._folderMutationGeneration
              || !root.folderMutationBusy) return
          root.failFolderMutation(error, fallback)
        })
    } catch (error) {
      failFolderMutation(error, fallback)
    }
  }

  function setFolderLinked(folderId, linked) {
    var folder = configuredFolder(folderId)
    if (!folder) {
      folderMutationError = "The selected folder is no longer configured"
      return false
    }
    var shouldPause = !linked
    if (!!folder.paused === shouldPause) return true
    if (!beginFolderMutation(linked ? "link" : "unlink", folder.id)) {
      return false
    }
    var label = String(folder.label || folder.id)
    var expectedPath = String(folder.path || "")
    requestFolderMutation("getFolder", {
      path: { id: folder.id },
      acceptStatuses: [404]
    }, function(current, xhr) {
      if (xhr.status === 404) {
        root.failFolderMutation(null, "The folder is no longer configured")
        return
      }
      if (!current || String(current.path || "") !== expectedPath) {
        root.failFolderMutation(null,
          "The folder configuration changed; refresh and review it")
        return
      }
      root.requestFolderMutation("patchFolder", {
        method: "PATCH",
        path: { id: folder.id },
        json: { paused: shouldPause }
      }, function() {
        if (linked) {
          root.recentlyLinkedFolderId = folder.id
          root.recentlyLinkedTimer.restart()
          root.finishFolderMutation(
            "Linked " + label + ". Syncthing resumed the folder with its "
            + "existing sharing configuration.")
        } else {
          root.finishFolderMutation(
            "Synchronization for " + label + " paused. The folder ID, "
            + "device associations, and data remain.")
        }
      }, linked ? "Could not link the folder" : "Could not unlink the folder")
    }, linked ? "Could not verify the folder before linking it"
      : "Could not verify the folder before unlinking it")
    return true
  }

  function forgetFolder(folderId) {
    var folder = configuredFolder(folderId)
    if (!folder) {
      folderMutationError = "The selected folder is no longer configured"
      return false
    }
    if (!folder.paused) {
      folderMutationError = "Unlink the folder before forgetting it"
      return false
    }
    if (!beginFolderMutation("forget", folder.id)) return false
    var forgottenId = String(folder.id)
    var expectedPath = String(folder.path || "")
    var usesDefaultMarker = String(folder.markerName || ".stfolder") === ".stfolder"
    requestFolderMutation("getFolder", {
      path: { id: forgottenId },
      acceptStatuses: [404]
    }, function(current, xhr) {
      if (xhr.status === 404) {
        root.failFolderMutation(null,
          "The folder is no longer configured")
        return
      }
      if (!current || current.paused !== true) {
        root.failFolderMutation(null,
          "The folder is no longer unlinked; refresh and try again")
        return
      }
      if (String(current.path || "") !== expectedPath) {
        root.failFolderMutation(null,
          "The folder configuration changed; refresh and review it")
        return
      }
      root.requestFolderMutation("deleteFolder", {
        method: "DELETE",
        path: { id: forgottenId }
      }, function() {
        root.finishFolderMutation(
          "Removed from Syncthing configuration and the plugin view. The "
          + "directory and its data files were not deleted. "
          + (usesDefaultMarker
            ? "Syncthing also attempted to remove its internal .stfolder marker. "
            : "")
          + "Re-add Folder ID " + forgottenId
          + " to rejoin the same remote folder.")
      }, "Could not forget the folder")
    }, "Could not verify the folder before forgetting it")
    return true
  }

  function addFolder(path, label, folderId, selectedDeviceIds, pendingDeviceId) {
    var id = String(folderId || "")
    var rawPath = String(path || "")
    var requestedPath = resolveFolderPath(rawPath)
    if (!id.trim()) {
      folderMutationError = "Folder ID is required"
      return false
    }
    if (id !== id.trim()) {
      folderMutationError = "Folder ID cannot start or end with whitespace"
      return false
    }
    if (configuredFolder(id)) {
      folderMutationError = "Folder ID already exists"
      return false
    }
    if (!rawPath.trim()) {
      folderMutationError = "Folder path is required"
      return false
    }
    if (requestedPath.indexOf("\n") >= 0 || requestedPath.indexOf("\r") >= 0) {
      folderMutationError = "Folder paths containing line breaks are not supported"
      return false
    }

    var selected = []
    var seen = ({})
    var values = selectedDeviceIds || []
    for (var i = 0; i < values.length; i++) {
      var deviceId = String(values[i] || "")
      if (!deviceId || deviceId === localDeviceId || seen[deviceId]) continue
      var device = configuredDevice(deviceId)
      if (!device) {
        folderMutationError = "A selected device is no longer configured"
        return false
      }
      if (device.untrusted === true) {
        folderMutationError = "Encrypted sharing with untrusted devices must "
          + "be configured in the Syncthing Web UI"
        return false
      }
      var pendingOffer = (((pendingFolders[id] || {}).offeredBy || ({}))[deviceId]
        || ({}))
      if (pendingOffer.receiveEncrypted === true
          || pendingOffer.remoteEncrypted === true) {
        folderMutationError = "Encrypted folder offers must be accepted in "
          + "the Syncthing Web UI"
        return false
      }
      seen[deviceId] = true
      selected.push(deviceId)
    }

    if (!beginFolderMutation("add", id)) return false
    _pendingFolderAdd = {
      id: id,
      label: String(label || "").trim(),
      path: requestedPath,
      selectedDeviceIds: selected,
      pendingDeviceId: String(pendingDeviceId || ""),
      configuredPaths: [],
      configuredFolders: []
    }
    _folderPathOutput = ""
    _folderPathErrorOutput = ""
    var command = ["realpath", "--canonicalize-missing", "--", requestedPath]
    for (var j = 0; j < folders.length; j++) {
      var configuredPath = resolveFolderPath(String((folders[j] || {}).path || ""))
      if (configuredPath.indexOf("\n") >= 0
          || configuredPath.indexOf("\r") >= 0) {
        failFolderMutation(null,
          "A configured folder path contains unsupported line breaks")
        return false
      }
      _pendingFolderAdd.configuredPaths.push(configuredPath)
      _pendingFolderAdd.configuredFolders.push({
        id: String((folders[j] || {}).id || ""),
        path: String((folders[j] || {}).path || "")
      })
      command.push(configuredPath)
    }
    folderPathProcess.command = command
    folderPathProcess.running = true
    return true
  }

  function postPendingFolder() {
    var pending = _pendingFolderAdd
    if (!pending) {
      failFolderMutation(null, "The folder operation lost its pending state")
      return
    }
    requestFolderMutation("getDefaultFolder", {}, function(data) {
      var defaults = data || ({})
      var config
      try {
        config = JSON.parse(JSON.stringify(defaults))
      } catch (error) {
        root.failFolderMutation(error, "Could not read Syncthing folder defaults")
        return
      }
      if (!root.localDeviceId) {
        root.failFolderMutation(null, "Syncthing did not report the local device")
        return
      }
      config.id = pending.id
      config.label = pending.label || root.displayFileName(pending.path) || pending.id
      config.path = pending.path
      config.paused = false
      config.devices = [{
        deviceID: root.localDeviceId,
        introducedBy: "",
        encryptionPassword: ""
      }]
      for (var i = 0; i < pending.selectedDeviceIds.length; i++) {
        config.devices.push({
          deviceID: pending.selectedDeviceIds[i],
          introducedBy: "",
          encryptionPassword: ""
        })
      }
      root.requestFolderMutation("getFolder", {
        path: { id: pending.id },
        acceptStatuses: [404]
      }, function(existing, xhr) {
        if (xhr.status !== 404) {
          root.failFolderMutation(null,
            "Folder ID was configured while the add form was open; refresh "
            + "and choose a different ID")
          return
        }
        root.requestFolderMutation("getFolders", {}, function(currentFolders) {
          var freshFolders = currentFolders instanceof Array ? currentFolders : []
          if (freshFolders.length !== pending.configuredFolders.length) {
            root.failFolderMutation(null,
              "Syncthing folders changed while the add form was open; refresh "
              + "and review them")
            return
          }
          for (var folderIndex = 0;
              folderIndex < pending.configuredFolders.length; folderIndex++) {
            var expected = pending.configuredFolders[folderIndex]
            var matched = false
            for (var freshIndex = 0;
                freshIndex < freshFolders.length; freshIndex++) {
              var fresh = freshFolders[freshIndex] || ({})
              if (String(fresh.id || "") === expected.id
                  && String(fresh.path || "") === expected.path) matched = true
            }
            if (!matched) {
              root.failFolderMutation(null,
                "Syncthing folders changed while the add form was open; "
                + "refresh and review them")
              return
            }
          }
          root.requestFolderMutation("getDevices", {}, function(currentDevices) {
            var freshDevices = currentDevices instanceof Array ? currentDevices : []
            for (var deviceIndex = 0;
                deviceIndex < pending.selectedDeviceIds.length; deviceIndex++) {
              var selectedId = pending.selectedDeviceIds[deviceIndex]
              var freshDevice = null
              for (var candidateIndex = 0;
                  candidateIndex < freshDevices.length; candidateIndex++) {
                if (String((freshDevices[candidateIndex] || {}).deviceID || "")
                    === selectedId) freshDevice = freshDevices[candidateIndex]
              }
              if (!freshDevice) {
                root.failFolderMutation(null,
                  "A selected device is no longer configured")
                return
              }
              if (freshDevice.untrusted === true) {
                root.failFolderMutation(null,
                  "Encrypted sharing with untrusted devices must be configured "
                  + "in the Syncthing Web UI")
                return
              }
            }
            root.requestFolderMutation("getPendingFolders", {}, function(currentPending) {
              var freshPending = currentPending || ({})
              root.pendingFolders = freshPending
              var offeredBy = ((freshPending[pending.id] || {}).offeredBy || ({}))
              var offeringDevices = Object.keys(offeredBy)
              for (var offerIndex = 0;
                  offerIndex < offeringDevices.length; offerIndex++) {
                var offer = offeredBy[offeringDevices[offerIndex]] || ({})
                if (offer.receiveEncrypted === true
                    || offer.remoteEncrypted === true) {
                  root.failFolderMutation(null,
                    "Encrypted folder offers must be accepted in the "
                    + "Syncthing Web UI")
                  return
                }
              }
              if (pending.pendingDeviceId
                  && !offeredBy[pending.pendingDeviceId]) {
                root.failFolderMutation(null,
                  "The selected remote folder offer is no longer available")
                return
              }
              root.requestFolderMutation("addFolder", {
                method: "POST",
                json: config
              }, function() {
                var count = pending.selectedDeviceIds.length
                if (count > 0) {
                  root.finishFolderMutation(
                    "Remote devices may have to accept the folder.")
                } else {
                  root.finishFolderMutation(
                    "Added " + config.label
                    + " locally. It is linked but not shared with another device.")
                }
              }, "Could not add the folder")
            }, "Could not verify remote folder offers")
          }, "Could not verify selected devices")
        }, "Could not verify current Syncthing folders")
      }, "Could not verify the folder ID before adding it")
    }, "Could not read Syncthing folder defaults")
  }

  function fetch(name, options, onSuccess, onError, showProgress) {
    var generation = _generation
    var visible = showProgress !== false
    if (visible) {
      _pendingRequests++
      refreshing = true
    }
    var xhr = requestApi(name, options, function(data) {
      if (generation !== root._generation) return
      if (onSuccess) onSuccess(data)
      root.finishRequest(generation, visible)
    }, function(error) {
      if (generation !== root._generation) return
      if (onError) onError(error)
      else root.fail(error)
      root.finishRequest(generation, visible)
    })
    var next = _requests.slice()
    next.push(xhr)
    _requests = next
  }

  function requestApi(name, options, onSuccess, onError) {
    if (!_useTls) {
      return Api.request(baseUrl, _apiKey, name, options, onSuccess, onError)
    }

    var process = apiRequestComponent.createObject(root)
    process.startRequest(
      apiHelperPath, baseUrl, _apiKey, name, options, onSuccess, onError)
    return process
  }

  function finishRequest(generation, visible) {
    if (generation !== _generation) return
    if (visible) {
      _pendingRequests = Math.max(0, _pendingRequests - 1)
      refreshing = _pendingRequests > 0
    }
    if (!refreshing && phase === "loading") phase = "ready"
    if (!refreshing && _finishRecoveryAfterRefresh && phase === "ready") {
      stopRecovery()
    }
  }

  function fail(error) {
    if (error && error.status === 403) _apiKey = ""
    stopRecovery()
    phase = "error"
    lastError = error ? error.message : "Connection failed"
  }

  function abortRequests() {
    for (var i = 0; i < _requests.length; i++) {
      try {
        _requests[i].abort()
      } catch (error) {
      }
    }
    _requests = []
    _pendingRequests = 0
    _connectionRefreshing = false
    refreshing = false
  }

  function discoverApiKey() {
    if (apiKeyProcess.running || !executablePath || _apiKeyFailureLatched) {
      return
    }
    apiKeyRetryTimer.stop()
    if (!_recoveryActive) {
      _recoveryActive = true
      _apiKeyAttempts = 0
      _recoveryDotCount = 0
      _recoveryTicks = 0
      _finishRecoveryAfterRefresh = false
    }
    _apiKeyAttempts++
    _generation++
    abortRequests()
    phase = "discovering"
    lastError = ""
    _keyOutput = ""
    apiKeyProcess.command = [
      executablePath,
      "cli",
      "config",
      "gui",
      "dump-json"
    ]
    apiKeyProcess.running = true
  }

  function stopRecovery() {
    _recoveryActive = false
    _apiKeyAttempts = 0
    _recoveryDotCount = 0
    _recoveryTicks = 0
    _finishRecoveryAfterRefresh = false
    apiKeyRetryTimer.stop()
  }

  function failApiKeyRecovery() {
    stopRecovery()
    _apiKeyFailureLatched = true
    phase = "error"
    lastError = "Could not discover the local API key"
  }

  function updateInstallationStatus() {
    if (packageStatusProcess.running) return
    packageRefreshing = true
    packageError = ""
    _packageOutput = ""
    _packageErrorOutput = ""
    packageStatusProcess.running = true
  }

  function applyInstallationStatus(text) {
    var data
    try {
      data = JSON.parse(String(text || ""))
    } catch (error) {
      packageError = "Could not read Syncthing installation status"
      return false
    }

    var state = String(data.state || "")
    if (["existing", "incomplete", "missing"].indexOf(state) < 0) {
      packageError = "Syncthing installation status is invalid"
      return false
    }

    installationState = state
    installationLabel = String(data.label || "Unavailable")
    executablePath = String(data.executable || "")
    serviceAvailable = data.serviceAvailable === true
    serviceRunning = data.serviceRunning === true
    operationRunning = data.operationRunning === true

    if (_desiredServiceState !== -1) {
      var expectedRunning = _desiredServiceState === 1
      if (serviceRunning === expectedRunning) {
        _desiredServiceState = -1
      } else if (!controlProcess.running) {
        _desiredServiceState = -1
        controlError = expectedRunning
          ? "Syncthing did not start" : "Syncthing did not stop"
      }
    }

    if (packageActionRunning && operationRunning) _operationSeen = true
    if (packageActionRunning && _operationSeen && !operationRunning) {
      packageActionRunning = false
      packageStatus = "Installation terminal closed"
      _operationSeen = false
      operationPollTimer.stop()
      packageMessageTimer.restart()
    }

    var canUseRuntime = state === "existing" && executablePath !== ""
    if (!canUseRuntime) stopApi(state)
    else if (serviceAvailable && !serviceActive) stopApi("stopped")
    else if (!_apiKey && !apiKeyProcess.running) refreshApi()
    return true
  }

  function installSyncthing() {
    if (!canInstall) return

    packageActionRunning = true
    packageError = ""
    packageStatus = "Complete installation in the Omarchy terminal"
    operationPollTimer.ticks = 0
    _operationSeen = false
    operationPollTimer.start()
    var command = ["bash", helperPath, "install"]
    Quickshell.execDetached(command)
  }

  function toggleService() {
    if (!canControlService || controlProcess.running || folderMutationBusy) return
    var start = !serviceActive
    _desiredServiceState = start ? 1 : 0
    controlError = ""
    _apiKeyFailureLatched = false
    _controlErrorOutput = ""
    controlProcess.command = [
      "systemctl",
      "--user",
      start ? "start" : "stop",
      "syncthing.service"
    ]
    if (!start) stopApi("stopped")
    else phase = "discovering"
    controlProcess.running = true
  }

  function refreshConnections() {
    if (!_apiKey || !canUseRuntime || refreshing || _connectionRefreshing
        || (serviceAvailable && !serviceActive)) return
    _connectionRefreshing = true
    fetch("getConnections", {}, function(data) {
      root.connections = data || ({})
      root._connectionRefreshing = false
    }, function(error) {
      root._connectionRefreshing = false
      root.fail(error)
    }, false)
  }

  function rebuildSyncingFiles() {
    var wasSyncing = syncingFiles.length > 0
    var result = []
    var seen = ({})
    var actions = ({})

    function append(names, action, actionMap) {
      for (var i = 0; i < names.length; i++) {
        var name = String(names[i] || "")
        var nextAction = actionMap
          ? String(actionMap[name] || action) : action
        if (name && !seen[name]) {
          seen[name] = true
          result.push(name)
        }
        if (name && root.syncActionPriority(nextAction)
            > root.syncActionPriority(actions[name])) actions[name] = nextAction
      }
    }

    append(_localSyncFiles, "syncing")
    var keys = Object.keys(_remoteSyncFiles)
    for (var i = 0; i < keys.length; i++) {
      append(_remoteSyncFiles[keys[i]], "upload")
    }
    append(_changeSyncFiles, "syncing", _changeSyncActions)
    syncingFiles = result
    syncActions = actions
    if (_syncFileIndex >= result.length) _syncFileIndex = 0
    if (wasSyncing && result.length === 0) refreshFolderStatuses(false)
  }

  function syncActionPriority(action) {
    if (action === "removing") return 3
    if (action === "upload") return 2
    if (action === "syncing") return 1
    return 0
  }

  function noteSyncChange(folder, path, action) {
    var token = syncToken(folder, path)
    if (!String(path || "")) return

    var next = _changeSyncFiles.slice()
    var nextActions = ({})
    var actionKeys = Object.keys(_changeSyncActions)
    for (var i = 0; i < actionKeys.length; i++) {
      nextActions[actionKeys[i]] = _changeSyncActions[actionKeys[i]]
    }
    var existing = next.indexOf(token)
    if (existing >= 0) next.splice(existing, 1)
    next.push(token)
    nextActions[token] = action || "syncing"
    while (next.length > 12) {
      var removed = next.shift()
      delete nextActions[removed]
    }
    _changeSyncFiles = next
    _changeSyncActions = nextActions
    syncChangeHoldTimer.restart()
  }

  function forgetSyncChange(folder, path) {
    var token = syncToken(folder, path)
    var next = _changeSyncFiles.slice()
    var existing = next.indexOf(token)
    if (existing >= 0) next.splice(existing, 1)

    var nextActions = ({})
    var actionKeys = Object.keys(_changeSyncActions)
    for (var i = 0; i < actionKeys.length; i++) {
      if (actionKeys[i] !== token) {
        nextActions[actionKeys[i]] = _changeSyncActions[actionKeys[i]]
      }
    }
    _changeSyncFiles = next
    _changeSyncActions = nextActions
    rebuildSyncingFiles()
  }

  function processIndexedChanges(folder, changes) {
    for (var i = 0; i < changes.length; i++) {
      noteSyncChange(folder, changes[i].path,
        changes[i].deleted ? "removing" : "syncing")
    }
  }

  function inspectIndexedFile(folder, path, onFinished) {
    fetch("getFileInfo", {
      query: { folder: folder, file: path }
    }, function(data) {
      var local = (data || {}).local || ({})
      var type = String(local.type || "")
      if (type === "FILE_INFO_TYPE_DIRECTORY" && local.deleted !== true) {
        onFinished({ directoryPath: path })
        return
      }
      if (type !== "FILE_INFO_TYPE_FILE") {
        onFinished(null)
        return
      }
      onFinished({
        path: String(local.name || path),
        deleted: local.deleted === true
      })
    }, function() {
      onFinished(null)
    }, false)
  }

  function scanIndexedDirectory(folder, path) {
    fetch("scanFolder", {
      method: "POST",
      query: { folder: folder, sub: path }
    }, function() {}, function() {}, false)
  }

  function processLocalIndexUpdate(event) {
    var data = (event || {}).data || ({})
    var folder = String(data.folder || "")
    var filenames = data.filenames instanceof Array ? data.filenames : []
    var names = []
    for (var i = Math.max(0, filenames.length - 12);
        i < filenames.length; i++) {
      var name = String(filenames[i] || "")
      if (name) names.push(name)
    }
    if (!folder || names.length === 0) return

    var remaining = names.length
    var changes = []
    var directories = []
    function finish(change) {
      if (change && change.directoryPath) {
        directories.push(change.directoryPath)
      } else if (change) {
        changes.push(change)
      }
      remaining--
      if (remaining > 0) return
      if (changes.length === 0) {
        for (var j = 0; j < directories.length; j++) {
          root.scanIndexedDirectory(folder, directories[j])
        }
      }
      root.processIndexedChanges(folder, changes)
    }
    for (var m = 0; m < names.length; m++) {
      inspectIndexedFile(folder, names[m], finish)
    }
  }

  function processSyncEvents(events) {
    for (var i = 0; i < events.length; i++) {
      var type = String((events[i] || {}).type || "")
      if (type === "LocalIndexUpdated") {
        processLocalIndexUpdate(events[i])
      } else {
        processSyncEvent(events[i])
      }
    }
  }

  function processSyncEvent(event) {
    var type = String((event || {}).type || "")
    var data = (event || {}).data || ({})

    if (type === "DownloadProgress") {
      var local = []
      var folders = Object.keys(data)
      for (var i = 0; i < folders.length; i++) {
        var localNames = Object.keys(data[folders[i]] || ({}))
        for (var localIndex = 0; localIndex < localNames.length; localIndex++) {
          local.push(syncToken(folders[i], localNames[localIndex]))
        }
      }
      _localSyncFiles = local
    } else if (type === "RemoteDownloadProgress") {
      var next = ({})
      var keys = Object.keys(_remoteSyncFiles)
      for (var j = 0; j < keys.length; j++) next[keys[j]] = _remoteSyncFiles[keys[j]]
      var key = String(data.device || "") + "|" + String(data.folder || "")
      var names = Object.keys(data.state || ({}))
      var remoteTokens = []
      for (var nameIndex = 0; nameIndex < names.length; nameIndex++) {
        remoteTokens.push(syncToken(data.folder, names[nameIndex]))
      }
      if (remoteTokens.length > 0) next[key] = remoteTokens
      else delete next[key]
      _remoteSyncFiles = next
    } else if (type === "DeviceDisconnected") {
      var device = String(data.id || data.device || "")
      var remaining = ({})
      var remoteKeys = Object.keys(_remoteSyncFiles)
      for (var k = 0; k < remoteKeys.length; k++) {
        if (remoteKeys[k].indexOf(device + "|") !== 0) {
          remaining[remoteKeys[k]] = _remoteSyncFiles[remoteKeys[k]]
        }
      }
      _remoteSyncFiles = remaining
    } else if (type === "PendingFoldersChanged") {
      fetch("getPendingFolders", {}, function(pending) {
        root.pendingFolders = pending || ({})
      }, function() {}, false)
    }
    rebuildSyncingFiles()
  }

  function pollSyncEvents() {
    if (_syncEventPolling || !_apiKey || !canUseRuntime
        || (serviceAvailable && !serviceActive)) return

    var generation = _syncEventGeneration
    var query = {
      events: "DownloadProgress,RemoteDownloadProgress,DeviceDisconnected,"
        + "PendingFoldersChanged,LocalIndexUpdated",
      timeout: _syncEventsInitialized ? 5 : 0
    }
    if (_syncEventsInitialized) query.since = _syncEventSince
    else query.limit = 1

    _syncEventPolling = true
    _syncEventRequest = requestApi("getEvents", {
      query: query
    }, function(data) {
      if (generation !== root._syncEventGeneration) return
      root._syncEventPolling = false
      root._syncEventRequest = null
      var events = data instanceof Array ? data : []
      if (!root._syncEventsInitialized) {
        root._syncEventsInitialized = true
      } else {
        root.processSyncEvents(events)
      }
      if (events.length > 0) {
        root._syncEventSince = Number(events[events.length - 1].id || 0)
      }
    }, function() {
      if (generation !== root._syncEventGeneration) return
      root._syncEventPolling = false
      root._syncEventRequest = null
    })
  }

  function stopSyncEvents() {
    _syncEventGeneration++
    if (_syncEventRequest) {
      try {
        _syncEventRequest.abort()
      } catch (error) {
      }
    }
    _syncEventRequest = null
    _syncEventPolling = false
    _syncEventsInitialized = false
    _syncEventSince = 0
    _localSyncFiles = []
    _remoteSyncFiles = ({})
    _changeSyncFiles = []
    _changeSyncActions = ({})
    syncChangeHoldTimer.stop()
    syncingFiles = []
    syncActions = ({})
    _syncDotCount = 0
    _syncFileIndex = 0
  }

  property Timer refreshTimer: Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refreshApi()
  }

  property Timer installationTimer: Timer {
    interval: 15000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.updateInstallationStatus()
  }

  property Timer operationPollTimer: Timer {
    property int ticks: 0
    interval: 1500
    repeat: true
    onTriggered: {
      ticks++
      root.updateInstallationStatus()
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

  property Timer folderMutationNoticeTimer: Timer {
    interval: 10400
    repeat: false
    onTriggered: root.folderMutationNotice = ""
  }

  property Timer recentlyLinkedTimer: Timer {
    interval: 10000
    repeat: false
    onTriggered: root.recentlyLinkedFolderId = ""
  }

  property Timer recoveryDotTimer: Timer {
    interval: 500
    repeat: true
    running: root._recoveryActive
    onTriggered: root._recoveryDotCount = (root._recoveryDotCount + 1) % 3
  }

  property Timer apiKeyRetryTimer: Timer {
    interval: 1000
    repeat: false
    onTriggered: root.discoverApiKey()
  }

  property Timer recoveryRefreshTimer: Timer {
    interval: 1000
    repeat: true
    running: root._recoveryActive && root._apiKey !== ""
    onTriggered: {
      if (!root.refreshing) {
        root._recoveryTicks++
        if (root._recoveryTicks >= 10) {
          root._finishRecoveryAfterRefresh = true
          root.refreshApi()
        } else {
          root.refreshConnections()
        }
      }
    }
  }

  property Timer connectionRefreshTimer: Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: if (!root._recoveryActive) root.refreshConnections()
  }

  property Timer syncEventTimer: Timer {
    interval: 500
    repeat: true
    running: true
    onTriggered: root.pollSyncEvents()
  }

  property Timer syncAnimationTimer: Timer {
    interval: 400
    repeat: true
    running: root.syncingFiles.length > 0
    onTriggered: root._syncDotCount = (root._syncDotCount + 1) % 3
  }

  property Timer syncFileTimer: Timer {
    interval: 2500
    repeat: true
    running: root.syncingFiles.length > 1
    onTriggered: root._syncFileIndex = (root._syncFileIndex + 1)
      % root.syncingFiles.length
  }

  property Timer syncChangeHoldTimer: Timer {
    interval: 7000
    repeat: false
    onTriggered: {
      root._changeSyncFiles = []
      root._changeSyncActions = ({})
      root.rebuildSyncingFiles()
    }
  }

  property Process folderPathProcess: Process {
    id: folderPathProcess
    command: []
    stdout: StdioCollector {
      id: folderPathStdout
      waitForEnd: true
      onStreamFinished: root._folderPathOutput = text
    }
    stderr: StdioCollector {
      id: folderPathStderr
      waitForEnd: true
      onStreamFinished: root._folderPathErrorOutput = text
    }
    onExited: function(exitCode) {
      if (!root.folderMutationBusy || root.folderMutationAction !== "add"
          || !root._pendingFolderAdd) return
      if (exitCode !== 0) {
        root.failFolderMutation({
          body: String(root._folderPathErrorOutput
            || folderPathStderr.text || "").trim()
        }, "Could not resolve the folder path")
        return
      }
      var output = String(root._folderPathOutput || folderPathStdout.text || "")
      var lines = output.split("\n")
      if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
      var expected = root._pendingFolderAdd.configuredPaths.length + 1
      if (lines.length !== expected || !lines[0]) {
        root.failFolderMutation(null, "Could not resolve the folder path")
        return
      }
      for (var i = 1; i < lines.length; i++) {
        if (lines[i] === lines[0]) {
          var existing = root.folders[i - 1] || ({})
          root.failFolderMutation(null,
            "Folder path is already configured as "
            + String(existing.label || existing.id || "another folder"))
          return
        }
        var existingPrefix = lines[i] === "/" ? "/" : lines[i] + "/"
        var newPrefix = lines[0] === "/" ? "/" : lines[0] + "/"
        if (lines[0].indexOf(existingPrefix) === 0
            || lines[i].indexOf(newPrefix) === 0) {
          var nested = root.folders[i - 1] || ({})
          root.failFolderMutation(null,
            "Nested Syncthing folders are unsupported; choose a path outside "
            + String(nested.label || nested.id || "the configured folder"))
          return
        }
      }
      root._pendingFolderAdd.path = lines[0]
      folderDirectoryProcess.command = ["test", "-d", lines[0]]
      folderDirectoryProcess.running = true
    }
  }

  property Process folderDirectoryProcess: Process {
    id: folderDirectoryProcess
    command: []
    onExited: function(exitCode) {
      if (!root.folderMutationBusy || root.folderMutationAction !== "add"
          || !root._pendingFolderAdd) return
      if (exitCode !== 0) {
        root.failFolderMutation(null,
          "Choose an existing local directory")
        return
      }
      root.postPendingFolder()
    }
  }

  property Component apiRequestComponent: Component {
    Process {
      id: requestProcess

      property var settings
      property var successCallback
      property var failureCallback
      property string output
      property bool canceled

      stdout: StdioCollector {
        id: requestStdout
        waitForEnd: true
        onStreamFinished: requestProcess.output = text
      }

      function startRequest(helper, baseUrl, apiKey, name, options,
          onSuccess, onError) {
        settings = options
        successCallback = onSuccess
        failureCallback = onError
        environment = ({ SYNCTHING_API_KEY: apiKey })
        var args = [
          "bash",
          helper,
          settings.method || "GET",
          Api.requestUrl(baseUrl, name, settings)
        ]
        if (settings.json !== undefined) {
          args.push(JSON.stringify(settings.json))
        }
        command = args
        running = true
      }

      function abort() {
        canceled = true
        if (running) running = false
        else destroy()
      }

      onExited: function(exitCode) {
        if (canceled) {
          destroy()
          return
        }
        var marker = output.lastIndexOf("\n")
        var body = output.slice(0, marker)
        var status = Number(output.slice(marker + 1)) || 0
        var accepted = settings.acceptStatuses || []
        if (exitCode === 0 && ((status >= 200 && status < 300)
            || accepted.indexOf(status) >= 0)) {
          successCallback(Api.parseBody(body), ({ status: status }))
        } else {
          failureCallback({
            status: status,
            message: status ? "HTTP " + status : "Connection failed",
            body: Api.parseBody(body)
          })
        }
        destroy()
      }
    }
  }

  property Process apiKeyProcess: Process {
    id: apiKeyProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._keyOutput = text
    }
    onExited: function(exitCode) {
      var config = null
      try {
        config = JSON.parse(root._keyOutput)
      } catch (error) {
      }
      var key = config ? String(config.apiKey || "").trim() : ""
      if (exitCode === 0 && key) {
        root._useTls = config.useTLS === true
        root._apiKey = key
        root.apiKeyRetryTimer.stop()
        root._recoveryTicks = 0
        root._finishRecoveryAfterRefresh = false
        root._apiKeyFailureLatched = false
        root.refreshApi()
      } else if (root.canUseRuntime
          && (!root.serviceAvailable || root.serviceActive)) {
        if (root._apiKeyAttempts < 15) root.apiKeyRetryTimer.restart()
        else root.failApiKeyRecovery()
      }
    }
  }

  property Process packageStatusProcess: Process {
    id: packageStatusProcess
    command: ["bash", root.helperPath, "status"]
    stdout: StdioCollector {
      id: packageStdout
      waitForEnd: true
      onStreamFinished: root._packageOutput = text
    }
    stderr: StdioCollector {
      id: packageStderr
      waitForEnd: true
      onStreamFinished: root._packageErrorOutput = text
    }
    onExited: function(exitCode) {
      root.packageRefreshing = false
      var output = String(root._packageOutput || packageStdout.text || "")
      var error = String(
        root._packageErrorOutput || packageStderr.text || "").trim()
      if (exitCode === 0) root.applyInstallationStatus(output)
      else root.packageError = error || "Could not check Syncthing installation"
    }
  }

  property Process controlProcess: Process {
    id: controlProcess
    command: []
    stderr: StdioCollector {
      id: controlStderr
      waitForEnd: true
      onStreamFinished: root._controlErrorOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.controlError = String(
        root._controlErrorOutput || controlStderr.text
          || "Could not change Syncthing service state").trim()
        root._desiredServiceState = -1
      }
      root.updateInstallationStatus()
      if (exitCode === 0 && root.serviceActive) root._apiKey = ""
    }
  }

  Component.onDestruction: {
    cancelFolderMutation("")
    if (_folderPreparationRequest) {
      try {
        _folderPreparationRequest.abort()
      } catch (error) {
      }
    }
    _folderPreparationRequest = null
    _generation++
    abortRequests()
    stopRecovery()
    stopSyncEvents()
    _apiKey = ""
  }
}
