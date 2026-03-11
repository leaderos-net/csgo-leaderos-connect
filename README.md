# LeaderosConnect Plugin for CS:GO

This plugin allows you to connect your CS:GO server to LeaderOS, enabling you to send commands to the server through the LeaderOS platform.

## Requirements

This plugin requires [SourceMod](https://www.sourcemod.net/downloads.php) and the [ripext](https://github.com/ErikMinekus/sm-ripext/releases) extension to be installed.

## Installation

### 1. Download the plugin

Download the latest release as a ZIP file from the link below and extract it:

[https://www.leaderos.net/plugin/csgo](https://www.leaderos.net/plugin/csgo)

### 2. Upload the plugin

Copy the files from the extracted ZIP into your server's SourceMod directory:

```
csgo/addons/sourcemod/plugins/leaderos_connect.smx
csgo/addons/sourcemod/configs/leaderos_connect.cfg
```

Also upload the ripext extension files:

```
csgo/addons/sourcemod/extensions/ripext.ext.so      (Linux)
csgo/addons/sourcemod/extensions/ripext.ext.dll     (Windows)
csgo/addons/sourcemod/extensions/ripext.autoload
```

### 3. Configure the plugin

Open the config file and fill in your credentials:

```
csgo/addons/sourcemod/configs/leaderos_connect.cfg
```

```
"LeaderosConnect"
{
    "WebsiteUrl"            "https://yourwebsite.com"
    "ApiKey"                "YOUR_API_KEY_HERE"
    "ServerToken"           "YOUR_SERVER_TOKEN_HERE"
    "FreqSeconds"           "300"
    "CheckPlayerOnline"     "1"
    "DebugMode"             "0"
}
```

If the config file does not exist, the plugin will auto-generate it with default values on first run.

### 4. Required server configuration

Add this to your `csgo/cfg/server.cfg`:

```
sv_hibernate_when_empty 0
```

Without this, the server enters sleep mode when no players are connected and stops processing game ticks. This prevents commands from executing on an empty server.

### 5. Restart your server

Restart your server. The plugin is now active. Run `leaderos_status` in the server console to confirm everything is working.

## Configuration

| Option | Description |
|---|---|
| `WebsiteUrl` | The URL of your LeaderOS website (e.g., `https://yourwebsite.com`). Must start with `https://`. |
| `ApiKey` | Your LeaderOS API key. Find it on `Dashboard > Settings > API`. |
| `ServerToken` | Your server token. Find it on `Dashboard > Store > Servers > Your Server > Server Token`. |
| `FreqSeconds` | How often the plugin polls the command queue, in seconds. Default: `300` (5 minutes). |
| `CheckPlayerOnline` | Set to `1` to queue commands for offline players and deliver them on next login. Set to `0` to execute commands regardless of whether the target player is online. |
| `DebugMode` | Set to `1` to enable verbose debug logging, or `0` to disable it. |

## Console Commands

All commands can be run freely from the server console or via RCON.

| Command | Description |
|---|---|
| `leaderos_status` | Displays the current plugin state, URL, token, poll frequency, and timer status. |
| `leaderos_poll` | Triggers an immediate queue poll without waiting for the next interval. |
| `leaderos_reload` | Reloads the config file and restarts the poll timer. |
| `leaderos_debug` | Toggles debug mode on or off at runtime and saves the change to the config file. |

## Building from Source

### Windows

1. Clone this repository:
   ```bat
   git clone https://github.com/leaderos-net/csgo-leaderos-connect.git
   cd csgo-leaderos-connect
   ```

2. Run the build script:
   ```bat
   build.bat
   ```

3. The compiled `leaderos_connect.smx` will be output to the `upload/` folder.

### Linux

1. Clone this repository:
   ```bash
   git clone https://github.com/leaderos-net/csgo-leaderos-connect.git
   cd csgo-leaderos-connect
   ```

2. Run the build script:
   ```bash
   chmod +x build.sh
   sh build.sh
   ```

3. The compiled `leaderos_connect.smx` will be output to the `upload/` folder.
