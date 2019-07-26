#include <tf2>
#include <tf2items>
#include <tf2attributes>
#include <sdktools>
#include <sdkhooks>
#include <sourcemod>
#include <tf2_stocks>
#include <buildings>

#pragma semicolon 1;
#pragma newdecls required;

Handle hCreateDroppedWeapon;
Handle hInitDroppedWeapon;
Handle hPickupWeaponFromOther;

ConVar gCurrentYear;
ConVar gMpTournamentWhitelist;

ArrayList gBlockedQualities;
ArrayList gBlockedAttributes;
ArrayList gCreatedWeapons;

public Plugin myinfo =
{
	name = "Years",
	description = "Year specific logic",
	author = "Jim",
	version = "1.0",
	url = ""
};

enum NamedItem {
	NIClient,
	String:NIClassname[32],
	NIDefIndex,
	NILevel,
	NIQuality,
	NIEntity,
};

public void OnPluginStart() {
	Handle hConf = LoadGameConfigFile("weapons.games");

	StartPrepSDKCall(SDKCall_Static);

	if(!PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "Create")) {
		LogMessage("[DW] Failed to set CDW from conf!");
	}

	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	hCreateDroppedWeapon = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_Entity);

	if(!PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "InitDroppedWeapon")) {
		LogMessage("[DW] Failed to set IDW from conf!");
	}

	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	hInitDroppedWeapon = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Player);

	if(!PrepSDKCall_SetFromConf(hConf, SDKConf_Signature, "PickupWeaponFromOther")) {
		PrintToServer("[DW] Failed to set PWFO from conf!");
	}

	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	hPickupWeaponFromOther = EndPrepSDKCall();
	
	delete hConf;

	gBlockedQualities = new ArrayList();
	gBlockedAttributes = new ArrayList();
	gCreatedWeapons = new ArrayList();
	
	HookEvent("player_spawn", Hook_PlayerSpawn, EventHookMode_Post);
	HookEvent("post_inventory_application", Hook_PostInventoryApplication, EventHookMode_Post);

	gMpTournamentWhitelist = FindConVar("mp_tournament_whitelist");
	gCurrentYear = CreateConVar("sm_current_year", "2019", "Current year", 0, true, 2007.0, true, 2019.0);
	gCurrentYear.AddChangeHook(YearChanged);

	YearChanged(gCurrentYear, "", "");

	RegAdminCmd("sm_year", Command_Year, ADMFLAG_GENERIC);
}

public Action Command_Year(int client, int args) {
	char year[8];

	GetCmdArg(1, year, sizeof(year));

	gCurrentYear.IntValue = StringToInt(year);

	ReplyToCommand(client, "[SM] Year set to %s", year);

	return Plugin_Handled;
}

public void Hook_PlayerSpawn(Handle event, char[] name, bool dontBroadcast) {
}

public void Hook_PostInventoryApplication(Event event, char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	for(int slot = 0; slot < 8; slot++) {
        int weapon = GetPlayerWeaponSlot(client, slot);
        
        if(IsValidEntity(weapon)) {
			NamedItem item[NamedItem];

			item[NIClient] = client;
			GetEntityClassname(weapon, item[NIClassname], sizeof(item[NIClassname]));
			item[NIDefIndex] = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			item[NILevel] = GetEntProp(weapon, Prop_Send, "m_iEntityLevel");
			item[NIQuality] = GetEntProp(weapon, Prop_Send, "m_iEntityQuality");
			item[NIEntity] = weapon;

			UpdateItem(item);
        }
    }
}

