import QtQuick
import ".."
import "../FolderModel.js" as FolderModel
import "../PanelModel.js" as PanelModel

QtObject {
  id: root

  property ActivityTracker tracker: ActivityTracker {}

  function compare(actual, expected, name) {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      throw new Error(name + ": expected " + JSON.stringify(expected)
        + ", got " + JSON.stringify(actual))
    }
  }

  function testActivityStates() {
    tracker.stop()
    tracker.processIndexedChanges("folder", [{
      path: "nested/file.txt", deleted: false
    }])
    compare(tracker.dots, ".  ", "first aligned dot frame")
    tracker._dotIndex = 1
    compare(tracker.dots, ".. ", "second aligned dot frame")
    tracker._dotIndex = 2
    compare(tracker.dots, "...", "third aligned dot frame")
    compare(tracker.action, "syncing", "addition action")
    compare(tracker.detail, "file.txt", "addition detail")

    tracker.processIndexedChanges("folder", [{
      path: "nested/file.txt", deleted: true
    }])
    compare(tracker.action, "removing", "removal action")
    compare(tracker.detail, "Removing file.txt", "removal detail")

    tracker.processIndexedChanges("second-folder", [{
      path: "second.txt", deleted: false
    }])
    tracker.advanceFile()
    compare(tracker.folderId, "second-folder", "file cycle folder")
    compare(tracker.detail, "second.txt", "file cycle detail")

    tracker.stop()
    tracker.processEvent({
      type: "RemoteDownloadProgress",
      data: {
        device: "device",
        folder: "folder",
        state: { "video.mp4": { bytesDone: 1, bytesTotal: 2 } }
      }
    })
    compare(tracker.action, "upload", "upload action")
    compare(tracker.detail, "Upload video.mp4", "upload detail")
  }

  function testNestedDirectoryScan() {
    var scans = []
    tracker.stop()
    tracker.requestApi = function(name, options, onSuccess, onError) {
      if (name === "getFileInfo") {
        onSuccess({
          local: {
            name: options.query.file,
            type: "FILE_INFO_TYPE_DIRECTORY",
            deleted: false
          }
        })
      } else if (name === "scanFolder") {
        scans.push(options.query)
        onSuccess({})
      } else {
        onError({})
      }
      return { abort: function() {} }
    }
    tracker.processLocalIndexUpdate({
      data: { folder: "folder", filenames: ["new-directory"] }
    })
    compare(scans, [{ folder: "folder", sub: "new-directory" }],
      "new directory scan")
  }

  function testModels() {
    var rows = PanelModel.buildFolderRows({
      localDeviceId: "local",
      folders: [{
        id: "folder",
        label: "Configured label",
        path: "/tmp/truthful-folder",
        devices: [{ deviceID: "local" }]
      }],
      folderStatuses: {
        folder: { state: "idle", globalFiles: 3, globalBytes: 12 }
      }
    }, "/home/test")
    compare(rows.length, 1, "folder row count")
    compare(rows[0].label, "truthful-folder", "folder display label")
    compare(PanelModel.folderState(rows[0], ""), "SYNCED", "folder state")
    compare(PanelModel.folderMeta(rows[0]),
      "3 files · local only · Configured label", "folder metadata")

    var config = FolderModel.buildConfig({}, {
      id: "folder",
      label: "Folder",
      path: "/tmp/folder",
      selectedDeviceIds: ["remote"]
    }, "local", function(path) { return path })
    compare(config.devices.map(function(device) { return device.deviceID }),
      ["local", "remote"], "configured devices")
  }

  Component.onCompleted: {
    try {
      testActivityStates()
      testNestedDirectoryScan()
      testModels()
      console.log("all model tests passed")
      Qt.exit(0)
    } catch (error) {
      console.error(error)
      Qt.exit(1)
    }
  }
}
