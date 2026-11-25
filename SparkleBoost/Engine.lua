-- SparkleBoost interaction engine.
-- Derived from N3zr0k/ForeverLootSparkles_Coloring Sparkles.lua
-- blob 52d93bfc9484e9b8f8fd37e6d2a93996b82d2eba, accessed 2026-11-16.
-- Original classification/soft-target logic: Forever Loot Sparkles / Lueur.
-- Modifications (C) 2026 Sola. SPDX-License-Identifier: GPL-3.0-or-later

-- Cursor, quest and corpse classification and target discovery are adapted
-- from the upstream GPL engine. SparkleBoost supplies its own renderer and
-- settings journal. Enhancement is opt-in, limited to one nearby target,
-- suspended visually during combat, and restricted to interface 16001.
-- Pausing on living units mitigates the upstream self-cast issue; this is
-- not a guarantee about protected spell targeting during combat.

local ADDON_NAME, ns = ...;

local SOFT = "softinteract";
-- Categories apply only while the separate enhancement option is enabled.
local CATEGORY_OPTIONS = {
	ore = "sparkleOre",
	herb = "sparkleHerbs",
	quest = "sparkleQuest",
	corpseLoot = "sparkleCorpseLoot",
	footlocker = "sparkleFootlocker",
};
local DEFAULTS = {
    sparkleOre = true, sparkleHerbs = true, sparkleQuest = true,
    sparkleCorpseLoot = false, sparkleFootlocker = false,
};

-- Footlockers rogues can pick open, by game object ID (from the GUID). The
-- English name is a fallback for IDs not listed here.
local FOOTLOCKER_IDS = {
	[179486] = true, [179487] = true, [179488] = true, [179490] = true, -- Waterlogged, Battered
	[179496] = true, -- Dented
	[179498] = true, -- Scarlet
	[405633] = true, -- Rockjaw
	[656157] = true, -- Syndicate
};


local POLL_INTERVAL = 0.12; -- re-check of target and state (seconds)
local STATE_DELAY = 0.15;   -- a state must hold this long before it shows (no flicker at the range edge)
local LOCK_DELAY = 0.60;    -- same for "locked", confirmed more carefully

-- Cursor files (Interface\Cursor\*.blp) -> category
local CURSOR_CATEGORY = {
	Mine = "ore",
	GatherHerbs = "herb",
	Quest = "quest", QuestRepeatable = "quest", QuestTurnIn = "quest",
	Interact = "other", PickLock = "other", LootAll = "other", Pickup = "other",
};

-- The client returns a fileID, a path (Interface\Cursor\Mine) or an atlas name
-- (Cursor_Crosshair_UnableMine_64), so keywords are searched in the string.
local CURSOR_KEYWORDS = {
	{ "gather", "herb" },
	{ "mine", "ore" },
	{ "quest", "quest" },
	{ "lootall", "other" },
	{ "pickup", "other" },
	{ "picklock", "other" },
	{ "interact", "other" },
};

local db;
local ready = false;         -- cvars are left alone until Forever Loot Sparkles has restored its own
local gateOpen;             -- is the game's own target nameplate on? nil = apply again
local pendingCVars = false; -- "apply" or "restore" once combat ends
local pendingForce = false; -- the pending "apply" also switches the interact key on
local paused;               -- nil, "unit" or "combat"; declared here because ApplyCVars/RestoreCVars reset it
local directWorks = false;  -- GetNamePlateForUnit("softinteract") has worked for an object
local activeUnits = {};     -- nameplateN token -> plate (or true until available)
local cursorLookup = {};    -- fileID -> { category, greyed out }
local questTexts = {};      -- unfinished objectives, lower case without counters
local questsDirty = true;

local sparkle = {};         -- the one sparkle frame and its animation state


local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value);
end

-- Calls that touch other units can error or return secret values; both count as "unknown"
local function SafeCall(func, ...)
	if not func then
		return nil;
	end
	local ok, result = pcall(func, ...);
	if not ok or IsSecret(result) then
		return nil;
	end
	return result;
end

local function IsActive()
	if not db or not ns.CanEnhance() then
		return false;
	end
	for _, key in pairs(CATEGORY_OPTIONS) do
		if db[key] then
			return true;
		end
	end
	return false;
