
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <votetime>

#define PluginVersion "v0.2" 
 
public Plugin myinfo =
{
	name = "squadcontrol",
	author = "Mikleo",
	description = "Control Squads in Empiresmod",
	version = PluginVersion,
	url = ""
}

// appears to crash clients. dont yet know why
ConVar sc_fixcommvotes,sc_prelimcommander;

new String:squadnames[][] = {"No Squad","Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliet","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","X-Ray","Yankee","Zulu"};
new String:teamcolors[][] = {"\x01","\x01","\x07FF2323","\x079764FF"};
new String:highlightColors[][] = {"\x07CCCC00","\x07CCCC00","\x07d60000","\x077733ff"};
new String:highlightColors2[][] = {"\x07CCCC00","\x07CCCC00","\x07a30000","\x07661aff"};
int playerVotes[MAXPLAYERS+1] = {0, ...};
int commVotes[MAXPLAYERS+1] = {0, ...};
int commChatTime[MAXPLAYERS+1] = {0, ...};
int lastCommVoiceTime[MAXPLAYERS+1] = {0, ...};
// bit flags
int playerFlags [MAXPLAYERS+1] = {0, ...};
int comms[4];
new String:teamnames[][] = {"Unassigned","Spectator","NF","BE"};
bool gameEnded;

#define FLAG_SQUAD_VOICE		(1<<0)
#define FLAG_COMM_VOICE		(1<<1)


#define HINT_SQUAD_CHAT			(1<<10)
#define HINT_SQUAD_VOICE		(1<<11)
#define HINT_COMM_CHAT		(1<<12)
#define HINT_PRELIM_COMM		(1<<13)

public void OnPluginStart()
{

	LoadTranslations("common.phrases");
	RegConsoleCmd("sm_squadinfo", Command_Info);
	RegConsoleCmd("sm_squadskills", Command_Skills);
	RegConsoleCmd("sm_sl", Command_SL_Vote);
	RegConsoleCmd("sm_rsl", Command_Request_SL);
	RegConsoleCmd("say_squad", Command_Say_Squad);
	RegConsoleCmd("say_comm", Command_Say_Comm);
	RegConsoleCmd("say_comm_private", Command_Say_Comm_Private);
	RegConsoleCmd("sm_assign", Command_Assign_Squad);
	RegConsoleCmd("sm_channel", Command_Change_Channel);
	RegConsoleCmd("sm_bindsquadvoice", Command_Bind_Squad_Voice);
	RegConsoleCmd("sm_bindcommvoice", Command_Bind_Comm_Voice);
	RegConsoleCmd("sm_hashmenu", Command_Hash_Menu);
	RegConsoleCmd("sm_commander", Command_Check_Commander);
	RegConsoleCmd("+voicerecord_squad", Command_Squad_Voice_Start);
	RegConsoleCmd("-voicerecord_squad", Command_Squad_Voice_End);
	RegConsoleCmd("+voicerecord_comm", Command_Comm_Voice_Start);
	RegConsoleCmd("-voicerecord_comm", Command_Comm_Voice_End);
	RegConsoleCmd("voice_squad_only", Comand_Squad_Voice);
	RegConsoleCmd("sm_bindchatkeys",Command_Bind_Chat_Keys );
	AddCommandListener(Command_Invite_Player, "emp_squad_invite");
	AddCommandListener(Command_Opt_Out, "emp_commander_vote_drop_out");
	AddCommandListener(Command_Say_Team, "say_team");
	AddCommandListener(Command_Squad_Join, "emp_squad_join");
	AddCommandListener(Command_Squad_Leave, "emp_squad_leave");
	AddCommandListener(Command_Squad_Make_Lead, "emp_make_lead");
	AddCommandListener(Command_Join_Team, "jointeam");
	HookEvent("commander_vote", Event_Comm_Vote, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("vehicle_enter", Event_VehicleEnter, EventHookMode_Post);
	HookEvent("commander_elected_player", Event_Elected_Player, EventHookMode_Pre);
	HookEvent("game_end",Event_Game_End);
	sc_fixcommvotes = CreateConVar("sc_fixcommvotes", "0", "Fixes comm vote numbers");
	sc_prelimcommander = CreateConVar("sc_prelimcommander", "0", "Preliminary commander election");
}
// must be used for natives
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("SC_GetCommVotes", Native_GetCommVotes);	
	CreateNative("SC_GetComm", Native_GetComm);	
	return APLRes_Success;
}



public OnConfigsExecuted()
{
	
}
public OnClientConnected(int client)
{
	// reset all player flags
	playerFlags[client] = 0;
}
public OnClientPutInServer(int client)
{
	ClientCommand(client,"bind home \"sm_hashmenu\"");
}
public OnClientDisconnect(int client)
{
	if(IsClientInGame(client))
	{
		onExitSquad(client);
	
		int team = GetClientTeam(client);
		if(!VT_HasGameStarted() && team >=2)
		{
			commVotes[client] = 0;
			RefreshVotes(team);
		}
		if(comms[team] == client)
		{
			comms[team] = 0;
		}
	}
	
	// reset all player flags
	playerFlags[client] = 0;
}

