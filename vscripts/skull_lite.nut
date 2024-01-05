//-----------------------------------------------------------------------------
// Original idea and SourcePawn script made by Mikusch
// https://steamcommunity.com/profiles/76561198071478507
// https://github.com/Mikusch/tf2-misc/blob/master/addons/sourcemod/scripting/skull.sp
//
// Rewritten to Vscript by CzechMate
// https://steamcommunity.com/profiles/76561198220559891
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// Constants that can be changed
//
const skull_speed = 20
const skull_count = 1
const skull_delete_self_on_contact = false //Warning: When the skull gets deleted, it doesn't stop the looping sound.

const multiple_skulls_target_one_player = false
const target_team_red = true
const target_team_blu = true
const crash_client = false

const model = "models/props_mvm/mvm_human_skull.mdl"
const model_scale = 1

const sound = "music/bump_in_the_night.wav"
const sound_radius = 1500
//
//-----------------------------------------------------------------------------

PrecacheModel(model)
PrecacheSound(sound)

class SkullData {
	entindex = null;
	m_target = 0;
	observer = null;
	ambient = null;
};

g_skulls <- []

//Events
ClearGameEventCallbacks();

function OnGameEvent_teamplay_round_start(params) {
	if (IsInWaitingForPlayers()) {
		return
	}

	// Create skulls based on the skull_count value.
	for (local i = 0; i < skull_count; i++) {
		g_skulls.append(SkullData())
		CreateSkull()
	}
}

//idk how to listen for client console commands to prevent them from kill binding... meaning they can take the easy way out... for now.
__CollectGameEventCallbacks(this)

function OnGameFrame() {
	for (local index = 0; index < g_skulls.len(); index++) {
		local data = g_skulls[index]
		if (data.entindex) {
			SkullThink(index, data)
		}
	}
	return -1
}

function CreateSkull() {
	local data = SkullData()
	local skull = Entities.CreateByClassname("prop_dynamic")
	if (skull != null) {
		data.entindex = skull.entindex()
		skull.KeyValueFromString("model", model)
		skull.KeyValueFromInt("modelscale", model_scale)

		// Hammer limit is 32768
		local worldMins = Vector(-25000, -25000, -25000)
		local worldMaxs = Vector(25000, 25000, 25000)

		local origin = Vector(RandomFloat(worldMins.x, worldMaxs.x), RandomFloat(worldMins.y, worldMaxs.y), RandomFloat(worldMins.z, worldMaxs.z))
		skull.KeyValueFromVector("origin", origin)

		// Generates random angles.
		local angles = Vector(RandomFloat(0.0, 360.0), RandomFloat(0.0, 360.0), RandomFloat(0.0, 360.0))
		skull.KeyValueFromVector("angles", angles)

		local skullName = "Skull" + data.entindex; // generates a unique name
		skull.KeyValueFromString("targetname", skullName)

		// Spawns the skull.
		Entities.DispatchSpawn(skull)

		local observer = Entities.CreateByClassname("info_observer_point")
		EntFireByHandle(observer, "SetParent", skullName, -1, null, null)
		observer.KeyValueFromVector("origin", origin)
		observer.KeyValueFromVector("angles", angles)
		Entities.DispatchSpawn(observer)

		// creates an ambient_generic entity
		local ambient = SpawnEntityFromTable("ambient_generic", {
			targetname = "AG",
			SourceEntityName = skullName,
			message = sound,
			health = 10,
			radius = sound_radius,
			spawnflags = 0
		})

		data.entindex = skull
		data.m_target = 0
		data.observer = observer
		data.ambient = ambient
		g_skulls.append(data)
	}
}

