# Development

The root contains only the manifest and runtime entry points:

- `Panel.qml` coordinates the bar widget and imports visual types from `ui/`.
- `Service.qml` coordinates local state and imports controllers from `core/`.
- `models/` contains reusable JavaScript transformations.

Split a file when it owns unrelated behavior, not to meet an arbitrary line
count.

## Checks

Run the complete local suite from the repository root:

```bash
git diff --check
jq empty manifest.json
omarchy plugin validate .
qmllint Panel.qml Service.qml core/*.qml models/*.js ui/*.qml \
  tests/run.qml scripts/folder-picker.qml
for script in scripts/*.sh; do bash -n "$script"; done
shellcheck scripts/*.sh
qml6 --apptype core -f tests/run.qml
```

## Syncthing state contract

Display only state reported by Syncthing:

- Classify an indexed file with `/rest/db/file` and `local.deleted`.
- Treat `RemoteDownloadProgress` as an upload from the local device.
- Rescan an indexed directory so files newly placed inside it are classified.
- Do not infer a rename or move from hashes, timing, or adjacent events.

Tests should cover these user-visible contracts or a concrete model invariant.
Avoid assertions that only mirror implementation details.