public Action  Command_Bind_Squad_Voice(int client,int args)
{
	if(client == 0)
		client = 1;
	new String:arg[129];
	GetCmdArg(1, arg, sizeof(arg));
	ClientCommand(client,"bind \"%s\" \"+voicerecord_squad\"",arg,arg);
	PrintToChat(client,"Squad voice now bound to %s",arg);
	return Plugin_Handled;
}
public Action  Command_Bind_Comm_Voice(int client,int args)
{
	if(client == 0)
		client = 1;
	new String:arg[129];
	GetCmdArg(1, arg, sizeof(arg));
	ClientCommand(client,"bind \"%s\" \"+voicerecord_comm\"",arg,arg);
	PrintToChat(client,"Comm voice now bound to %s",arg);
	return Plugin_Handled;
}
public Action Command_Bind_Chat_Keys(int client,int args)
{
	ClientCommand(client,"bind \".\" \"say_team\";bind \",\" \"say_team\";bind \"semicolon\" \"say_team\"");
	
	PrintToChat(client,"';', '.' and ',' are now bound to say_team. Double tap them for easy access to squad/comm chat");
	return Plugin_Handled;
}


public Action Command_Squad_Voice_Start(int client,int args)
{
	FakeClientCommand(client,"voice_squad_only 1");
	
}
public Action Command_Squad_Voice_End(int client,int args)
{
	FakeClientCommand(client,"voice_squad_only 0");
}


public Action Comand_Squad_Voice(int client,int args)
{
	if(client == 0)
		client = 1;
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	new String:arg[129];
	GetCmdArg(1, arg, sizeof(arg));
	
	
	int team = GetClientTeam(client);
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	
	playerFlags[client] |= HINT_SQUAD_VOICE;
	
	if(StrEqual("1", arg, false))
	{
		ClientCommand(client,"+voicerecord");
		playerFlags[client] |= FLAG_SQUAD_VOICE;
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i) )
			{
				if(GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
				{
					EmitSoundToClient(i, "squadcontrol/squadvoice_start.wav");
					if(!(playerFlags[i] & HINT_SQUAD_VOICE))
					{
						new String:clientName[128];
						GetClientName(client,clientName,sizeof(clientName));
						PrintToChat(i,"\x04[SC]: \x07ff6600%s \x01is using squad voice, use \x04!bindsquadvoice [key] \x01to reply",clientName);
						playerFlags[i] |= HINT_SQUAD_VOICE;
					}
				}
				else
				{
					SetListenOverride(i, client, Listen_No);
				}
				
			
			}
			
		}
	}
	else
	{
		ClientCommand(client,"-voicerecord");
		playerFlags[client] &= ~FLAG_SQUAD_VOICE;
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i))
			{
				if(GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
				{
					EmitSoundToClient(i, "squadcontrol/squadvoice_end.wav");
				}
				SetListenOverride(i, client, Listen_Default);
			}
			
		}
	}
	return Plugin_Handled;
}
public Action Command_Comm_Voice_Start(int client,int args)
{
	SetCommVoice(client,true);
	return Plugin_Handled;
}
public Action Command_Comm_Voice_End(int client,int args)
{
	SetCommVoice(client,false);
	return Plugin_Handled;
}
void SetCommVoice(int client,bool enabled)
{
	if(client == 0)
		client = 1;
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return;
	}
	
	new String:arg[129];
	GetCmdArg(1, arg, sizeof(arg));
	
	int team = GetClientTeam(client);
	
	int thetime = GetTime();

	
	if(enabled)
	{
		ClientCommand(client,"+voicerecord");
		playerFlags[client] |= FLAG_COMM_VOICE;
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i) )
			{
				if(GetClientTeam(i) == team && (comms[team] == i || playerFlags[client] & FLAG_COMM_VOICE ||  thetime - lastCommVoiceTime[i] < 30))
				{
					EmitSoundToClient(i, "squadcontrol/commvoice_start.wav");
					
					// start listening to players who already began speaking
					if(playerFlags[client] & FLAG_COMM_VOICE)
					{
						SetListenOverride(client,i,Listen_Default);
					}
				}
				else
				{
					SetListenOverride(i, client, Listen_No);
				}
				
				
				
			
			}
		}
	}
	else
	{
		playerFlags[client] &= ~FLAG_COMM_VOICE;
		lastCommVoiceTime[client] = thetime;
		ClientCommand(client,"-voicerecord");
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i))
			{
				if(GetListenOverride(i, client) == Listen_Default)
				{
					// reset the time as the time they last spoke
					EmitSoundToClient(i, "squadcontrol/commvoice_end.wav");
				}
				SetListenOverride(i, client, Listen_Default);
			}
			
		}
	}
	
	
}



// need to do it after the event.. because we dont know if it will be successful 
void SquadChange(int client)
{
	
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return;
	}
	int team = GetClientTeam(client);
	
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	// if we have left a squad block the players speaking in that squad
	for(new i=1; i< MaxClients; i++)
	{ 
		if(IsClientInGame(i) && GetClientTeam(i) == team && playerFlags[i] & FLAG_SQUAD_VOICE) 
		{
			if(GetEntProp(i, Prop_Send, "m_iSquad") == squad)
			{
				SetListenOverride(i, client, Listen_Default);
			}
			else
			{
				SetListenOverride(i, client, Listen_No);
			}
		}
		
	}
}