function SelectRandomTarget(index) {
	// Resets the target of the skull at the given index.
	g_skulls[index].m_target = 0

	// Creates an array to hold the valid clients.
	local clients = []
	local total = 0

	// Iterates over each client.
	local MaxPlayers = MaxClients().tointeger()
	for (local client = 1; client <= MaxPlayers; client++) {
		if (!IsValidSkullTarget(client))
			continue

		if (multiple_skulls_target_one_player == false) {
			local isTargeted = false
			for (local i = 0; i < g_skulls.len(); i++) {
				if (i != index && g_skulls[i].m_target == client) {
					isTargeted = true
					break;
				}
			}

			if (isTargeted)
				continue
		}

		// Adds the client to the array of valid clients.
		clients.append(client)
		total++
	}

	if (total) {
		g_skulls[index].m_target = clients[RandomInt(0, total - 1)]; // Selects a random target
		//printl("Next target is: " + NetProps.GetPropString(PlayerInstanceFromIndex(g_skulls[index].m_target), "m_szNetname"))

		//ClientPrint(null, Constants.EHudNotify.HUD_PRINTTALK, "\x07FBECCBSomeone is being watched...\x07")
		return true
	}
	return false
}

function SkullThink(index, data) {
	if (data.m_target != 0 && IsValidSkullTarget(data.m_target)) {
		local targetOrigin = PlayerInstanceFromIndex(data.m_target).EyePosition()
		local skullOrigin = data.entindex.GetOrigin()

		local direction = targetOrigin - skullOrigin;
		direction.Norm()

		data.entindex.SetForwardVector(direction)
		local speed = skull_speed

		local skull = data.entindex
		local ambient = data.ambient

		local hullmin = skull.GetBoundingMins()
		local hullmax = skull.GetBoundingMaxs()

		// outside the world or in solid wall? speed it up.
		local traceTable = {
			start = skullOrigin,
			end = skullOrigin,
			hullmin = hullmin,
			hullmax = hullmax,
			mask = Constants.FContents.CONTENTS_SOLID | Constants.FContents.CONTENTS_MOVEABLE | Constants.FContents.CONTENTS_PLAYERCLIP | Constants.FContents.CONTENTS_WINDOW | Constants.FContents.CONTENTS_GRATE | Constants.FContents.CONTENTS_MONSTER,
			ignore = skull
		}
		TraceHull(traceTable)
		if (traceTable.hit) {
			speed *= 5
		}

		//DebugDrawBox(skullOrigin, hullmin, hullmax, 255, 0, 0, 100, 0)

		direction *= speed * FrameTime()

		local newSkullOrigin = skullOrigin + direction;
		data.entindex.SetAbsOrigin(newSkullOrigin)

		local player = PlayerInstanceFromIndex(data.m_target)
		local player_name = NetProps.GetPropString(player, "m_szNetname")

		if ("enthit" in traceTable) {
			if (traceTable.enthit == player) {
				ClientPrint(null, Constants.EHudNotify.HUD_PRINTTALK, format("\x07FBECCB%s fell victim to the skull...\x07", player_name))
				CrashClient(player, data)
				if (skull_delete_self_on_contact) {
					EntFireByHandle(ambient, "Volume", "0", -1, null, null) // This doesn't actually do anything ://
					data.entindex.Destroy()
					g_skulls.remove(index)
				} else {
					SelectRandomTarget(index)
				}
			}
		}
	} else {
		SelectRandomTarget(index)
	}
}

function IsValidSkullTarget(client) {
	local player = PlayerInstanceFromIndex(client)

	if (player == null || player == 0) {
		return false
	}

	if (NetProps.GetPropInt(player, "m_iObserverMode") != 0) {
		return false
	}

	local pTeam = player.GetTeam()
	if (pTeam == 0 || pTeam == 1 || pTeam == null) {
		return false
	}

	if (target_team_red != true) {
		if (pTeam == 2) {
			return false
		}
	}

	if (target_team_blu != true) {
		if (pTeam == 3) {
			return false
		}
	}

	if (!NetProps.GetPropInt(player, "m_lifeState") == 0) {
		//0 = alive
		return false
	}

	if ((player.InCond(Constants.ETFCond.TF_COND_HALLOWEEN_GHOST_MODE))) {
		return false
	}

	// If none of the above conditions were met, the player is a valid target.
	return true
}

function CrashClient(player, data) {
	if (crash_client == true) {
		player.Destroy()
	} else {
		local playerMaxHealth = player.GetMaxHealth()
		player.TakeDamage(playerMaxHealth * 9999, 1, data.entindex)
	}
}