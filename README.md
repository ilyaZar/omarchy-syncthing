# Syncthing for Omarchy

See what Syncthing is doing without leaving the Omarchy bar. The plugin shows
live sync health, manages configured folders, opens their directories, starts or
stops the user service, and launches Syncthing's local Web UI.

![Syncthing status and installation controls](preview.png)

## Install

```bash
omarchy plugin add \
  https://github.com/ilyaZar/omarchy-syncthing.git \
  --enable \
  --yes
```

## Install Syncthing

Open the widget, select **More**, then select **Install Syncthing**. The plugin
installs the official Arch package through `omarchy pkg add syncthing`, then
enables and immediately starts `syncthing.service`.

After installation, the plugin treats Syncthing like any other existing
installation. It does not retain package ownership or offer package removal.

After the first start, select **Open Web UI** to add devices and configure
advanced folder options; the latter can also be configured by the plugin UI
though the easiest first setup is likely achieved by using the official web UI.
Syncthing ships with the Web UI built in.

## Use

### General

- Use the switch beside **Syncthing** to start or stop the user service. This
  does not change whether the service starts automatically at login.
- Select any folder row to open that folder in the file manager.
- Under **More**, use the folder selector below **FOLDERS** to choose the target
  for **LINK** or **UNLINK**.
- Select **+** to add an existing local directory.
- Select **Refresh** for an immediate health update.
- Select **Open Web UI** to open the local Syncthing interface.

### Keyboard

| Key   | Action                    |
| ----- | ------------------------- |
| `R`   | refresh status            |
| `W`   | open the Web UI           |
| `P`   | start or stop the service |
| `M`   | show or hide More         |
| `Q`   | close the panel           |
| `Esc` | close the panel           |

## Usage and managing folders

In this plugin, **UNLINK** sets Syncthing's reversible `paused` flag to `true`;
**LINK** sets it to `false`. Neither action creates a filesystem link or changes
device sharing. Unlinking preserves the Folder ID, path, settings, device
associations, directory, and data. Linking can resume synchronization
immediately.

Adding a folder requires an existing local directory and a unique Folder ID. It
creates an active (`paused=false`) configuration from Syncthing's current folder
defaults. The plugin asks Syncthing to generate a new ID, but the ID can be
replaced when rejoining an existing remote folder. Folder IDs are case sensitive
and must match exactly on every device that shares the folder.

Relative paths and `~/` paths are resolved under `$HOME` and canonicalized.
Paths already configured by Syncthing, nested inside a configured folder, or
parents of another configured folder are rejected. The selected directory may
already contain data, so review advanced behavior in the Web UI and maintain
appropriate backups before synchronizing it.

When creating a new folder identity, no remote devices are selected by default.
Select named devices explicitly to share the folder with them. Selected devices
receive a folder offer and may still need to accept it before synchronization
begins. The plugin never silently shares a new directory with every configured
device.

Pending unencrypted folder offers appear under **More** and in the add form.
**ACCEPT** only opens the form with the existing Folder ID, label, and named
offering device selected. Choose an existing local path, then select **ADD
FOLDER** to complete acceptance. Folder IDs with encrypted offers and sharing
with untrusted devices must be handled in the Syncthing Web UI.

An unlinked row has a **FORGET** action. After confirmation, this removes only
that folder from Syncthing configuration and the plugin view. It does not delete
the directory or its data files. For the default marker, Syncthing also attempts
to remove its internal `.stfolder` directory and normally recreates it if the
folder is added again. Forgetting discards the local folder settings and device
list; no hidden plugin metadata is retained. To rejoin the same remote folder
later, accept its pending offer or enter its exact Folder ID and select the
intended devices. Reusing an ID restores only the folder identity, not the
previous settings or device selections. Select **NEW ID** only when creating a
different folder identity.

Folder mutations use Syncthing's documented granular REST configuration
endpoints, available since Syncthing 1.12.0. Operations are serialized and the
plugin immediately reloads Syncthing configuration after every result.

**BROWSE** opens a `qml6` folder chooser and uses Omarchy's `hyprctl` and `jq`
tools to float and position it. A path can be entered manually if the chooser is
unavailable.

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

Removing the plugin does not reverse changes made through it. Added folders,
device associations, and linked or unlinked states remain in Syncthing
configuration. The plugin stores no separate folder-restoration metadata.

## Security and license

The plugin talks only to Syncthing's local API at `127.0.0.1:8384`. It reads the
API key into memory and never intentionally writes or logs it. Like other
Omarchy shell plugins, it runs unsandboxed; the API key permits Syncthing
configuration changes.

Plugin code is MIT licensed. Adapted Syncthing status icons are MPL-2.0; their
source and attribution are documented in `assets/README.md`.
