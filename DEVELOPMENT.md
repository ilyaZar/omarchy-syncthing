# Development practices

## QML and JavaScript

Keep visual components declarative. Put state acquisition and mutations in
focused controller objects, and put reusable data transformations in JavaScript
libraries. A component should expose the smallest property and signal surface
needed by its parent.

Follow Qt's recommended QML member order: id, properties, signals, JavaScript
functions, object properties, child objects, states, and transitions. Move a
multi-line handler into a named function and move substantial logic into a
separate JavaScript resource or controller.

Use these review thresholds:

- Aim for no more than 500 lines per QML or JavaScript file. Crossing 500 lines
  triggers a split review; focused orchestration files should remain below 600.
- Aim for functions no longer than 50 lines. A function over 75 lines must be
  split or justified by a clearer single flow.
- Keep cyclomatic complexity at or below 20 and nesting at four levels or less.
- Run `qmllint` over every QML and JavaScript file before committing, including
  files under `core/`, `models/`, and `ui/`.

The numeric thresholds use ESLint's maintained `max-lines`,
`max-lines-per-function`, `complexity`, and `max-depth` rules as practical
review signals. They are prompts to improve ownership, not targets for dense
formatting.

Sources:

- [Qt QML coding conventions](https://doc.qt.io/qt-6/qml-codingconventions.html)
- [Qt Quick best practices](https://doc.qt.io/qt-6/qtquick-bestpractices.html)
- [JavaScript resources in QML](https://doc.qt.io/qt-6/qtqml-javascript-resources.html)
- [qmllint documentation](https://doc.qt.io/qt-6.10/qtqml-tooling-qmllint.html)
- [ESLint max-lines](https://eslint.org/docs/latest/rules/max-lines)
- [ESLint max-lines-per-function](https://eslint.org/docs/latest/rules/max-lines-per-function)
- [ESLint complexity](https://eslint.org/docs/latest/rules/complexity)
- [ESLint max-depth](https://eslint.org/docs/latest/rules/max-depth)

## Shell

Use shell for short orchestration around existing commands. Prefer another
language once a script grows beyond roughly 100 lines and contains substantial
data processing or control flow.

- Start Bash scripts with `#!/bin/bash` and `set -euo pipefail`.
- Quote expansions, use arrays for commands, and use `[[ ... ]]` for tests.
- Put executable flow in `main` and keep helper functions focused.
- Aim for 80 columns and run both `bash -n` and ShellCheck.

Source:

- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

## Syncthing state

User-visible activity must come from stable Syncthing API state. File deletion
uses the indexed file's `local.deleted` value, and upload uses
`RemoteDownloadProgress`. Do not label a rename or move unless Syncthing exposes
a structured source-to-destination relationship; matching names, hashes, or
event timing is not sufficient.
