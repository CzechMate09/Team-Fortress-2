ClearGameEventCallbacks()

////////////////////////////////////////////////////////////////////////////
const model_scale = 0.90
//idk if there is a way to disable/hide bodygroups of a model using vscript, so i just recompiled the model and removed the "class" bodygroup myself
const mvm_revive_tombstone_no_hologram = "models/props_mvm/mvm_revive_tombstone_no_hologram.mdl" 
const mvm_revive_tombstone = "models/props_mvm/mvm_revive_tombstone.mdl"
const offset = 40
////////////////////////////////////////////////////////////////////////////

::VectorDistance <- function(vec1, vec2) {
    local diff = vec1 - vec2
    return sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)
}

function gibThink() {
	if (self == null || !self.IsValid())
		return -1

	local scope = self.GetScriptScope()

	if (scope.hReviveMarker == null || !scope.hReviveMarker.IsValid()) 
		return -1

	if (self == null || !self.IsValid())
		return -1

	local hPlayer = NetProps.GetPropEntity(scope.hReviveMarker, "m_hOwner")
	local iPlayerLifeState = NetProps.GetPropInt( hPlayer, "m_lifeState" )

	if ( iPlayerLifeState == 0 ) {
		self.Destroy()
		return -1
	}

	if (scope.isBeingRevived == true) {
		local revMarkerOrigin = scope.hReviveMarker.GetOrigin()
		revMarkerOrigin.z += 20
		local revMarkerAngles = scope.hReviveMarker.GetAbsAngles()
		local gibOrigin = self.GetOrigin()
		local gibAngles = self.GetAbsAngles()
		local maxHealth = NetProps.GetPropInt(scope.hReviveMarker, "m_iMaxHealth" )
		local currentHealth = NetProps.GetPropInt(scope.hReviveMarker, "m_iHealth")
        local distance = VectorDistance(gibOrigin, revMarkerOrigin);

		local direction = revMarkerOrigin - gibOrigin;
		direction.Norm()
		
		local angles = revMarkerAngles - gibAngles
		local healthPercentage = (currentHealth * 1.0 / maxHealth)

		local speed =  healthPercentage * 80 * healthPercentage * offset / maxHealth
		speed *= FrameTime()
		direction *= speed
		angles *= speed/10

		local newGibOrigin = gibOrigin + direction;
		local newGibAngles = gibAngles + angles;

        if (distance >= 0.5) {
			self.SetAbsOrigin(newGibOrigin)
        }

		self.SetAbsAngles(newGibAngles)
		return -1
	}
}

