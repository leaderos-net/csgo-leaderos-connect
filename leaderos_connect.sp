// ============================================================
//  LeaderOS Connect
//  Syncs your CS:GO server with the LeaderOS panel.
//  Fetches the command queue from the API every X seconds
//  and executes the returned commands.
//
//  SETUP:
//    1. Edit addons/sourcemod/configs/leaderos_connect.cfg
//    2. Upload compiled leaderos_connect.smx to addons/sourcemod/plugins/
// ============================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <ripext>

#define PLUGIN_VERSION  "1.0.0"
#define PENDING_FILE    "data/leaderos_pending.json"

public Plugin myinfo =
{
    name        = "LeaderOS Connect",
    author      = "LeaderOS",
    description = "Syncs your server with the LeaderOS panel",
    version     = PLUGIN_VERSION,
    url         = "https://leaderos.net"
};

// ── Config globals ────────────────────────────────────────────

KeyValues g_Config;
char      g_sConfigFile[PLATFORM_MAX_PATH];

char g_sWebsiteUrl[256];
char g_sApiKey[256];
char g_sServerToken[256];
bool g_bDebugMode         = false;
bool g_bCheckPlayerOnline = true;
int  g_iFreqSeconds       = 300;

Handle g_hPollTimer = null;

// ── Helpers ───────────────────────────────────────────────────

void Log(const char[] fmt, any ...)
{
    char buf[512];
    VFormat(buf, sizeof(buf), fmt, 2);
    PrintToServer("[LeaderOS] %s", buf);
}

void LogDebug(const char[] fmt, any ...)
{
    if (!g_bDebugMode) return;
    char buf[512];
    VFormat(buf, sizeof(buf), fmt, 2);
    PrintToServer("[LeaderOS][DEBUG] %s", buf);
}

void LogError2(const char[] fmt, any ...)
{
    char buf[512];
    VFormat(buf, sizeof(buf), fmt, 2);
    PrintToServer("[LeaderOS][ERROR] %s", buf);
}

// ── Config (Tebex-style) ──────────────────────────────────────

void LeaderosConfigInit()
{
    BuildPath(Path_SM, g_sConfigFile, sizeof(g_sConfigFile), "configs/leaderos_connect.cfg");

    if (FileExists(g_sConfigFile))
    {
        Log("Loading config...");
        delete g_Config;
        g_Config = new KeyValues("LeaderosConnect");
        g_Config.SetEscapeSequences(true);
        FileToKeyValues(g_Config, g_sConfigFile);
    }
    else
    {
        Log("No config file found, creating with defaults...");
        g_Config = new KeyValues("LeaderosConnect");
        g_Config.SetEscapeSequences(true);
        g_Config.SetString("WebsiteUrl",       "https://yourwebsite.com");
        g_Config.SetString("ApiKey",            "YOUR_API_KEY_HERE");
        g_Config.SetString("ServerToken",       "YOUR_SERVER_TOKEN_HERE");
        g_Config.SetString("FreqSeconds",       "300");
        g_Config.SetString("CheckPlayerOnline", "1");
        g_Config.SetString("DebugMode",         "0");
        KeyValuesToFile(g_Config, g_sConfigFile);
    }

    g_Config.GetString("WebsiteUrl",       g_sWebsiteUrl,  sizeof(g_sWebsiteUrl),  "");
    g_Config.GetString("ApiKey",           g_sApiKey,       sizeof(g_sApiKey),       "");
    g_Config.GetString("ServerToken",      g_sServerToken,  sizeof(g_sServerToken),  "");
    g_bDebugMode         = view_as<bool>(g_Config.GetNum("DebugMode",         0));
    g_bCheckPlayerOnline = view_as<bool>(g_Config.GetNum("CheckPlayerOnline", 1));
    g_iFreqSeconds       = g_Config.GetNum("FreqSeconds", 300);
}

void LeaderosSetConfig(const char[] key, const char[] value)
{
    g_Config.SetString(key, value);
    KeyValuesToFile(g_Config, g_sConfigFile);
    Log("Config updated: %s = %s", key, value);
}

// ── Config Validation ─────────────────────────────────────────

