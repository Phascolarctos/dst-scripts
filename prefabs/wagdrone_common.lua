local REGISTERED_TARGET_TAGS

local function FindShockTargets(x, z, radius)
	if REGISTERED_TARGET_TAGS == nil then
		REGISTERED_TARGET_TAGS = TheSim:RegisterFindTags(
			{ "_combat" },
			{ "INLIMBO", "flight", "invisible", "notarget", "noattack", "ghost", "playerghost", "shadowthrall", "shadow", "shadowcreature", "shadowminion", "shadowchesspiece", "brightmare", "brightmareboss", "wagdrone", "wagboss" }
		)
	end
	return TheSim:FindEntities_Registered(x, 0, z, radius, REGISTERED_TARGET_TAGS)
end

--------------------------------------------------------------------------

local function SetLedEnabled(inst, enable)
	if enable then
		inst.AnimState:Show("LIGHT_ON")
	else
		inst.AnimState:Hide("LIGHT_ON")
	end
end

--------------------------------------------------------------------------

local function teleport_override_fn(inst)
	local x, y, z = inst.Transform:GetWorldPosition()
	if TheWorld.Map:IsPointInWagPunkArena(x, y, z) then
		return Vector3(x, y, z)
	end
end

local function PreventTeleportFromArena(inst)
	if inst.components.teleportedoverride == nil then
		inst:AddComponent("teleportedoverride")
		inst.components.teleportedoverride:SetDestPositionFn(teleport_override_fn)
	end
end

--------------------------------------------------------------------------

local function RemoveQuestConfig(inst)
	inst:RemoveComponent("teleportedoverride")
end

local function RemoveLootConfig(inst)
	inst:RemoveComponent("workable")
end

local function RemoveFriendlyConfig(inst)
	inst:RemoveComponent("inventoryitem")
	inst:RemoveComponent("finiteuses")
	inst:RemoveComponent("knownlocations")
	inst:RemoveTag("notarget")
end

--------------------------------------------------------------------------

local function OnDespawn(inst)
	if inst:IsAsleep() then
		inst:Remove()
		return
	end
	inst:ListenForEvent("entitysleep", inst.Remove)
	inst.persists = false
	inst.components.locomotor:Stop()
	--stategraph will also handle the event
end

local function OnGotCommander(inst, data)
	RemoveLootConfig(inst)
	RemoveFriendlyConfig(inst)
	PreventTeleportFromArena(inst)

	inst.components.entitytracker:TrackEntity("robot", data.commander)
	inst.AnimState:OverrideSymbol("light_yellow_off", inst.prefab, "light_red_off")
	inst.AnimState:OverrideSymbol("light_yellow_on", inst.prefab, "light_red_on")
	inst:ListenForEvent("onremove", inst._onremovecommander, data.commander)

	if inst.sg:HasStateTag("off") and inst.sg:HasStateTag("idle") then
		inst.AnimState:PlayAnimation("off_idle")
	end
end

local function _DoClearCommander(inst, commander)
	inst.components.entitytracker:ForgetEntity("robot", commander)
	inst.AnimState:ClearOverrideSymbol("light_yellow_off")
	inst.AnimState:ClearOverrideSymbol("light_yellow_on")
end

local function OnLostCommander(inst, data)
	inst:RemoveEventCallback("onremove", inst._onremovecommander, data.commander)
	_DoClearCommander(inst, data.commander)
	inst:PushEvent("deactivate")

	--wagdrone_rolling specific
	inst.dest = nil
end

local function MakeHackable(inst)
	inst:AddComponent("entitytracker")

	inst._onremovecommander = function(commander) _DoClearCommander(inst, commander) end

	inst:ListenForEvent("gotcommander", OnGotCommander)
	inst:ListenForEvent("lostcommander", OnLostCommander)
	inst:ListenForEvent("despawn", OnDespawn)
end

local function HackableLoadPostPass(inst)--, ents, data)
	local robot = inst.components.entitytracker:GetEntity("robot")
	if robot then
		if robot.components.commander then
			robot.components.commander:AddSoldier(inst)
		else
			inst.components.entitytracker:ForgetEntity("robot")
		end
	end
end

--------------------------------------------------------------------------

SetSharedLootTable("wagdrone_common",
{
	{ "wagdrone_parts",		1.0 },
	{ "gears",				1.0 },
	{ "gears",				0.333 },
	{ "transistor",			0.667 },
	{ "wagpunk_bits",		1.0	},
	{ "wagpunk_bits",		1.0	},
	{ "wagpunk_bits",		0.5	},
})