public Action Command_Join_Team(int client, const String:command[], args)
{
	char arg[10];
	GetCmdArg(1, arg, sizeof(arg));
	int team = StringToInt(arg);
	int oldTeam = GetClientTeam(client);

	if(oldTeam != team && team >= 2)
	{
		onExitSquad(client);
	}
	
	return Plugin_Continue;
	
}



public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int cuid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(cuid);
	// this can happen, idk why, i think rejoining players on something. 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int team = GetEventInt(event, "team");
	int oldTeam = GetEventInt(event, "oldteam");
	
	// refresh the votes. the player might have been comm or he might have voted for the comm. 
	if(!VT_HasGameStarted())
	{
		if(oldTeam >= 2)
		{
			commVotes[oldTeam] = 0;
			RefreshVotes(oldTeam);
		}
		if(team >= 2 && sc_fixcommvotes.IntValue > 0)
		{
			FixCommVotes(team);
		}
	}
	
	if(comms[oldTeam] == client)
	{
		comms[oldTeam] = 0;
	}
	return Plugin_Continue;
}
public Action Event_VehicleEnter(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	// check if player is now the commander
	bool isComm =  GetEntProp(client, Prop_Send, "m_bCommander") == 1;
	if(isComm)
	{
		comms[GetClientTeam(client)] = client;
	}
	playerVotes[client] = 0;
	SquadChange(client);
	return Plugin_Continue;
}

public Action Command_Squad_Join(client, const String:command[], args)
{
	onExitSquad(client); 
	return Plugin_Continue;
}

public Action Command_Squad_Leave(client, const String:command[], args)
{
	onExitSquad(client);
	return Plugin_Continue;
}
onExitSquad(client)
{
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	if(squad == 0)
		return;
	playerVotes[client] = 0;
	CreateTimer(1.0, onSquadChange,client);
	int team = GetClientTeam(client);
	int resourceEntity = GetPlayerResourceEntity();
	bool leader = GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,client) == 1;
	if(leader)
	{
		new Handle:Datapack;
		CreateDataTimer(1.0, onSquadLeaderChange,Datapack);
		WritePackCell(Datapack, squad);
		WritePackCell(Datapack, team);
		WritePackCell(Datapack, client);
	}
		
}

public Action Command_Squad_Make_Lead(client, const String:command[], args)
{
	// make sure the client is a squadleader or the commander
	int team = GetClientTeam(client);
	
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	int resourceEntity = GetPlayerResourceEntity();
	bool leader = GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,client) == 1;
	
	if(client == comms[team] || leader)
	{
		new Handle:Datapack;
		CreateDataTimer(1.0, onSquadLeaderChange,Datapack);
		WritePackCell(Datapack, squad);
		WritePackCell(Datapack, team);
		
		int prevLeader = client;
		if(!leader)
			prevLeader = 0;
		WritePackCell(Datapack, prevLeader);
	}
	
	
	return Plugin_Continue;
}
public Action onSquadChange(Handle timer, any client)
{
	SquadChange(client);
}
public Action onSquadLeaderChange(Handle timer,any dataPack)
{
	// must reset to start of pack
	ResetPack(dataPack);
	int squad = ReadPackCell(dataPack);
	int team = ReadPackCell(dataPack);
	int prevLeader = ReadPackCell(dataPack);

	int resourceEntity = GetPlayerResourceEntity();
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
		{
			if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1 && i != prevLeader)
			{
				PrintToChat(i,"\x04[SC] \x01You are now squad leader");
				EmitSoundToClient(i,"squadcontrol/squadleader_alert.wav");
			}
		}
	} 
}
public Action Command_Say_Comm(int client,int args)
{
	new String:input[129];
	GetCmdArg(1, input, sizeof(input));
	
	if(client == 0)
		client = 1;
	
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	bool isComm = comms[team] ==client;
	
	new String:message[256]; 
	new String:clientName[128];
	
	
	
	GetClientName(client,clientName,sizeof(clientName));
	
	
	// for testing comment this out
	playerFlags[client] |= HINT_COMM_CHAT;
	
	
	
	
	if(isComm)
	{
		Format(message, sizeof(message), "%s(Commander) %s%s: %s",highlightColors2[team],teamcolors[team],clientName,input); 
		// alert all players and send message
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team)
			{
				
				PrintToChat(i,message);
				EmitSoundToClient(i,"squadcontrol/commchat_alert2.wav");
				
			}
		}
	}
	else
	{
	
		int comm = comms[team];
		if(comm == 0 || !IsClientInGame(comm))
		{
			PrintToChat(client,"There is no commander");
			return Plugin_Handled;
		}
		new String:commMessage[256]; 
		
		Format(message, sizeof(message), "%s(To Comm) %s%s: %s",highlightColors[team],teamcolors[team], clientName,input); 
		Format(commMessage, sizeof(commMessage), "%s(To Comm) %s%s: %s",highlightColors2[team],teamcolors[team],clientName,input); 
		
		
		
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team)
			{
				// to everyone not comm and initiator
				if(client != i && comms[team] != i) 
				{
					if(!(playerFlags[i] & HINT_COMM_CHAT))
					{
						PrintToChat(i,"x04[SC] \x07ff6600%s\x01 is using comm chat, put a \x04'.' \x01before your message to get your commanders attention with an alert sound.",clientName);
						playerFlags[i] |= HINT_SQUAD_CHAT;
					}
					PrintToChat(i,message);
				}
				
				
				
			}
		}
		PrintToChat(client,commMessage);
		PrintToChat(comm,commMessage);
		EmitSoundToClient(client,"squadcontrol/commchat_alert2.wav");
		EmitSoundToClient(comm,"squadcontrol/commchat_alert2.wav");

		
	}
	return Plugin_Handled;
}
public Action Command_Say_Comm_Private(int client,int args)
{
	new String:input[129];
	GetCmdArg(1, input, sizeof(input));
	
	if(client == 0)
		client = 1;
	
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	bool isComm = comms[team] == client;
	
	new String:message[256]; 
	new String:clientName[128];
	
	
	GetClientName(client,clientName,sizeof(clientName));
	
	commChatTime[client] = GetTime();
	
	if(isComm)
	{
		Format(message, sizeof(message), "%s(Comm Reply) %s%s: %s",highlightColors2[team],teamcolors[team],clientName,input); 
		int thetime = GetTime();
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team && (thetime - commChatTime[i]) < 30)
			{
				PrintToChat(i,message);
				EmitSoundToClient(client,"squadcontrol/commchat_alert2.wav");
			}
		}
	}
	else
	{
		Format(message, sizeof(message), "%s(To Comm Only) %s%s: %s",highlightColors2[team],teamcolors[team],clientName,input); 
		int comm = 0;
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team && comms[team] == i)
			{
				comm = i;
			}
		}
		if(comm == 0)
		{
			PrintToChat(client,"There is no commander");
		}
		else
		{
			PrintToChat(client,message);
			PrintToChat(comm,message);
			EmitSoundToClient(client,"squadcontrol/commchat_alert2.wav");
			EmitSoundToClient(comm,"squadcontrol/commchat_alert2.wav");
		}
		
		
	}
	return Plugin_Handled;
}
public Action Command_Say_Squad(int client,int args)
{
	new String:input[129];
	GetCmdArg(1, input, sizeof(input));
	
	if(client == 0)
		client = 1;
	
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	
	new String:message[256];
	new String:clientName[128];
	
	
	GetClientName(client,clientName,sizeof(clientName));
	Format(message, sizeof(message), "%s(%s) %s%s: %s",highlightColors[team],squadnames[squad],teamcolors[team],clientName,input); 
	
	// for testing comment this out
	playerFlags[client] |= HINT_SQUAD_CHAT;
	
	for(new i=1; i< MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
		{
			if(!(playerFlags[i] & HINT_SQUAD_CHAT))
			{
				PrintToChat(i,"%s is using squad chat, put a ';' before your message in team chat to reply.",clientName);
				playerFlags[i] |= HINT_SQUAD_CHAT;
			}
			PrintToChat(i,message);
			EmitSoundToClient(i,"squadcontrol/squadchat_alert2.wav");
		}
		
	}
	return Plugin_Handled;
}