bool ValidateConfig()
{
    bool valid = true;

    if (strlen(g_sWebsiteUrl) == 0)
    {
        LogError2("WebsiteUrl is empty.");
        valid = false;
    }
    else
    {
        if (strncmp(g_sWebsiteUrl, "https://", 8) != 0)
        {
            LogError2("WebsiteUrl must start with 'https://' (got: '%s').", g_sWebsiteUrl);
            valid = false;
        }

        int len = strlen(g_sWebsiteUrl);
        if (g_sWebsiteUrl[len - 1] == '/')
        {
            g_sWebsiteUrl[len - 1] = '\0';
            Log("Trailing slash removed from WebsiteUrl.");
        }
    }

    if (strlen(g_sApiKey) == 0 || strcmp(g_sApiKey, "YOUR_API_KEY_HERE") == 0)
    {
        LogError2("ApiKey is not set.");
        valid = false;
    }

    if (strlen(g_sServerToken) == 0 || strcmp(g_sServerToken, "YOUR_SERVER_TOKEN_HERE") == 0)
    {
        LogError2("ServerToken is not set.");
        valid = false;
    }

    return valid;
}

// ── Pending Commands (offline players) ───────────────────────

JSONObject LoadPending()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), PENDING_FILE);

    if (!FileExists(path))
        return new JSONObject();

    JSONObject obj = JSONObject.FromFile(path);
    return (obj != null) ? obj : new JSONObject();
}

void SavePending(JSONObject data)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), PENDING_FILE);
    data.ToFile(path);
}

void PendingAdd(const char[] steamid, const char[] cmd)
{
    JSONObject data = LoadPending();
    JSONArray  cmds;

    if (data.HasKey(steamid))
        cmds = view_as<JSONArray>(data.Get(steamid));
    else
    {
        cmds = new JSONArray();
        data.Set(steamid, cmds);
    }

    cmds.PushString(cmd);
    SavePending(data);

    delete cmds;
    delete data;
}

JSONArray PendingFlush(const char[] steamid)
{
    JSONObject data = LoadPending();

    if (!data.HasKey(steamid))
    {
        delete data;
        return null;
    }

    JSONArray cmds = view_as<JSONArray>(data.Get(steamid));
    data.Remove(steamid);
    SavePending(data);

    delete data;
    return cmds;
}

// ── Player Lookup ─────────────────────────────────────────────

int FindPlayerBySteamId64(const char[] steamid64)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;

        char sid[32];
        GetClientAuthId(i, AuthId_SteamID64, sid, sizeof(sid));

        if (strcmp(sid, steamid64) == 0)
            return i;
    }
    return -1;
}

// ── Command Executor ─────────────────────────────────────────

void ExecuteCommands(JSONArray cmds, const char[] steamid)
{
    int client = FindPlayerBySteamId64(steamid);

    if (g_bCheckPlayerOnline && client == -1)
    {
        int count = cmds.Length;
        Log("Player %s is offline. Queuing %d command(s).", steamid, count);

        for (int i = 0; i < count; i++)
        {
            char cmd[512];
            cmds.GetString(i, cmd, sizeof(cmd));
            PendingAdd(steamid, cmd);
        }
        return;
    }

    char sid32[32];
    char name[MAX_NAME_LENGTH];

    if (client > 0)
    {
        GetClientAuthId(client, AuthId_Steam2, sid32, sizeof(sid32));
        GetClientName(client, name, sizeof(name));
    }

    for (int i = 0; i < cmds.Length; i++)
    {
        char cmd[512];
        cmds.GetString(i, cmd, sizeof(cmd));

        if (client > 0)
        {
            ReplaceString(cmd, sizeof(cmd), "{steamid}",   steamid);
            ReplaceString(cmd, sizeof(cmd), "{steamid32}", sid32);
            ReplaceString(cmd, sizeof(cmd), "{name}",      name);
        }

        Log("Executing: %s", cmd);
        ServerCommand("%s", cmd);
    }
}

// ── HTTP ──────────────────────────────────────────────────────

void BuildUrl(char[] buf, int maxlen, const char[] endpoint)
{
    FormatEx(buf, maxlen, "%s/api/%s", g_sWebsiteUrl, endpoint);
}

// ── Validate Callback ─────────────────────────────────────────