end

---------------------------------------------------------------------------
-- Cvars
---------------------------------------------------------------------------

local function GetCVarValue(name)
    return ns.GetCVar(name);
end

local function SetCVarValue(name, value)
    return ns.SetManagedCVar(name, value, "soft");
end

local function SetGate(open)
    if open == gateOpen or InCombatLockdown() then return; end
    if SetCVarValue("SoftTargetNameplateInteract", open and 1 or 0) then
        gateOpen = open;
    end
end

local Evaluate;

local function ApplyCVars(force)
    if InCombatLockdown() then
        pendingCVars, pendingForce = "apply", pendingForce or force == true;
        return;
    end
    local first = db.journal.SoftTargetInteract == nil;
    if force or first then
        paused, db.pausedInteract = nil, nil;
        SetCVarValue("SoftTargetInteract", 3);
        SetCVarValue("SoftTargetIconGameObject", 1);
    end
    SetCVarValue("SoftTargetInteractRange", db.range);
    SetCVarValue("SoftTargetInteractArc", db.arc);
    SetCVarValue("SoftTargetInteractOnlyInRange", 0);
    gateOpen = nil;
    Evaluate();
end

local function RestoreCVars()
    if InCombatLockdown() then
        pendingCVars = "restore";
        return;
    end
    paused, db.pausedInteract = nil, nil;
    ns.RestoreCVars("soft");
    gateOpen = nil;
end

---------------------------------------------------------------------------
-- Pausing soft targeting (safe self-cast)
---------------------------------------------------------------------------