public Action Command_Say_Team(client, const String:command[], args)
{
	if(client == 0)
		client = 1;
	new String:input[129];
	
	GetCmdArg(1, input, sizeof(input));
	
	if(input[5] == ';' && input[6] != ')' && (strlen(input) > 7 || (input[6] != 'P' && input[6] != 'D' )))
	{
		RemoveCharacters(input,sizeof(input),5,5);
		FakeClientCommand(client,"say_squad \"%s\"",input);
		return Plugin_Handled;
	}
	else if(input[5] == '.' && input[6] != '.')
	{
		RemoveCharacters(input,sizeof(input),5,5);
		FakeClientCommand(client,"say_comm \"%s\"",input);
		return Plugin_Handled;
	}
	else if(input[5] == ',')
	{
		RemoveCharacters(input,sizeof(input),5,5);
		FakeClientCommand(client,"say_comm_private \"%s\"",input);
		return Plugin_Handled;
	}
	else if (input[5] == '/' || input[5] == '!')
	{
		RemoveCharacters(input,sizeof(input),0,4);
		FakeClientCommand(client,"say_team \"%s\"",input);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
RemoveCharacters(char[] input,int inputsize,int startindex,int endindex)
{
	new pos_cleanedMessage = 0; 
	for (int i = 0; i < inputsize; i++) { 
		if (i<startindex || i>endindex) { 
			input[pos_cleanedMessage++] = input[i]; 
		} 
	}
}

public Action Command_Info(int client, int args)
{
	if(client == 0)
		client = 1;
	int currentTeam = GetClientTeam(client);
	int points[26];
	// need high limit, it prints out a lot of information.
	new String:message[512] = "";
	ArrayList players[26];
	int resourceEntity = GetPlayerResourceEntity();
	for (new i = 1; i <= MaxClients; i++)
	{
		
		if (IsClientInGame(i) && GetClientTeam(i) == currentTeam)
		{
			int squad = GetEntProp(i, Prop_Send, "m_iSquad");
			points[squad] = GetEntProp(i, Prop_Send, "m_iEmpSquadXP") + 1;
			
			if(players[squad] == INVALID_HANDLE)
			{
				players[squad] = new ArrayList();
				players[squad].Push(i);
			}
			else
			{
				if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1)
				{
					players[squad].ShiftUp(0);
					players[squad].Set(0,i);
				}
				else
				{	
					players[squad].Push(i);
				}
			}

		}
	} 
	for (new i = 1; i < 26; i++)
	{
		
		if(points[i] > 0)
		{
			
			new String:squadmessage[16];
			Format(squadmessage, sizeof(squadmessage), "\x04%s [%d] \x01", squadnames[i],points[i] - 1);
			StrCat(message,sizeof(message),squadmessage);
		
		
			for (new j = 0; j < players[i].Length; j++)
			{
				int playerid =  players[i].Get(j);
				if (IsClientInGame(playerid))
				{
					int len;
					new String:color[12];
					if(j ==0)
					{
						len = 16;
						color = "\x07ff6600";
					}
					else
					{
						len = 12;
						color = "\x01";
					}
						
					new String:targetName[len];
					GetClientName(playerid, targetName, len);
					
					// playeroutput also includes the color
					new String:playeroutput[32];
					Format(playeroutput, 32, "%s%s",color,targetName);
					StrCat(message,sizeof(message),playeroutput);
					if(j != players[i].Length -1)
					{
						StrCat(message,sizeof(message), "\x01, ");
					}
				}
			}
			delete players[i];
			StrCat(message,sizeof(message),"\n");
		}
		
		
		
	}
	if(StrEqual(message,"", false))
	{
		PrintToChat(client,"No players in a squad");
	}
	else
	{
		PrintToChat(client,message);
	}
	

	return Plugin_Handled;
}

ArrayList GetSquadPlayers(int team,int squad)
{
	int resourceEntity = GetPlayerResourceEntity();
	ArrayList players = new ArrayList();
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
		{
		
			if(players.Length != 0 && GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1 )
			{
				players.ShiftUp(0);
				players.Set(0,i);
			}
			else
			{	
				players.Push(i);
			}

		}
	}
	return players;
}