void OnValidateResponse(HTTPResponse response, DataPack pack)
{
    pack.Reset();
    delete pack;

    int status = view_as<int>(response.Status);
    LogDebug("Validate response status: %d", status);

    if (response.Status != HTTPStatus_OK)
    {
        LogError2("Validate HTTP error: %d", status);

        if (g_bDebugMode && response.Data != null)
        {
            char body[4096];
            JSONObject errData = view_as<JSONObject>(response.Data);
            if (errData != null)
            {
                errData.ToString(body, sizeof(body));
                LogDebug("Validate error body: %s", body);
            }
        }

        return;
    }

    if (response.Data == null)
    {
        LogError2("Validate response data is null.");
        return;
    }

    JSONObject data = view_as<JSONObject>(response.Data);

    if (g_bDebugMode && data != null)
    {
        char body[4096];
        data.ToString(body, sizeof(body));
        LogDebug("Validate response body: %s", body);
    }

    if (data == null || !data.HasKey("commands"))
    {
        LogError2("Invalid validate response (missing 'commands' key).");
        return;
    }

    JSONArray items    = view_as<JSONArray>(data.Get("commands"));
    JSONArray cmds     = new JSONArray();
    char      username[64];
    username[0] = '\0';

    for (int i = 0; i < items.Length; i++)
    {
        JSONObject item = view_as<JSONObject>(items.Get(i));

        char cmd[512];
        item.GetString("command", cmd, sizeof(cmd));

        if (strlen(cmd) > 0)
            cmds.PushString(cmd);

        if (strlen(username) == 0 && item.HasKey("username"))
            item.GetString("username", username, sizeof(username));

        delete item;
    }

    LogDebug("Validate: %d command(s) for steamid '%s'.", cmds.Length, username);

    if (cmds.Length > 0 && strlen(username) > 0)
        ExecuteCommands(cmds, username);

    delete cmds;
    delete items;
}

// ── Validate Request ──────────────────────────────────────────

void ValidateAndExecute(JSONArray ids)
{
    char url[512];
    BuildUrl(url, sizeof(url), "command-logs/validate");

    LogDebug("POST (form) %s", url);

    if (g_bDebugMode)
    {
        // Log form params as JSON for easy reading
        JSONObject debugBody = new JSONObject();
        JSONArray  debugIds  = new JSONArray();
        debugBody.SetString("token", g_sServerToken);
        for (int i = 0; i < ids.Length; i++)
        {
            char id[32];
            ids.GetString(i, id, sizeof(id));
            debugIds.PushString(id);
        }
        debugBody.Set("commands[]", debugIds);
        char debugStr[4096];
        debugBody.ToString(debugStr, sizeof(debugStr));
        LogDebug("Validate form params: %s", debugStr);
        delete debugIds;
        delete debugBody;
    }

    HTTPRequest req = new HTTPRequest(url);
    req.SetHeader("X-Api-Key", g_sApiKey);

    // AppendFormParam sets Content-Type: application/x-www-form-urlencoded automatically
    req.AppendFormParam("token", g_sServerToken);

    for (int i = 0; i < ids.Length; i++)
    {
        char id[32];
        ids.GetString(i, id, sizeof(id));
        req.AppendFormParam("commands[]", id);
    }

    DataPack pack = new DataPack();
    req.PostForm(OnValidateResponse, pack);
}

// ── Queue Callback ────────────────────────────────────────────

void OnQueueResponse(HTTPResponse response, any unused)
{
    int status = view_as<int>(response.Status);
    LogDebug("Queue response status: %d", status);

    if (response.Status != HTTPStatus_OK)
    {
        LogError2("Queue HTTP error: %d", status);

        if (g_bDebugMode && response.Data != null)
        {
            char body[4096];
            JSONObject errData = view_as<JSONObject>(response.Data);
            if (errData != null)
            {
                errData.ToString(body, sizeof(body));
                LogDebug("Queue error body: %s", body);
            }
        }

        return;
    }

    if (response.Data == null)
    {
        LogError2("Queue response data is null.");
        return;
    }

    if (g_bDebugMode)
    {
        char debugBody[8192];
        JSONObject debugObj = view_as<JSONObject>(response.Data);
        if (debugObj != null)
            debugObj.ToString(debugBody, sizeof(debugBody));
        else
        {
            JSONArray debugArr = view_as<JSONArray>(response.Data);
            if (debugArr != null)
                debugArr.ToString(debugBody, sizeof(debugBody));
        }
        LogDebug("Queue response body: %s", debugBody);
    }

    JSONArray arr = null;
    JSONArray ids = new JSONArray();

    JSONObject obj = view_as<JSONObject>(response.Data);

    if (obj != null && obj.HasKey("array"))
        arr = view_as<JSONArray>(obj.Get("array"));
    else if (obj != null && obj.HasKey("data"))
        arr = view_as<JSONArray>(obj.Get("data"));
    else
        arr = view_as<JSONArray>(response.Data);

    if (arr == null)
    {
        LogError2("Invalid queue response (could not find array).");

        if (g_bDebugMode && obj != null)
        {
            char body[4096];
            obj.ToString(body, sizeof(body));
            LogDebug("Queue response body: %s", body);
        }

        delete ids;
        return;
    }

    for (int i = 0; i < arr.Length; i++)
    {
        JSONObject entry = view_as<JSONObject>(arr.Get(i));
        if (entry != null && entry.HasKey("id"))
        {
            char id[32];
            entry.GetString("id", id, sizeof(id));
            ids.PushString(id);
        }
        delete entry;
    }

    LogDebug("Queue: %d item(s) found.", ids.Length);

    if (ids.Length > 0)
        ValidateAndExecute(ids);

    delete ids;
}