function OnGameEvent_revive_player_notify(params) {
	local isBeingRevived = true
	local hReviveMarker = EntIndexToHScript(params.marker_entindex)
	local revMarkerOrigin = hReviveMarker.GetOrigin()
	local revMarkerAngles = hReviveMarker.GetAbsAngles()
	local reviveMarkerOwner = EntIndexToHScript(params.entindex) //ent index of the owner
	local reviveMarkerTeam = reviveMarkerOwner.GetTeam()
	local reviveMarkerClass = reviveMarkerOwner.GetPlayerClass()
	local mins = Vector(revMarkerOrigin.x, revMarkerOrigin.y, revMarkerOrigin.z)
	local maxs = Vector(revMarkerOrigin.x + offset, revMarkerOrigin.y + offset, revMarkerOrigin.z)
	
	local className = ""
	local gibsModelAmount = 0
	
	local hPlayer = NetProps.GetPropEntity(hReviveMarker, "m_hOwner")
	local iPlayerLifeState = NetProps.GetPropInt( hPlayer, "m_lifeState" )
    local targetnameCheck = params.entindex.tostring();

	hReviveMarker.SetModelSimple(mvm_revive_tombstone_no_hologram)

	switch (reviveMarkerClass) {
		case 1:
			className = "scout"
			gibsModelAmount = 9
			break
		case 3:
			className = "soldier"
			gibsModelAmount = 8
			break
		case 7:
			className = "pyro"
			gibsModelAmount = 8
			break
		case 4:
			className = "demo"
			gibsModelAmount = 6
			break
		case 6:
			className = "heavy"
			gibsModelAmount = 7
			break
		case 9:
			className = "engineer"
			gibsModelAmount = 7
			break
		case 5:
			className = "medic"
			gibsModelAmount = 8
			break
		case 2:
			className = "sniper"
			gibsModelAmount = 7
			break
		case 8:
			className = "spy"
			gibsModelAmount = 7
			break
		default:
			className = ""
			gibsModelAmount = 0
			break
	}


	if ( iPlayerLifeState == 0 ) {
		if (targetnameCheck) {
			EntFire(targetnameCheck, "Kill");
		}

		if (targetnameCheck + "_physics") {
			EntFire(targetnameCheck + "_physics", "Kill");
		}
		return -1
	}

	if (targetnameCheck + "_physics" != null) {
		EntFire(targetnameCheck + "_physics", "Kill")
	}

	local skin = (reviveMarkerTeam == 2) ? 0 : 1
	
	for (local i = 0; i < gibsModelAmount; i++) {

		local randomOrigin = Vector(RandomFloat(mins.x, maxs.x), RandomFloat(mins.y, maxs.y), RandomFloat(mins.z, maxs.z))
		local randomAngles = Vector(RandomFloat(0.0, 360.0), RandomFloat(0.0, 360.0), RandomFloat(0.0, 360.0))
		local gibNumber = i + 1

		local targetname = params.entindex.tostring()
		local model = "models/player/gibs/" + className + "gib00" + gibNumber + ".mdl"
		PrecacheEntityFromTable({ classname = "prop_dynamic_override", model = model });

		local gib = SpawnEntityFromTable("prop_dynamic_override",
		{
			targetname = targetname,
			model = model,
			origin = randomOrigin,
			angles = randomAngles,
			modelscale = model_scale,
			solid = 0,
			skin = skin,
		})

		if (gib != null) {
			gib.ValidateScriptScope()
			local scope = gib.GetScriptScope()
            scope.hReviveMarker <- hReviveMarker
            scope.isBeingRevived <- true;
			scope.gibThink <- gibThink
			AddThinkToEnt(gib, "gibThink")
		}
	}

}

function OnGameEvent_revive_player_stopped(params) {
    local targetname = params.entindex.tostring() // owner of the revive marker
	local hReviveMarker = null
	while (hReviveMarker = Entities.FindByClassname(hReviveMarker, "entity_revive_marker")) {
		if (NetProps.GetPropEntity(hReviveMarker, "m_hOwner").entindex() == params.entindex){
			hReviveMarker.SetModelSimple(mvm_revive_tombstone)
		}
	}
    local gib = null;
    while (gib = Entities.FindByName(gib, targetname)) {
        if (gib != null && gib.IsValid()) {
		
            // Store properties
            local origin = gib.GetOrigin()
            local angles = gib.GetAbsAngles()
            local model = gib.GetModelName()
            local skin = gib.GetSkin()
            
            // Remove the gib
            gib.Destroy()

			PrecacheEntityFromTable({ classname = "prop_physics_override", model = model });
            // Spawn prop_physics_override with the same properties
            local prop = SpawnEntityFromTable("prop_physics_override", {
				targetname = targetname + "_physics"
                model = model,
                origin = origin,
                angles = angles,
                skin = skin,
                modelscale = model_scale,
				spawnflags = 6,
            });
            
            if (prop != null) {
                prop.ValidateScriptScope()
                local scope = prop.GetScriptScope()
                if (scope != null) {
                    scope.isBeingRevived <- false
                }
            }
        }
    }
}

function OnGameEvent_player_spawn(params) {
	local hPlayer = GetPlayerFromUserID(params.userid)
	local targetname = hPlayer.entindex()
	
	if (targetname) {
		EntFire(targetname, "Kill")
	}

	if (targetname + "_physics") {
		EntFire(targetname + "_physics", "Kill")
	}
}

__CollectGameEventCallbacks(this)