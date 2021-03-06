stock void AddMessagesToArray(KeyValues kv)
{
  bool bEnabled;
  bEnabled = view_as<bool>(kv.GetNum("enabled", 1));
  if(bEnabled)
  {
    if(SA_CheckDate(kv))
    {
      char sTempMap[64];
      kv.GetString("maps", sTempMap, sizeof(sTempMap), "all");
      if(StrEqual(sTempMap, "all") || StrEqual(sTempMap, sMapName) || StrContains(sMapName, sTempMap) != -1)
      {
        ArrayList aMessages = new ArrayList(512);
        ArrayList aMessages_Text = new ArrayList(512);

        char sMessageType[3];
        char sMessageTag[64];
        char sMessageFlags[16];
        char sTempLanguageName[12];
        char sTempLanguageMessage[512];
        char sMessageColor[32];
        char sMessagePosX[16];
        char sMessagePosY[16];
        char sMessageFadeIn[32];
        char sMessageFadeOut[16];
        char sMessageHoldTime[16];
        kv.GetString("type", sMessageType, sizeof(sMessageType), "T");
        kv.GetString("tag", sMessageTag, sizeof(sMessageTag), sServerName);
        kv.GetString("flags", sMessageFlags, sizeof(sMessageFlags), "all");
        if(strlen(sMessageFlags) == 0)
        {
          Format(sMessageFlags, sizeof(sMessageFlags), "all");
        }
        for(int i = 0; i < aLanguages.Length; i++)
        {
          aLanguages.GetString(i, sTempLanguageName, sizeof(sTempLanguageName));
          kv.GetString(sTempLanguageName, sTempLanguageMessage, sizeof(sTempLanguageMessage), "NOLANG");
          if(StrEqual(sTempLanguageMessage, "NOLANG"))
          {
            SetFailState("%s '%s' translation missing in message \"%i\"", SA3, sTempLanguageName, aMessagesList.Length+1);
            return;
          }
          aMessages_Text.PushString(sTempLanguageMessage);
        }
        aMessages.PushString(sMessageType);
        aMessages.PushString(sMessageTag);
        aMessages.PushString(sMessageFlags);
        aMessages.Push(aMessages_Text);
        if(StrEqual(sMessageType, "H", false))
        {
          kv.GetString("color", sMessageColor, sizeof(sMessageColor), "255 255 255");
          kv.GetString("posx", sMessagePosX, sizeof(sMessagePosX), "-1");
          kv.GetString("posy", sMessagePosY, sizeof(sMessagePosY), "0.05");
          kv.GetString("fadein", sMessageFadeIn, sizeof(sMessageFadeIn), "0.2");
          kv.GetString("fadeout", sMessageFadeOut, sizeof(sMessageFadeOut), "0.2");
          kv.GetString("holdtime", sMessageHoldTime, sizeof(sMessageHoldTime), "5.0");
          aMessages.PushString(sMessageColor);
          aMessages.PushString(sMessagePosX);
          aMessages.PushString(sMessagePosY);
          aMessages.PushString(sMessageFadeIn);
          aMessages.PushString(sMessageFadeOut);
          aMessages.PushString(sMessageHoldTime);
        }
        aMessagesList.Push(aMessages);
      }
    }
  }
}
stock void CheckMessageVariables(char[] message, int len)
{
  char sBuffer[256];
  ConVar hConVar;
  char sConVar[64];
  char sSearch[64];
  char sReplace[64];
  int iCustomCvarEnd = -1;
  int iCustomCvarStart = StrContains(message, "{");
  int iCustomCvarNextStart;
  if(iCustomCvarStart != -1)
  {
    while(iCustomCvarStart != -1)
    {
        iCustomCvarEnd = StrContains(message[iCustomCvarStart+1], "}");
        if(iCustomCvarEnd != -1)
        {
          strcopy(sConVar, iCustomCvarEnd+1, message[iCustomCvarStart+1]);
          Format(sSearch, sizeof(sSearch), "{%s}", sConVar);
          hConVar = FindConVar(sConVar);
          if(hConVar)
          {
              hConVar.GetString(sReplace, sizeof(sReplace));
              ReplaceString(message, len, sSearch, sReplace, false);
          }
          iCustomCvarNextStart = StrContains(message[iCustomCvarStart+1], "{");
          if(iCustomCvarNextStart != -1)
          {
            iCustomCvarStart += iCustomCvarNextStart+1;
          }
          else break;
        }
        else break;
    }
  }
  if(StrContains(message , "{NEXTMAP}") != -1)
  {
    GetNextMap(sBuffer, sizeof(sBuffer));
    ReplaceString(message, len, "{NEXTMAP}", sBuffer);
  }

  if(StrContains(message, "{CURRENTMAP}") != -1)
  {
    GetCurrentMap(sBuffer, sizeof(sBuffer));
    ReplaceString(message, len, "{CURRENTMAP}", sBuffer);
  }

  if(StrContains(message, "{PLAYERCOUNT}") != -1)
  {
    Format(sBuffer, sizeof(sBuffer), "%i", CountPlayers());
    ReplaceString(message, len, "{PLAYERCOUNT}", sBuffer);
  }

  if(StrContains(message, "{CURRENTTIME}") != -1)
  {
    FormatTime(sBuffer, sizeof(sBuffer), "%H:%M:%S");
    ReplaceString(message, len, "{CURRENTTIME}", sBuffer);
  }

  if(StrContains(message, "{SERVERIP}") != -1)
  {
    GetServerIP(sBuffer, sizeof(sBuffer));
    ReplaceString(message, len, "{SERVERIP}", sBuffer);
  }

  if(StrContains(message, "{SERVERNAME}") != -1)
  {
    GetConVarString(FindConVar("hostname"), sBuffer,sizeof(sBuffer));
    ReplaceString(message, len, "{SERVERNAME}", sBuffer);
  }

  if(StrContains(message , "{TIMELEFT}") != -1)
  {
    int i_Minutes;
    int i_Seconds;
    int i_Time;
    if(GetMapTimeLeft(i_Time) && i_Time > 0)
    {
     i_Minutes = i_Time / 60;
     i_Seconds = i_Time % 60;
    }
    Format(sBuffer, sizeof(sBuffer), "%d:%02d", i_Minutes, i_Seconds);
    ReplaceString(message, len, "{TIMELEFT}", sBuffer);
  }
  if(StrContains(message, "{ADMINSONLINE}") != -1)
  {
    char sAdminList[128];
    LoopClients(x)
    {
      if(IsValidClient(x) && IsPlayerAdmin(x))
      {
       if(sAdminList[0] == 0) Format(sAdminList,sizeof(sAdminList),"'%N'", x);
       else Format(sAdminList,sizeof(sAdminList),"%s,'%N'",sAdminList, x);
      }
    }
    ReplaceString(message, len, "{ADMINSONLINE}", sAdminList);
  }
}
stock void SA_GetClientLanguage(int client, char buffer[3])
{
  char sBuffer[12];
  GetClientCookie(client, g_hSA3CustomLanguage, sBuffer, sizeof(sBuffer));
  if(StrEqual(sBuffer, "geoip", false))
  {
    char sIP[26];
    GetClientIP(client, sIP, sizeof(sIP));
    GeoipCode2(sIP, buffer);
  }
  else
  {
    int iIndex = aLanguages.FindString(sBuffer);
    if(iIndex == -1)
    {
      SetClientCookie(client, g_hSA3CustomLanguage, "geoip");
      char sIP[26];
      GetClientIP(client, sIP, sizeof(sIP));
      GeoipCode2(sIP, buffer);
    }
    else
    {
      Format(buffer, sizeof(buffer), sBuffer);
    }
  }
}
stock void CheckMessageClientVariables(int client, char[] message, int len)
{
  char sBuffer[256];
  if(StrContains(message, "{STEAMID}") != -1)
  {
    GetClientAuthId(client, AuthId_Engine, sBuffer, sizeof(sBuffer));
    ReplaceString(message, len, "{STEAMID}", sBuffer);
  }

  if(StrContains(message , "{PLAYERNAME}") != -1)
  {
    Format(sBuffer, sizeof(sBuffer), "%N", client);
    ReplaceString(message, len, "{PLAYERNAME}", sBuffer);
  }
}
stock int CountPlayers()
{
  int count = 0;
  LoopClients(i)
  {
    count++;
  }
  return count;
}
stock void GetServerIP(char[] buffer, int len)
{
  int ips[4];
  int ip = GetConVarInt(FindConVar("hostip"));
  int port = GetConVarInt(FindConVar("hostport"));
  ips[0] = (ip >> 24) & 0x000000FF;
  ips[1] = (ip >> 16) & 0x000000FF;
  ips[2] = (ip >> 8) & 0x000000FF;
  ips[3] = ip & 0x000000FF;
  Format(buffer, len, "%d.%d.%d.%d:%d", ips[0], ips[1], ips[2], ips[3], port);
}
stock void HudMessage(int client, const char[] color, const char[] message, const char[] posx, const char[] posy, const char[] fadein, const char[] fadeout, const char[] holdtime)
{
  int ent = CreateEntityByName("game_text");
  DispatchKeyValue(ent, "channel", "1");
  DispatchKeyValue(ent, "color", color);
  DispatchKeyValue(ent, "color2", "0 0 0");
  DispatchKeyValue(ent, "effect", "0");
  DispatchKeyValue(ent, "fadein", fadein);
  DispatchKeyValue(ent, "fadeout", fadeout);
  DispatchKeyValue(ent, "fxtime", "0.25");
  DispatchKeyValue(ent, "holdtime", holdtime);
  DispatchKeyValue(ent, "message", message);
  DispatchKeyValue(ent, "spawnflags", "0");
  DispatchKeyValue(ent, "x", posx);
  DispatchKeyValue(ent, "y", posy);
  DispatchSpawn(ent);
  SetVariantString("!activator");
  AcceptEntityInput(ent,"display",client);
}
stock bool SA_DateCompare(int currentdate[3], int availabletill[3])
{
  if(availabletill[0] > currentdate[0])
  {
    return true;
  }
  else if(availabletill[0] == currentdate[0])
  {
    if(availabletill[1] > currentdate[1])
    {
      return true;
    }
    else if(availabletill[1] == currentdate[1])
    {
      if(availabletill[2] >= currentdate[2])
      {
        return true;
      }
    }
  }
  return false;
}
stock bool SA_CheckDate(KeyValues kv)
{
  char sEnabledTill[32];
  char sEnabledTillEx[3][12];
  kv.GetString("enabledtill", sEnabledTill, sizeof(sEnabledTill), "");
  if(strlen(sEnabledTill) > 0)
  {
    int iEnabledTill = ExplodeString(sEnabledTill, ".", sEnabledTillEx, sizeof(sEnabledTillEx), sizeof(sEnabledTillEx[]));
    if(iEnabledTill != 3)
    {
      SetFailState("%s (1) Wrong date format in message %i. Use: DD.MM.YYYY",SA3, aMessagesList.Length+1);
    }
  }
  else
  {
    return true;
  }
  int iExpDate[3];
  int iCurrentDate[3];
  char sCurrentYear[12];
  char sCurrentYearEx[3][12];
  FormatTime(sCurrentYear, sizeof(sCurrentYear), "%Y.%m.%d");
  ExplodeString(sCurrentYear, ".", sCurrentYearEx, sizeof(sCurrentYearEx), sizeof(sCurrentYearEx[]));

  iCurrentDate[0] = StringToInt(sCurrentYearEx[0]);
  iCurrentDate[1] = StringToInt(sCurrentYearEx[1]);
  iCurrentDate[2] = StringToInt(sCurrentYearEx[2]);

  iExpDate[0] = StringToInt(sEnabledTillEx[2]);
  iExpDate[1] = StringToInt(sEnabledTillEx[1]);
  iExpDate[2] = StringToInt(sEnabledTillEx[0]);

  if(((strlen(sEnabledTillEx[0]) != 2) || (strlen(sEnabledTillEx[1]) != 2) || (strlen(sEnabledTillEx[2]) != 4) || iExpDate[2] > 31 || iExpDate[1] > 12))
  {
    SetFailState("%s (2) Wrong date format in message %i. Use: DD.MM.YYYY",SA3, aMessagesList.Length+1);
  }
  else
  {
    if(SA_DateCompare(iCurrentDate, iExpDate))
    {
      return true;
    }
    else
    {
      if(bExpiredMessagesDebug == true)
      {
        LogError("%s Message #%i is not available anymore. The message expired on %s",SA3, aMessagesList.Length+1, sEnabledTill);
      }
    }
  }
  return false;
}