// ── Poll Queue ────────────────────────────────────────────────

void PollQueue(Handle timer = null, any data = 0)
{
    LogDebug("Polling queue...");

    char endpoint[256];
    FormatEx(endpoint, sizeof(endpoint), "command-logs/%s/queue", g_sServerToken);

    char url[512];
    BuildUrl(url, sizeof(url), endpoint);

    LogDebug("GET %s", url);

    HTTPRequest req = new HTTPRequest(url);
    req.SetHeader("X-Api-Key", g_sApiKey);
    req.Get(OnQueueResponse);
}

// ── Pending Flush on Connect ──────────────────────────────────

public Action OnClientPostAdminCheck_Delayed(Handle timer, DataPack pack)
{
    pack.Reset();
    int userid = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userid);
    if (client == 0) return Plugin_Stop;

    char steamid[32];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));

    JSONArray cmds = PendingFlush(steamid);
    if (cmds == null) return Plugin_Stop;

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    Log("Executing %d pending command(s) for '%s'.", cmds.Length, name);
    ExecuteCommands(cmds, steamid);

    delete cmds;
    return Plugin_Stop;
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client)) return;

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    CreateTimer(3.0, OnClientPostAdminCheck_Delayed, pack);
}

// ── Plugin Lifecycle ──────────────────────────────────────────

public void OnPluginStart()
{
    LeaderosConfigInit();

    if (!ValidateConfig())
    {
        SetFailState("[LeaderOS] Addon could not start due to configuration errors.");
        return;
    }

    g_hPollTimer = CreateTimer(float(g_iFreqSeconds), PollQueue, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    Log("Started. Queue will be checked every %d second(s).", g_iFreqSeconds);

    RegServerCmd("leaderos_reload", Cmd_Reload,  "Reload config and restart the timer.");
    RegServerCmd("leaderos_poll",   Cmd_Poll,    "Trigger an immediate queue poll.");
    RegServerCmd("leaderos_debug",  Cmd_Debug,   "Toggle debug mode.");
    RegServerCmd("leaderos_status", Cmd_Status,  "Print current plugin status.");
}

public void OnMapStart()
{
    if (g_hPollTimer == null || g_hPollTimer == INVALID_HANDLE)
        g_hPollTimer = CreateTimer(float(g_iFreqSeconds), PollQueue, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// ── Console Commands ──────────────────────────────────────────

public Action Cmd_Reload(int args)
{
    delete g_hPollTimer;
    LeaderosConfigInit();

    if (!ValidateConfig())
    {
        LogError2("Config reload failed.");
        return Plugin_Handled;
    }

    g_hPollTimer = CreateTimer(float(g_iFreqSeconds), PollQueue, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    PollQueue();
    Log("Reloaded.");
    return Plugin_Handled;
}

public Action Cmd_Poll(int args)
{
    PollQueue();
    return Plugin_Handled;
}

public Action Cmd_Debug(int args)
{
    g_bDebugMode = !g_bDebugMode;
    LeaderosSetConfig("DebugMode", g_bDebugMode ? "1" : "0");
    Log("Debug mode: %s", g_bDebugMode ? "true" : "false");
    return Plugin_Handled;
}

public Action Cmd_Status(int args)
{
    Log("=== LeaderOS Connect Status ===");
    Log("URL:           %s", g_sWebsiteUrl);
    Log("Token:         %s", g_sServerToken);
    Log("Frequency:     %d second(s)", g_iFreqSeconds);
    Log("Check Online:  %s", g_bCheckPlayerOnline ? "true" : "false");
    Log("Debug:         %s", g_bDebugMode ? "true" : "false");
    Log("Timer active:  %s", (g_hPollTimer != null && g_hPollTimer != INVALID_HANDLE) ? "true" : "false");
    return Plugin_Handled;
}