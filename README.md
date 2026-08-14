# Syncthing for Omarchy

See what Syncthing is doing without leaving the Omarchy bar. The plugin shows
live sync health, opens configured folders, starts or stops the user service,
and launches Syncthing's local Web UI.

![Syncthing status and installation controls](preview.png)

## Install

```bash
omarchy plugin add \
  https://github.com/ilyaZar/omarchy-syncthing.git \
  --enable \
  --yes
```

The widget starts on the right side of the bar and can be moved with Omarchy's
bar customization controls.

## Install Syncthing

Open the widget, select **More**, then select **Install Syncthing**. The plugin
installs the official Arch package through `omarchy pkg add syncthing`, so it
follows normal system updates. A terminal shows every step and waits for Enter
when it finishes.

After installation, the plugin treats Syncthing like any other existing
installation. It does not retain package ownership or offer package removal.
The square **?** beside **Installation** summarizes this policy.

After the first start, select **Open Web UI** to add devices and folders.

## Use

- Use the switch beside **Syncthing** to start or stop syncing.
- Select any folder row to open that folder in the file manager.
- Select **Refresh** for an immediate health update.
- Select **Open Web UI** to open the local Syncthing interface.

The status beneath **Syncthing** changes as folders synchronize, scan, pause,
or need attention. Long folder paths are shortened from the left while keeping
the final directory visible.

| Key | Action                |
| --- | --------------------- |
| `R` | refresh status        |
| `W` | open the Web UI       |
| `P` | start or stop syncing |
| `M` | show or hide More     |

## Remove Syncthing

Remove Syncthing manually with the method that installed it. For the official
package installed by this plugin:

```bash
systemctl --user disable --now syncthing.service
omarchy pkg drop syncthing
```

These commands do not remove Syncthing configuration, shared folders, or their
files.

Remove the plugin separately:

```bash
omarchy plugin remove io.github.ilyazar.syncthing --yes
```

Removing the plugin never removes Syncthing. The plugin monitors any Syncthing
installation found on the command path, shows its resolved executable, and can
control an existing `syncthing.service`. Installation is offered only when no
Syncthing executable or conflicting installation files are found.

## Security and license

The plugin talks only to Syncthing's local API at `127.0.0.1:8384`. It reads
the API key into memory and never writes or logs it.

Plugin code is MIT licensed. Adapted Syncthing status icons are MPL-2.0; their
source and attribution are documented in `assets/README.md`.