public Action Command_Skills(int client, int args)
{
	if(client == 0)
		client = 1;
	int currentTeam = GetClientTeam(client);
	int currentSquad = GetEntProp(client, Prop_Send, "m_iSquad");
	ArrayList squadPlayers = GetSquadPlayers(currentTeam,currentSquad);
	
	new String:message[512] = "";
	

	
	for (new j = 0; j < squadPlayers.Length; j++)
	{
		int playerid =  squadPlayers.Get(j);
		
		
		if (IsClientInGame(playerid))
		{
			new String:targetName[128];
			GetClientName(playerid, targetName, sizeof(targetName));
			Format(targetName, sizeof(targetName), "\x07ff6600%s: \x01",targetName);
			StrCat(message,sizeof(message),targetName);
			
			
			for(int i = 1;i < 5;i++)
			{
				// may do it so if alive use skill else use desiredskill
				new String:property[20];
				Format(property, 20, "m_iSkill%i",i);
				int skill = GetEntProp(playerid, Prop_Send, property);
				if(skill > 8)
				{
					new String:skillName[100];
					GetSkillName(skill,skillName,sizeof(skillName));
					Format(skillName, sizeof(skillName), "%s, ",skillName);
					StrCat(message,sizeof(message),skillName);
				}
			}
			message[strlen(message)-2] = 0; 
			StrCat(message,sizeof(message),"\n");
		}
	}
	
	delete squadPlayers;
	
	PrintToChat(client,message);

	return Plugin_Handled;
}
public Action Command_Hash_Menu(int client, int args)
{
	if(client == 0)
		client = 1;
	Menu menu = new Menu(HashMenuHandler);
	menu.SetTitle("Command List");
	
	menu.AddItem("recycle walls", "Recycle Walls");	
	menu.AddItem("unstuck", "Unstuck");
	menu.AddItem("request lead", "Request Squad Lead");
	menu.AddItem("squadleadvote", "Squad Lead Vote");
	menu.AddItem("squadinfo", "Squad Info");
	menu.AddItem("squadskills", "Squad Skills");
	menu.AddItem("lastcomm", "Last Commander");		
	menu.ExitButton = true;
	menu.Display(client, 10);

}
public int HashMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		switch(param2)
		{
			case 0:
				FakeClientCommand(client,"emp_eng_recycle_walls");
			case 1:
				FakeClientCommand(client,"emp_unstuck");
			case 2:
				FakeClientCommand(client,"sm_rsl");
			case 3:
				SquadLeadVote(client);
			case 4:
				FakeClientCommand(client,"sm_squadinfo");
			case 5:
				FakeClientCommand(client,"sm_squadskills");
			case 6:
				FakeClientCommand(client,"sm_commander");			
		}
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}
void SquadLeadVote(int client)
{
	Menu menu = new Menu(SquadVoteMenuHandler);
	menu.SetTitle("Pick Player");
	
	char idbuffer[32];
	IntToString(client,idbuffer,sizeof(idbuffer));
	menu.AddItem(idbuffer, "Yourself");	
	
	ArrayList players = GetSquadPlayers(GetClientTeam(client),GetEntProp(client, Prop_Send, "m_iSquad"));
	
	char clientName[256];
			
	for(int i = 0;i<players.Length;i++)
	{
		int playerid = players.Get(i);
		if(playerid != client)
		{
			GetClientName(playerid, clientName, sizeof(clientName));
			IntToString(playerid,idbuffer,sizeof(idbuffer));
			menu.AddItem(idbuffer, clientName);
		}
		
	}
	menu.ExitButton = true;
	menu.Display(client, 10);
	
	delete players;
}
public int SquadVoteMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		int targetId = StringToInt(info);
		vote(client,targetId);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}