public void UpdateItem(NamedItem item[NamedItem]) {
	//Skip items that aren't equipped
	int slot = GetWeaponSlot(item[NIClient], item[NIEntity]);

	if(slot == -1) {
		PrintToServer("Ignoring item that is no longer equipped");
		return;
	}

	//Create replacement item if needed
	Handle replacement = CreateReplacementItem(item);

	if(replacement == INVALID_HANDLE) {
		PrintToServer("No replacement item created");
		return;
	}

	int created = TF2Items_GiveNamedItem(item[NIClient], replacement);

	if(!IsValidEntity(created)) {
		PrintToServer("TF2Items_GiveNamedItem failed");
		return;
	}

	gCreatedWeapons.Push(created);

	//Remove old item
	TF2_RemoveWeaponSlot(item[NIClient], slot);
	PrintToServer("Original item unequipped");
	
	//Equip replaced item (will be invisible)
	EquipPlayerWeapon(item[NIClient], created);
	PrintToServer("Replacement item equipped");

	//Create dropped version of replaced weapon
	float position[3];
	float angles[3];

	GetClientEyePosition(item[NIClient], position);
	GetClientEyeAngles(item[NIClient], angles);
	int dropped = CreateDroppedWeapon(created, item[NIClient], position, angles);


	if(dropped == INVALID_ENT_REFERENCE) {
		return;
	}

	gCreatedWeapons.Push(dropped);

	//"Pick up" dropped weapon, which will be visible
	SDKCall(hPickupWeaponFromOther, item[NIClient], dropped);

	delete replacement;
}

stock Handle CreateReplacementItem(NamedItem item[NamedItem]) {
	bool replace = false;

	if(gBlockedQualities.FindValue(item[NIQuality]) > -1) {
		item[NIQuality] = 6;
		replace = true;
	}

	int attributes[16];
	float attributeValues[16];
	int attributeCount = TF2Attrib_GetSOCAttribs(item[NIEntity], attributes, attributeValues);
	int allowedAttributeCount = 0;

	//Check for blocked attributes requiring item replacement
	if(attributeCount != -1) {
		for(int i = 0; i < attributeCount; i++) {
			if(gBlockedAttributes.FindValue(attributes[i]) > -1) {
				replace = true;
			} else {
				allowedAttributeCount++;
			}
		}
	} else {
		replace = true;
	}

	if(!replace) {
		return INVALID_HANDLE;
	}
	
	//Create replacement
	//FIXME: try to fix GiveNamedItem failing or crashing server (FORCE_GENERATION?)
	Handle replacement = TF2Items_CreateItem(PRESERVE_ATTRIBUTES | OVERRIDE_ALL | FORCE_GENERATION);
	TF2Items_SetQuality(replacement, item[NIQuality] ? item[NIQuality] : 6);
	TF2Items_SetItemIndex(replacement, item[NIDefIndex]);
	TF2Items_SetLevel(replacement, item[NILevel]);
	TF2Items_SetClassname(replacement, item[NIClassname]);
	TF2Items_SetNumAttributes(replacement, allowedAttributeCount);

	int index = 0;

	//Add allowed attributes to replacement
	for(int i = 0; i < attributeCount; i++) {
		if(gBlockedAttributes.FindValue(attributes[i]) == -1) {
			TF2Items_SetAttribute(replacement, index, attributes[i], attributeValues[i]);
			index++;
		}
	}

	return replacement;
}

