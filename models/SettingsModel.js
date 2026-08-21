.pragma library

var DefaultIconStyle = "branded"
var DefaultWebUiTheme = "omarchy"

function stripComment(line) {
  var quote = ""
  for (var i = 0; i < line.length; i++) {
    var character = line.charAt(i)
    if ((character === "\"" || character === "'") && !quote) {
      quote = character
    } else if (character === quote) {
      quote = ""
    } else if (character === "#" && !quote) {
      return line.slice(0, i)
    }
  }
  return line
}

function parseValue(raw) {
  var value = String(raw || "").trim()
  var match = value.match(/^(["'])([^"']*)\1$/)
  return match ? match[2] : null
}

function parse(raw) {
  var values = ({})
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var line = stripComment(lines[i]).trim()
    if (!line) continue
    var assignment = line.match(/^([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(.+)$/)
    if (!assignment) {
      return { error: "Invalid settings syntax on line " + (i + 1) }
    }
    var key = assignment[1]
    if (key !== "icon_style" && key !== "web_ui_theme") {
      return { error: "Unknown setting " + key + " on line " + (i + 1) }
    }
    if (values[key] !== undefined) {
      return { error: "Duplicate setting " + key + " on line " + (i + 1) }
    }
    var value = parseValue(assignment[2])
    if (value === null) {
      return { error: key + " must use a quoted value" }
    }
    values[key] = value
  }

  if (values.icon_style === undefined) {
    return { error: "Missing setting icon_style" }
  }
  if (["branded", "themed"].indexOf(values.icon_style) < 0) {
    return { error: "icon_style must be branded or themed" }
  }
  if (values.web_ui_theme === undefined) {
    return { error: "Missing setting web_ui_theme" }
  }
  if (["default", "omarchy"].indexOf(values.web_ui_theme) < 0) {
    return { error: "web_ui_theme must be default or omarchy" }
  }

  return {
    error: "",
    iconStyle: values.icon_style,
    webUiTheme: values.web_ui_theme
  }
}

function defaults(legacyThemedIcon) {
  return {
    iconStyle: legacyThemedIcon === true ? "themed" : DefaultIconStyle,
    webUiTheme: DefaultWebUiTheme
  }
}