public Action Command_Check_Commander(int client, int args)
{
		char arg[65];
		if(client == 0)
			client = 1;
		
		GetCmdArg(1, arg, sizeof(arg));
		int team = GetClientTeam(client);
		int target = 0;
		bool foundTarget = false;
		for(int i = 2;i<4;i++)
		{
			if(StrEqual(teamnames[i], arg, false))
			{
				if(team >=2 && team != i && !gameEnded)
				{
					PrintToChat(client,"We don't know!");
					return Plugin_Handled;
				}
				else
				{
					target = comms[i];
					foundTarget = true;
				}
			}
		}
		
		// we use the team we are on
		if(!foundTarget)
		{
			target = comms[team];
		}
		
		if(target != 0 && !IsClientInGame(target))
		{
			target = 0;
		}
		
		
		if(target != 0)
		{
			char targetName[256];
			GetClientName(target, targetName, sizeof(targetName));
			PrintToChat(client,"\x03The last player in the Command Vehicle was \x07ff6600%s\x03.",targetName);
		}
		else
		{
			PrintToChat(client,"There is no commander");
		}
		
		return Plugin_Handled;
}


public Action Command_SL_Vote(int client, int args)
{
	if(client == 0)
		client = 1;
	// find the target
	int target;
	// set the votes.. 
	if(args > 0)
	{
		char arg[65];
		GetCmdArg(1, arg, sizeof(arg));
		
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		
		target_count = ProcessTargetString(
				arg,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_NO_IMMUNITY,
				target_name,
				sizeof(target_name),
				tn_is_ml);
		if(target_count == -7)
		{
			ReplyToCommand(client, " Input applies to more than one target");
			return Plugin_Handled;
		}	
		if (target_count <= 0)
		{
			ReplyToCommand(client, "No Targets detected");
			return Plugin_Handled;
		}
		target = target_list[0];
		
	}
	else
	{
		target = client;
	}
	
	vote(client,target);
	
	return Plugin_Handled;
}
public Action Command_Request_SL(int client, int args)
{
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	FakeClientCommand(client,"say_comm_private \"Requesting lead of %s squad commander!\"",squadnames[squad]); 
	return Plugin_Handled;
}

public Action Command_Assign_Squad(int client, int args)
{
	if(client == 0)
		client = 1;
	int clientTeam = GetClientTeam(client);
	if(comms[clientTeam] != client)
	{
		ReplyToCommand(client, "You must be the commander to assign squads");
		return Plugin_Handled;
	}
	
	// find the target
	int target;
	
	if(args < 2)
	{
		ReplyToCommand(client, "You must have a target and squad");
		return Plugin_Handled;
	}
	
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
			arg,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_NO_IMMUNITY,
			target_name,
			sizeof(target_name),
			tn_is_ml);
			
			
	if(target_count == -7)
	{
		ReplyToCommand(client, " Input applies to more than one target");
		return Plugin_Handled;
	}	
	if (target_count <= 0)
	{
		ReplyToCommand(client, "No Targets detected");
		return Plugin_Handled;
	}
	

	target = target_list[0];
	
	
	int targetTeam = GetClientTeam(target);
	if(clientTeam != targetTeam)
	{
		ReplyToCommand(client, "Target Must be in your own team");
		return Plugin_Handled;
	}
	
	char arg2[65];
	GetCmdArg(2, arg2, sizeof(arg2));
	
	
	int squad = getSquad(arg2);
	
	AssignSquad(client,target,squad);
	
	return Plugin_Handled;
}
void AssignSquad(int origin,int target, int squad)
{
	if(getNumberInSquad(GetClientTeam(origin),squad) == 5)
	{
		PrintToChat(origin, "The squad is full");
		return;
	}
	FakeClientCommand(target,"emp_squad_join %d",squad); 
	char originName[256];
	char targetName[256];
	GetClientName(origin, originName, sizeof(originName));
	GetClientName(target, targetName, sizeof(targetName));
	PrintToChat(origin,"\x03Assigned \x07ff6600%s\x03 to \x04%s\x03 squad",targetName,squadnames[squad]);
	PrintToChat(target,"\x04[SC] \x07ff6600%s\x01 assigned you to \x04%s\x01 squad",originName,squadnames[squad]);
	
}

public Action Command_Change_Channel(int client, int args)
{
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	int team = GetClientTeam(client);
	
	if(team >= 2)
	{
		ReplyToCommand(client, "\x01You must be in \x07CCCCCCspectator\x01 to use this command");
		return Plugin_Handled;
	}
	
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int squad = getSquad(arg);
	SetEntProp(client, Prop_Send, "m_iSquad",squad);
	
	char originName[256];
	GetClientName(client, originName, sizeof(originName));
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) &&  GetClientTeam(i) == team)
		{
			PrintToChat(i,"\x04[SC] \x07ff6600%s\x01 joined channel \x04%s\x01.",originName,squadnames[squad]);
		}			
	} 
	
	return Plugin_Handled;
}