public void YearChanged(ConVar convar, char[] oldValue, char[] newValue) {
	gBlockedQualities.Clear();
	gBlockedAttributes.Clear();

	if(gCurrentYear.IntValue < 2008) {
		gBlockedQualities.Push(6); //Unique
		gBlockedAttributes.Push(142); //Paint
	}

	if(gCurrentYear.IntValue < 2010) {
		gBlockedQualities.Push(5); //Unusual
		gBlockedQualities.Push(3); //Vintage
	}

	if(gCurrentYear.IntValue < 2011) {
		gBlockedQualities.Push(11); //Strange
		gBlockedQualities.Push(13); //Haunted
		gBlockedQualities.Push(1); //Genuine
		gBlockedAttributes.Push(214); //Strange counter
		gBlockedAttributes.Push(294); //Strange counter 2
		gBlockedAttributes.Push(134); //Unusual effect
		gBlockedAttributes.Push(747); //Unusual effect
	}
	
	if(gCurrentYear.IntValue < 2012) {
		gBlockedAttributes.Push(379); //Strange parts
		gBlockedAttributes.Push(380); //Strange parts
		gBlockedAttributes.Push(381); //Strange parts
		gBlockedAttributes.Push(382); //Strange parts
		gBlockedAttributes.Push(383); //Strange parts
		gBlockedAttributes.Push(384); //Strange parts
		gBlockedAttributes.Push(385); //Strange parts
	}

	if(gCurrentYear.IntValue < 2013) {
		gBlockedAttributes.Push(2013); //Killstreak 
		gBlockedAttributes.Push(2014); //Killstreak Sheen
		gBlockedAttributes.Push(2025); //Killstreak Tier
		gBlockedAttributes.Push(2027); //Australium
		gBlockedAttributes.Push(2022); //Australium
		gBlockedAttributes.Push(542); //Australium
	}

	if(gCurrentYear.IntValue < 2014) {
		gBlockedQualities.Push(14); //Collector's
		gBlockedQualities.Push(750); //Unusual taunt
	}

	if(gCurrentYear.IntValue < 2015) {
		gBlockedQualities.Push(15); //Decorated
		gBlockedAttributes.Push(725); //Skin wear
		gBlockedAttributes.Push(2053); //Festivized
		gBlockedAttributes.Push(731); //Inspecting
	}

	//War paints
	if(gCurrentYear.IntValue < 2017) {
		gBlockedAttributes.Push(834);
		gBlockedAttributes.Push(866);
		gBlockedAttributes.Push(867);
	}

	//Date attributes that seem to break things
	gBlockedAttributes.Push(143);
	gBlockedAttributes.Push(185);
	gBlockedAttributes.Push(211);
	gBlockedAttributes.Push(302);
	gBlockedAttributes.Push(374);
	gBlockedAttributes.Push(751);
	gBlockedAttributes.Push(2010);
	gBlockedAttributes.Push(2011);

	char whitelist[PLATFORM_MAX_PATH];
	Format(whitelist, sizeof(whitelist), "cfg/whitelists/%d.txt", gCurrentYear.IntValue);
	gMpTournamentWhitelist.SetString(whitelist);

	ServerCommand("exec \"years/reset.cfg\"");
	ServerCommand("exec \"years/%d.cfg\"", gCurrentYear.IntValue);
}

public Action Buildings_CanPlayerPickup(int client, int building, bool &result) {
	if(gCurrentYear.IntValue < 2010) {
		result = false;

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

stock int GetWeaponSlot(int client, int weapon) {
	if (client == 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || weapon == 0 || weapon < MaxClients || !IsValidEntity(weapon))
		return -1;

	for (int i = 0; i < 5; i++)
	{
		if (GetPlayerWeaponSlot(client, i) != weapon)
			continue;

		return i;
	}

	return -1;
}

int CreateDroppedWeapon(int fromWeapon, int client, const float origin[3], const float angles[3]) {
	// Offset of the CEconItemView class inlined on the weapon.
	// Manually using FindSendPropInfo as 1) it's a sendtable, not a value,
	// and 2) we just want a pointer to it, not the value at that address.
	int itemOffset = FindSendPropInfo("CTFWeaponBase", "m_Item");

	if(itemOffset == -1) {
		ThrowError("Failed to find m_Item on CTFWeaponBase");
	}
	
	// Can't get model directly. Instead get index and look it up in string table.
	char model[PLATFORM_MAX_PATH];
	int modelidx = GetEntProp(fromWeapon, Prop_Send, "m_iWorldModelIndex");
	ModelIndexToString(modelidx, model, sizeof(model));
	
	int droppedWeapon = SDKCall(hCreateDroppedWeapon, client, origin, angles, model, GetEntityAddress(fromWeapon) + view_as<Address>(itemOffset));
	
	if(droppedWeapon != INVALID_ENT_REFERENCE) {
		SDKCall(hInitDroppedWeapon, droppedWeapon, client, fromWeapon, false, false);
	}

	return droppedWeapon;
}

void ModelIndexToString(int index, char[] model, int size) {
	int table = FindStringTable("modelprecache");
	ReadStringTable(table, index, model, size);
}