-- Spells cast without a target can land on the soft interact target when it
-- is a living unit (a player or NPC next to you). Only objects and corpses
-- need it for the sparkle, so soft targeting is switched off in combat and as
-- soon as it picks a living unit, and back on once you have moved a few yards
-- (or after a few seconds where the game won't give your position). The value
-- it had is kept in db.pausedInteract, so a logout during a pause can't leave
-- it off.
local RESUME_DISTANCE = 5; -- yards
local RESUME_TIME = 3;     -- seconds, without a position
local pausedAt, pausedY, pausedX;

local function PlayerPosition()
	if not UnitPosition then
		return nil;
	end
	local ok, y, x = pcall(UnitPosition, "player");
	if ok and type(y) == "number" and type(x) == "number" and not IsSecret(y) and not IsSecret(x) then
		return y, x;
	end
end

local function Pause(reason)
	if paused then
		if reason == "combat" then
			paused = "combat";
		end
		return;
	end
	if InCombatLockdown() then
		return;
	end
	local current = GetCVarValue("SoftTargetInteract");
	if current == nil or current == "0" then
		return;
	end
	db.pausedInteract = current;
	paused = reason;
	pausedAt = GetTime();
	pausedY, pausedX = PlayerPosition();
	SetCVarValue("SoftTargetInteract", 0);
end

local function Resume()
	if InCombatLockdown() then
		return;
	end
	paused = nil;
	if db.pausedInteract ~= nil then
		if GetCVarValue("SoftTargetInteract") == "0" then
			SetCVarValue("SoftTargetInteract", db.pausedInteract);
		end
		db.pausedInteract = nil;
	end
	gateOpen = nil;
end

local function ReadyToResume()
	local y, x = PlayerPosition();
	if y and pausedY then
		local dy, dx = y - pausedY, x - pausedX;
		return dy * dy + dx * dx >= RESUME_DISTANCE * RESUME_DISTANCE;
	end
	return GetTime() - pausedAt >= RESUME_TIME;
end

local function IsLivingUnit(unit)
	return SafeCall(UnitIsDead, unit) == false and SafeCall(UnitExists, unit) == true;
end

---------------------------------------------------------------------------
-- Classification
---------------------------------------------------------------------------

local probe = UIParent:CreateTexture(nil, "BACKGROUND"); -- hidden, reads the cursor icon
probe:Hide();

if GetFileIDFromPath then
	for name, category in pairs(CURSOR_CATEGORY) do
		for _, prefix in ipairs({ "", "Unable" }) do
			local path = "Interface\\Cursor\\" .. prefix .. name;
			local id = SafeCall(GetFileIDFromPath, path) or SafeCall(GetFileIDFromPath, path .. ".blp");
			if id then
				cursorLookup[id] = { category, prefix ~= "" };
			end
		end
	end
end

local function NormalizeText(text)
	text = text:lower():gsub("\194\160", " "); -- non-breaking space
	text = text:gsub("\226\128\153", "'");     -- typographic apostrophe
	text = text:gsub("%d+%s*/%s*%d+", "");
	text = text:gsub("^[%s:%-]+", ""):gsub("[%s:%-]+$", "");
	return text;
end

local function RebuildQuestTexts()
	questsDirty = false;
	wipe(questTexts);
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then
		return;
	end
	local modern = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestIDForLogIndex;
	for index = 1, SafeCall(modern and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries) or 0 do
		local questID;
		if modern then
			questID = SafeCall(C_QuestLog.GetQuestIDForLogIndex, index);
		elseif GetQuestLogTitle then
			local ok, _, _, _, isHeader, _, _, _, id = pcall(GetQuestLogTitle, index);
			if ok and not isHeader then
				questID = id;
			end
		end
		local objectives = type(questID) == "number" and SafeCall(C_QuestLog.GetQuestObjectives, questID);
		if type(objectives) == "table" then
			for _, objective in ipairs(objectives) do
				local text = objective.text;
				if not objective.finished and type(text) == "string" and not IsSecret(text) then
					text = NormalizeText(text);
					if #text >= 4 then
						questTexts[#questTexts + 1] = text;
					end
				end
			end
		end
	end
end

-- Is the object's name part of an unfinished objective ("Soaked Saw: 0/1"), or
-- the objective part of its name ("Supplies" in "Crate of Supplies")?
local function MatchesObjective(name)
	if type(name) ~= "string" or #name < 4 then
		return false;
	end
	if questsDirty then
		RebuildQuestTexts();
	end
	name = NormalizeText(name);
	for _, text in ipairs(questTexts) do
		if text:find(name, 1, true) or (#text >= 5 and name:find(text, 1, true)) then
			return true;
		end
	end
	return false;
end

local QUEST_LINE_TYPE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective;

local function IsQuestRelated(unit, name)
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
		and SafeCall(C_QuestLog.UnitIsRelatedToActiveQuest, unit) == true then
		return true;
	end
	if QUEST_LINE_TYPE and C_TooltipInfo and C_TooltipInfo.GetUnit then
		local data = SafeCall(C_TooltipInfo.GetUnit, unit);
		if data and data.lines then
			for _, line in ipairs(data.lines) do
				if line.type == QUEST_LINE_TYPE then
					return true;
				end
			end
		end
	end
	return MatchesObjective(name);
end

-- Category and "greyed out" flag (Unable variant: can't interact right now) of a cursor name
local function ReadCursorName(name)
	if type(name) ~= "string" then
		return nil;
	end
	name = name:lower();
	local blocked = name:find("unable", 1, true) ~= nil;
	for _, entry in ipairs(CURSOR_KEYWORDS) do
		if name:find(entry[1], 1, true) then
			return entry[2], blocked;
		end
	end
	return nil, blocked;
end

-- Returns the object's category and whether its cursor is greyed out
local function Classify(unit, name)
	local category, blocked;
	if SafeCall(SetUnitCursorTexture, probe, unit, nil, true) then
		local texture = probe:GetTexture();
		local atlas = probe.GetAtlas and probe:GetAtlas();
		if IsSecret(texture) then
			texture = nil;
		end
		if IsSecret(atlas) then
			atlas = nil;
		end
		local known = type(texture) == "number" and cursorLookup[texture];
		if known then
			category, blocked = known[1], known[2];
		else
			category, blocked = ReadCursorName(texture);
			if not category then
				local fromAtlas, atlasBlocked = ReadCursorName(atlas);
				category, blocked = fromAtlas, blocked or atlasBlocked;
			end
		end
	end
	if category ~= "ore" and category ~= "herb" and IsQuestRelated(unit, name) then
		category = "quest";
	end
	return category, blocked or false;
end

-- Does the corpse still hold loot this character may take? pcall instead of
-- SafeCall: both return values are needed.
local function HasLootLeft(unit)
	local guid = SafeCall(UnitGUID, unit);
	if not (guid and CanLootUnit) then
		return false;
	end
	local ok, hasLoot, canLoot = pcall(CanLootUnit, guid);
	if not ok or IsSecret(hasLoot) or IsSecret(canLoot) then
		return false;
	end
	return hasLoot == true and canLoot ~= false;
end

-- UnitIsCorpse is false for dead mobs (checked in the client), UnitIsDead isn't
local function IsCorpseWithLoot(unit)
	return SafeCall(UnitIsDead, unit) == true and HasLootLeft(unit);
end

-- "ready": can interact; "far": too far; "locked": in range but the game
-- refuses (skill too low, object locked …)
local function ReadState(unit, blocked)
	local inRange = UnitIsInInteractRange and SafeCall(UnitIsInInteractRange, unit);
	if inRange == false then
		return "far";
	end
	if blocked then
		return inRange == true and "locked" or "far";
	end
	return "ready";
end

-- Game object ID from a GUID like "GameObject-0-1-2-3-179488-0000"
local function ObjectID(unit)
	local guid = SafeCall(UnitGUID, unit);
	if type(guid) ~= "string" then
		return nil;
	end
	local kind, _, _, _, _, id = strsplit("-", guid);
	if kind == "GameObject" then
		return tonumber(id);
	end
end

local function IsFootlocker(unit, name)
	local id = ObjectID(unit);
	if id and FOOTLOCKER_IDS[id] then
		return true;
	end
	return type(name) == "string" and not IsSecret(name) and name:lower():find("footlocker", 1, true) ~= nil;
end

---------------------------------------------------------------------------
-- Target
---------------------------------------------------------------------------

local function GetNamePlate(unit)
	return C_NamePlate and SafeCall(C_NamePlate.GetNamePlateForUnit, unit);
end

-- true, false, or nil when the client won't say (secret values). A world
-- object does not "exist" as far as UnitExists is concerned.
local function SoftTargetExists()
	local isUnit, isObject = SafeCall(UnitExists, SOFT), SafeCall(UnitIsGameObject, SOFT);
	if isUnit == true or isObject == true then
		return true;
	end
	if isUnit == false and isObject == false then
		return false;
	end
	return nil;
end

-- Returns the unit token to query, its nameplate (nil if the game doesn't show
-- it, or not yet) and, without a readable target, whether that is for lack of
-- knowing. Until "softinteract" has given the nameplate of a world object on
-- this client, the visible nameplates are searched as well.
local function ResolveTarget()
	local exists = SoftTargetExists();
	if exists == false then
		return nil;
	end
	local plate = GetNamePlate(SOFT);
	if plate then
		if not directWorks and SafeCall(UnitIsGameObject, SOFT) == true then
			directWorks = true;
		end
		return SOFT, plate;
	end
	if not directWorks then
		for unit in pairs(activeUnits) do
			local softGuid = SafeCall(UnitGUID, SOFT);
            local unitGuid = SafeCall(UnitGUID, unit);
            if SafeCall(UnitIsUnit, unit, SOFT) == true
                or (type(softGuid) == "string" and softGuid == unitGuid) then
				plate = GetNamePlate(unit);
				if plate then
					return unit, plate;
				end
			end
		end
	end
	if exists then
		return SOFT, nil;
	end
	return nil, nil, true;
end

---------------------------------------------------------------------------
-- Sparkle
---------------------------------------------------------------------------

-- Rendering is kept separate from target discovery. All effects are 2D UI
-- textures following a nameplate, not a changed world model or shader.
local function Release()
    ns.EffectRelease();
    sparkle.anchor, sparkle.unit, sparkle.retarget = nil, nil, nil;
end

local function Attach(plate, state, category)
    ns.EffectAttach(plate, state, category);
    sparkle.anchor, sparkle.state, sparkle.category = plate, state, category;
    sparkle.pending = nil;
end

local function ProposeState(state)
    if state == sparkle.state then
        sparkle.pending = nil;
    else
        local now = GetTime();
        if sparkle.pending ~= state then
            sparkle.pending, sparkle.pendingSince = state, now;
        elseif now - sparkle.pendingSince >= (state == "locked" and LOCK_DELAY or STATE_DELAY) then
            sparkle.state, sparkle.pending = state, nil;
        end
    end
    ns.EffectState(sparkle.state, sparkle.category);
end

-- Finds the current interaction target, then brings the game's nameplate (on
-- only for objects that get a sparkle) and the sparkle itself in line with it
function Evaluate()
	if InCombatLockdown() then Release(); return; end
	if not ready then
		return;
	end
	if not IsActive() then
		Release();
		return;
	end
	local unit, plate, unknown = ResolveTarget();
	if not unit then
		SetGate(false); -- unknown targets never get a speculative nameplate
		Release();
		return;
	end

	-- world objects sparkle, and of the units only corpses with loot left
	local category, blocked;
	if SafeCall(UnitIsGameObject, unit) == true then
		local name = SafeCall(UnitName, unit);
		category, blocked = Classify(unit, name);
		if IsFootlocker(unit, name) then
			category = "footlocker"; -- "blocked" from the lockpicking cursor: grey when the skill is too low
		end
	elseif db.sparkleCorpseLoot and IsCorpseWithLoot(unit) then
		category, blocked = "corpseLoot", false;
	else
		SetGate(false);
		Release();
		if db.safeSelfCast and IsLivingUnit(unit) then
			Pause("unit");
		end
		return;
	end
	local option = CATEGORY_OPTIONS[category];
	local wanted = option ~= nil and db[option] == true;
	SetGate(wanted);
	if not wanted or not plate then
		-- without a plate it has just been asked for; the sparkle follows when it arrives
		Release();
		return;
	end

	local state = ReadState(unit, blocked);
	if sparkle.anchor ~= plate or sparkle.retarget then
		Release();
		Attach(plate, state, category);
        sparkle.unit = unit;
	else
		sparkle.category = category;
		ProposeState(state);
	end
end

---------------------------------------------------------------------------
-- Events and options
---------------------------------------------------------------------------

local function Refresh(force)
	if IsActive() then
		ApplyCVars(force);
	else
		Release();
		RestoreCVars();
	end
end

local poller = CreateFrame("Frame");
poller:Hide();
local sinceCheck = 0;
poller:SetScript("OnUpdate", function(_, elapsed)
	sinceCheck = sinceCheck + elapsed;
	if sinceCheck >= POLL_INTERVAL then
		sinceCheck = 0;
		if paused == "unit" and ReadyToResume() then
			Resume();
		end
		Evaluate();
	end
end);

local function UpdatePoller()
	poller:SetShown(ready and IsActive());
end

local handlers = {};

-- Forever Loot Sparkles 2.x puts its old soft targeting values back at login
-- and once more 5 seconds later. This module starts after that.
local START_DELAY = 1;
local startTimer = CreateFrame("Frame");
startTimer:Hide();
local startAt;
startTimer:SetScript("OnUpdate", function(self)
	if GetTime() < startAt then
		return;
	end
	if ForeverLootSparklesDB and ForeverLootSparklesDB.savedCVars and GetTime() < startAt + 30 then
		return; -- its restore hasn't run yet (combat): wait for it
	end
	self:Hide();
	ready = true;
	-- Recover a pause left over from a reload or an interrupted session.
	if db.pausedInteract ~= nil and not InCombatLockdown() then
		Resume();
	end
	if IsActive() then
		ApplyCVars();
    else
        RestoreCVars();
	end
	UpdatePoller();
end);

function handlers.PLAYER_LOGIN()
	startAt = GetTime() + (ns.SafeCall(C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded, "ForeverLootSparkles") and 6 or START_DELAY);
	startTimer:Show();
end

-- Account-synced settings can arrive after PLAYER_LOGIN and overwrite ours
function handlers.VARIABLES_LOADED()
	if ready and IsActive() then
		ApplyCVars();
	end
end
handlers.PLAYER_ENTERING_WORLD = handlers.VARIABLES_LOADED;

-- Hide our effect on combat entry. CVar changes are attempted only if the
-- client still permits them; protected combat states defer those changes.
function handlers.PLAYER_REGEN_DISABLED()
	if ready and IsActive() then
		SetGate(false);
		Release();
		if db.safeSelfCast then
			Pause("combat");
		end
	end
end

function handlers.PLAYER_REGEN_ENABLED()
	if pendingCVars == "apply" then
		ApplyCVars(pendingForce);
	elseif pendingCVars == "restore" then
		RestoreCVars();
	end
	pendingCVars, pendingForce = false, false;
	if paused == "combat" then
		Resume();
	end
	Evaluate();
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
	activeUnits[unit] = GetNamePlate(unit) or true;
	Evaluate();
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
    local oldPlate = activeUnits[unit];
    activeUnits[unit] = nil;
    if sparkle.unit == unit or oldPlate == sparkle.anchor then Release(); end
end

function handlers.PLAYER_SOFT_INTERACT_CHANGED(oldTarget, newTarget)
	-- a nameplate recycled from one target to the next doesn't show the change by itself
	if not IsSecret(oldTarget) and not IsSecret(newTarget) and oldTarget and newTarget and oldTarget ~= newTarget then
		sparkle.retarget = sparkle.anchor ~= nil;
	end
	Evaluate();
end

function handlers.QUEST_LOG_UPDATE()
	questsDirty = true;
end

local events = CreateFrame("Frame");
events:SetScript("OnEvent", function(_, event, ...)
	if db then
		handlers[event](...);
	end
end);
for event in pairs(handlers) do
	pcall(events.RegisterEvent, events, event);
end

---------------------------------------------------------------------------
-- /flscolor target: what the addon sees on the current interaction target
---------------------------------------------------------------------------

function ns.DebugTarget()
	local function out(...)
		local parts = {};
		for i = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(i, ...)));
		end
		print("  " .. table.concat(parts, " "));
	end
	print("|cffffd166拾光：|r interaction target");
	out("ready=", ready, "active=", db and IsActive(), "paused=", paused, "gate=", gateOpen);
	out("cvars: Interact=", GetCVarValue("SoftTargetInteract"), "IconGameObject=", GetCVarValue("SoftTargetIconGameObject"),
		"NameplateInteract=", GetCVarValue("SoftTargetNameplateInteract"), "Range=", GetCVarValue("SoftTargetInteractRange"));
	local unit, plate, unknown = ResolveTarget();
	out("unit=", unit, "plate=", plate ~= nil, "unknown=", unknown);
	local u = unit or SOFT;
	local name = SafeCall(UnitName, u);
	local guid = SafeCall(UnitGUID, u);
	out("name=", name, "guid=", guid, "objectID=", ObjectID(u));
	out("gameObject=", SafeCall(UnitIsGameObject, u), "exists=", SafeCall(UnitExists, u), "dead=", SafeCall(UnitIsDead, u));
	local texture, atlas;
	if SafeCall(SetUnitCursorTexture, probe, u, nil, true) then
		texture = probe:GetTexture();
		atlas = probe.GetAtlas and probe:GetAtlas();
	end
	out("cursor texture=", texture, "atlas=", atlas);
	local category, blocked = Classify(u, name);
	out("classified=", category, "blocked=", blocked, "footlocker=", IsFootlocker(u, name),
		"option=", db and db.sparkleFootlocker);
	out("effect active=", sparkle.anchor ~= nil, "category=", sparkle.category);
end

---------------------------------------------------------------------------
-- Interface for Options.lua
---------------------------------------------------------------------------

ns.SPARKLE_DEFAULTS = DEFAULTS;

-- Called at ADDON_LOADED with this addon's saved variables
function ns.SparkleInit(savedVariables)
	db = savedVariables;
	for key, value in pairs(DEFAULTS) do
		if db[key] == nil then
			db[key] = value;
		end
	end
	if db.safeSelfCast == nil then
		db.safeSelfCast = true;
	end
	if db.hidePlate == nil then
		db.hidePlate = true;
	end
	UpdatePoller();
end

-- Public lifecycle used by Core.lua.
function ns.EngineRefresh()
    if not ready then return; end
    Refresh(false);
    UpdatePoller();
end

function ns.EngineStop(shutdown)
    Release();
    RestoreCVars();
    poller:Hide();
    if shutdown then ready = false; startTimer:Hide(); end
end

function ns.HidePlateChanged()
    ns.RefreshEffects();
end