int getNumberInSquad(int team, int squad)
{
	int count = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) &&  GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad")== squad)
		{
			count++;
		}			
	} 
	return count;
}

int getSquad(char[] name)
{
	int num = CharToLower(name[0]) - 96;
	if(num <0 || num > 26)
		num = 0;
	return  num;
}



vote( int client,int target)
{
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");

	
	int resourceEntity = GetPlayerResourceEntity();
	char originName[256];
	char targetName[256];
	GetClientName(client, originName, sizeof(originName));
	GetClientName(target, targetName, sizeof(targetName));
	
	int team = GetClientTeam(client);

	int targetSquad = GetEntProp(target, Prop_Send, "m_iSquad");
	int targetTeam = GetClientTeam(target);
	if(team < 2)
	{
		PrintToChat(client, "You must be in a team to vote");
		return;
	}
	if(team != targetTeam || squad != targetSquad)
	{
		PrintToChat(client, "%s is not in your squad",targetName);
		return;
	}
	if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,target) == 1)
	{
		PrintToChat(client, "%s is already squad leader",targetName);
		return;
	}
	
	playerVotes[client] = target;
	int votes = 0;
	ArrayList squadPlayers = GetSquadPlayers(team,squad);
	
	
	for(int i = 0;i<squadPlayers.Length;i++)
	{
		int playerid = squadPlayers.Get(i);
		if(playerVotes[playerid] == target)
		{
			votes ++;
		}	
	}
	
	
	new String:message[128];
	int requiredVotes = RoundToCeil(float(squadPlayers.Length) * 0.51);
	if(votes >= requiredVotes)
	{
		changeSquadLeader(team,squad,target);
		Format(message, sizeof(message), "\x07ff6600%s\x01 voted for \x07ff6600%s\x01 to become squad leader, \x07ff6600%s\x01 is now the leader",originName,targetName,targetName); 
	}
	else
	{
		Format(message, sizeof(message), "\x07ff6600%s\x01 voted for \x07ff6600%s\x01 to become squad leader (\x073399ff%d\x01/\x04%d\x01). Use \x04/sl [player]\x01 to vote.",originName,targetName, votes,requiredVotes);
	}
	
	for (new i = 0; i < squadPlayers.Length; i++)
	{
			PrintToChat(squadPlayers.Get(i),message);
	}
	delete squadPlayers;
}



changeSquadLeader(int team, int squad,int target)
{
	int resourceEntity = GetPlayerResourceEntity();
	int leader = 0;
	
	
	// we get the squad leader and  swap their position with 2
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
		{
			if(GetEntProp(i, Prop_Send, "m_iSquad")== squad)
			{
				if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1)
				{
					leader = i;
				}
			}
		}
	} 
	if(leader == 0)
	{
		return;
	}
	
	FakeClientCommand(leader,"emp_make_lead %d",target); 
}
public Action Command_Invite_Player(client, const String:command[], args)
{
	int team = GetClientTeam(client);
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int player = StringToInt(arg);
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	// if they are not in the squad assign them, when you are comm 
	if(IsClientInGame(player) && GetClientTeam(player) == team && GetEntProp(client, Prop_Send, "m_bCommander") == 1 && squad != GetEntProp(player, Prop_Send, "m_iSquad"))
	{
		AssignSquad(client,player,squad);
		return Plugin_Handled;
	}
	return Plugin_Continue;
	
}


public OnMapStart()
{
	AutoExecConfig(true, "squadcontrol");
	AddFileToDownloadsTable("sound/squadcontrol/squadvoice_start.wav");
	AddFileToDownloadsTable("sound/squadcontrol/squadvoice_end.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commvoice_start.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commvoice_end.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commchat_alert2.wav");
	AddFileToDownloadsTable("sound/squadcontrol/squadchat_alert2.wav");
	AddFileToDownloadsTable("sound/squadcontrol/squadleader_alert.wav");
	PrecacheSound("squadcontrol/squadvoice_start.wav");
	PrecacheSound("squadcontrol/squadvoice_end.wav");
	PrecacheSound("squadcontrol/commvoice_start.wav");
	PrecacheSound("squadcontrol/commvoice_end.wav");
	PrecacheSound("squadcontrol/commchat_alert2.wav");
	PrecacheSound("squadcontrol/squadchat_alert2.wav");
	PrecacheSound("squadcontrol/squadleader_alert.wav");
	for (int i=1; i<=MaxClients; i++)
	{
		playerVotes[i] = 0;
		// commvotes need to be reset
		commVotes[i] = 0;
		// reset appropriate flags
		playerFlags[i] &= ~(FLAG_SQUAD_VOICE | FLAG_COMM_VOICE);
	}
	comms[2] = 0;
	comms[3] = 0;
	gameEnded = false;
}
public Action Event_Comm_Vote(Event event, const char[] name, bool dontBroadcast)
{
	if(GetEventBool(event, "squadcontrol"))
	{
		// we fired the event, return
		return;
	}
	// dont ask why +1 here I have no idea, but it's neccessary atm
	int voter = GetEventInt(event, "voter_id") + 1;
	int player = GetEventInt(event, "player_id") + 1;
	int team = GetClientTeam(voter);
	
	commVotes[voter] = player;
	RefreshVotes(team);
	
}

