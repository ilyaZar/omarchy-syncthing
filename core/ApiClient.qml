import QtQuick
import Quickshell.Io
import "../models/SyncthingApi.js" as Api

QtObject {
  id: root

  property string baseUrl: "http://127.0.0.1:8384"
  property string helperPath: ""
  property string apiKey: ""
  property bool useTls: false

  function request(name, options, onSuccess, onError) {
    if (!useTls) {
      return Api.request(baseUrl, apiKey, name, options, onSuccess, onError)
    }
    var process = requestComponent.createObject(root)
    process.start(helperPath, baseUrl, apiKey, name, options,
      onSuccess, onError)
    return process
  }

  property Component requestComponent: Component {
    Process {
      id: requestProcess

      property var settings
      property var successCallback
      property var failureCallback
      property string output
      property bool canceled

      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: requestProcess.output = text
      }

      function start(helper, base, key, name, options, onSuccess, onError) {
        settings = options
        successCallback = onSuccess
        failureCallback = onError
        environment = ({ SYNCTHING_API_KEY: key })
        var args = [
          "bash",
          helper,
          settings.method || "GET",
          Api.requestUrl(base, name, settings)
        ]
        if (settings.json !== undefined) args.push(JSON.stringify(settings.json))
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
}