local function OnWorked(inst, worker)
	inst:AddComponent("lootdropper")
	inst.components.lootdropper:SetChanceLootTable("wagdrone_common")
	inst.components.lootdropper:DropLoot(inst:GetPosition())
	if inst:IsAsleep() then
		inst:Remove()
	else
		inst.persists = false
		inst:AddTag("NOCLICK")
		inst:ListenForEvent("entitysleep", inst.Remove)
		inst:ListenForEvent("animover", ErodeAway)
		inst.AnimState:PlayAnimation("death")
		inst.SoundEmitter:PlaySound("rifts5/wagdrone_flying/death")
	end
end

local function ChangeToLoot(inst)
	if inst.components.workable == nil then
		RemoveQuestConfig(inst)
		RemoveFriendlyConfig(inst)

		inst:PushEvent("deactivate")

		inst:AddComponent("workable")
		inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
		inst.components.workable:SetWorkLeft(1)
		inst.components.workable:SetOnFinishCallback(OnWorked)
		if inst.sg:HasStateTag("off") and inst.sg:HasStateTag("idle") then
			inst.AnimState:PlayAnimation("damaged_idle_loop", true)
		else
			inst.components.workable:SetWorkable(false)
		end
	end
end

--------------------------------------------------------------------------

local function RememberDeployPoint(inst, dont_overwrite)
	inst.components.knownlocations:RememberLocation("deploypoint", inst:GetPosition(), dont_overwrite)
end

local function ForgetDeployPoint(inst)
	inst.components.knownlocations:ForgetLocation("deploypoint")
end

local function toground(inst)
	RememberDeployPoint(inst)
end

local topocket = ForgetDeployPoint

local function OnDepleted(inst)
	ForgetDeployPoint(inst)
	inst:PushEvent("deactivate")
end

local function ChangeToFriendly(inst)
	if inst.components.inventoryitem == nil then
		RemoveQuestConfig(inst)
		RemoveLootConfig(inst)

		inst.components.health:SetPercent(1)
		inst:AddTag("notarget")

		inst:AddComponent("inventoryitem")
		inst.components.inventoryitem:SetOnDroppedFn(toground)
		inst.components.inventoryitem:SetOnPutInInventoryFn(topocket)
		inst.components.inventoryitem.nobounce = true

		inst:AddComponent("finiteuses")
		inst.components.finiteuses:SetMaxUses(TUNING.WAGDRONE_ROLLING_USES)
		inst.components.finiteuses:SetUses(TUNING.WAGDRONE_ROLLING_USES)
		inst.components.finiteuses.onfinished = OnDepleted

		inst:AddComponent("knownlocations")

		if not POPULATING then
			toground(inst)
			inst:PushEvent("activate")
		end

		if inst.sg:HasStateTag("off") and inst.sg:HasStateTag("idle") then
			inst.AnimState:PlayAnimation("off_idle")
		end
	end
end

local function MakeFriendablePristine(inst)
	--Sneak this into pristine state for optimization
	inst:AddTag("__inventoryitem")
end

local function MakeFriendable(inst)
	--Remove this tag so that it can be added properly when replicating component below
	inst:RemoveTag("__inventoryitem")

	inst:PrereplicateComponent("inventoryitem")
end

local function IsFriendly(inst)
	return inst.components.inventoryitem ~= nil
end

local function FriendlySave(inst, data)
	data.isfriend = IsFriendly(inst) or nil
end

local function FriendlyPreLoad(inst, data, ents)
	if data and data.isfriend then
		ChangeToFriendly(inst)
	end
end

--------------------------------------------------------------------------

return
{
	FindShockTargets = FindShockTargets,
	SetLedEnabled = SetLedEnabled,
	MakeHackable = MakeHackable,
	HackableLoadPostPass = HackableLoadPostPass,
	PreventTeleportFromArena = PreventTeleportFromArena,
	ChangeToLoot = ChangeToLoot,
	ChangeToFriendly = ChangeToFriendly,
	MakeFriendablePristine = MakeFriendablePristine,
	MakeFriendable = MakeFriendable,
	IsFriendly = IsFriendly,
	FriendlySave = FriendlySave,
	FriendlyPreLoad = FriendlyPreLoad,
	RememberDeployPoint = RememberDeployPoint,
	ForgetDeployPoint = ForgetDeployPoint,
}