public Action Command_Opt_Out(client, const String:command[], args)
{
	// neccessary because the server resets votes as well #readded 
	// otherwise votes would be saved across opt outs.
	for (int i=1; i<=MaxClients; i++)
	{
		if(commVotes[i] == client)
		{
			commVotes[i] = 0;
		}
	}

	RefreshVotes(GetClientTeam(client));
}


 
void RefreshVotes(int team)
{
	if(sc_prelimcommander.IntValue == 0)
		return;

	int resourceEntity = GetPlayerResourceEntity();
	int votes[MAXPLAYERS+1] = {0,...}; // votes for each player
	// add all the comm votes up.
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == team && commVotes[i] != 0)
		{
			// make sure the player wants command
			if(GetEntProp(resourceEntity, Prop_Send, "m_bWantsCommand",4,commVotes[i]))
			{
				votes[commVotes[i]]++;
			}
		}
	}
	int mostVotesClient;
	int mostVotes = 0;
	for (int i=1; i<=MaxClients; i++)
	{
		if(votes[i] >mostVotes)
		{
			mostVotes = votes[i];
			mostVotesClient = i;
		}
	}
	if( mostVotesClient != comms[team])
	{
		if(comms[team] != 0 && IsClientInGame(comms[team]))
		{
			SetEntProp(comms[team], Prop_Send, "m_bCommander",false);
		}
		if(mostVotesClient != 0 && IsClientInGame(mostVotesClient))
		{
			if(!(playerFlags[mostVotesClient] & HINT_PRELIM_COMM))
			{
				playerFlags[mostVotesClient]|=HINT_PRELIM_COMM;
				PrintToChat(mostVotesClient,"\x04[SC] \x01 You have been made preliminary commander. You can now promote players to squad lead. You can also assign players to squads using the invite button or the command \x04/assign <player> <squad>");
			}
			
			SetEntProp(mostVotesClient, Prop_Send, "m_bCommander",true);
		}
		comms[team] = mostVotesClient;
		
	}
}
public int Native_GetCommVotes(Handle plugin, int numParams)
{
	SetNativeArray(1, commVotes, sizeof(commVotes));
}
public int Native_GetComm(Handle plugin, int numParams)
{
	return comms[GetNativeCell(1)];
}

public Event_Elected_Player(Handle:event, const char[] name, bool dontBroadcast)
{	
	// remove commander status for now
	for(int i = 2;i<4;i++)
	{
		if(comms[i] != 0)
		{
			if(IsClientInGame(comms[i]))
			{
				SetEntProp(comms[i], Prop_Send, "m_bCommander",false);
			}
			comms[i] = 0;
		}
	}
	
}
public Event_Game_End(Handle:event, const char[] name, bool dontBroadcast)
{	
	gameEnded = true;
}

void FixCommVotes(int team)
{
	// resend every comm vote as an event when players join teams
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i)  && GetClientTeam(i) == team && commVotes[i] != 0 && IsClientInGame(commVotes[i]))
		{
			// refire the event;
			Event event = CreateEvent("commander_vote");
			if (event == null)
			{
				return;
			}
			event.SetInt("voter_id", i-1);
			event.SetInt("player_id", commVotes[i] -1);
			event.SetBool("squadcontrol", true);
			event.Fire();
		}
	}
}

// taken from the emp_skills.txt file 
GetSkillName(int id,char[] result,resultlength)
{
	switch(id)
	{
		case 16:
			strcopy(result, resultlength, "Wpn Silencer");
		case 32:
			strcopy(result, resultlength, "Enhanced Senses");
		case 64:
			strcopy(result, resultlength, "Radar Stealth");
		case 128:
			strcopy(result, resultlength, "Hide");
		case 256:
			strcopy(result, resultlength, "Vehicle Speed");
		case 512:
			strcopy(result, resultlength, "Dig In");
		case 1024:
			strcopy(result, resultlength, "Damage Increase");
		case 2048:
			strcopy(result, resultlength, "Vehicle Damage");
		case 4096:
			strcopy(result, resultlength, "Defusal");
		case 8192:
			strcopy(result, resultlength, "Armor Detection");
		case 16384:
			strcopy(result, resultlength, "Artillery Feedback");
		case 32768:
			strcopy(result, resultlength, "Increased Armor");
		case 65536:
			strcopy(result, resultlength, "Healing Upgrade");
		case 131072:
			strcopy(result, resultlength, "Repair Upgrade");	
		case 262144:
			strcopy(result, resultlength, "Revive");
		case 524288:
			strcopy(result, resultlength, "Turret Upgrade");
		case 1048576:
			strcopy(result, resultlength, "Vehicle Cooling");
		case 2097152:
			strcopy(result, resultlength, "Health Upgrade");
		case 4194304:
			strcopy(result, resultlength, "Health Regeneration");
		case 8388608:
			strcopy(result, resultlength, "Ammo Increase");
		case 16777216:
			strcopy(result, resultlength, "Stamina Increase");	
		case 33554432:
			strcopy(result, resultlength, "Speed Upgrade");
		case 67108864:
			strcopy(result, resultlength, "Accuracy Upgrade");
		case 134217728:
			strcopy(result, resultlength, "Melee Upgrade");	
	}
}


