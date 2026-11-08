local ADDON, ns = ...

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

local defaults = {
    levelInterval = 10,  -- skärmdump var N:e nivå (plus maxnivå)
    lootLogQuality = 3,  -- logga föremål från denna kvalitet (3 = blå, 4 = lila, 5 = orange)
    lootShotQuality = 4, -- ta skärmdump från denna kvalitet
    screenshotDelay = 1, -- sekunder innan bilden tas, så effekter hinner synas
    pvpKillInterval = 25, -- skärmdump för första PvP-killen och sedan var N:e
    screenshotMode = "auto", -- "auto" (spelets Screenshot), "extern" (Dagbok-fotografen) eller "manuell"
}

local function InitDB()
    DagbokDB = DagbokDB or {}
    local db = DagbokDB
    db.entries = db.entries or {}
    db.kills = db.kills or {}
    db.settings = db.settings or {}
    db.stats = db.stats or {}
    if db.settings.manualScreenshots ~= nil then
        db.settings.screenshotMode = db.settings.manualScreenshots and "extern" or "auto"
        db.settings.manualScreenshots = nil
    end
    for k, v in pairs(defaults) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    local stats = db.stats
    stats.items = stats.items or 0
    stats.byQuality = stats.byQuality or {}
    stats.vendorValue = stats.vendorValue or 0
    stats.bossKills = stats.bossKills or 0
    stats.quests = stats.quests or 0
    stats.deaths = stats.deaths or 0
    stats.npcKills = stats.npcKills or 0
    stats.duelsWon = stats.duelsWon or 0
    stats.duelsLost = stats.duelsLost or 0
    db.character = db.character or {}
    db.sessions = db.sessions or {}
    db.zones = db.zones or {}
    db.creatures = db.creatures or {}
    db.reputation = db.reputation or {}
    db.skills = db.skills or {}
    db.companions = db.companions or {}
    for _, key in ipairs({ "instances", "bosses", "questZones", "deathCauses", "deathZones", "zoneTime", "levelPlayed",
        "spells", "flights", "crafted", "emotes", "looted", "resurrectors", "factions" }) do
        db[key] = db[key] or {}
    end
    for _, key in ipairs({ "moneyEarned", "moneySpent", "questXP", "questMoney", "xp", "damageDone", "healingDone",
        "overhealing", "damageTaken", "crits", "jumps", "flightCount", "hearths", "repairCost", "resurrected",
        "spiritHealer", "crafts", "played", "critHeals" }) do
        stats[key] = stats[key] or 0
    end
    db.pvp = db.pvp or {}
    local pvp = db.pvp
    pvp.kills = pvp.kills or 0
    pvp.deaths = pvp.deaths or 0
    pvp.victims = pvp.victims or {}
    pvp.nemeses = pvp.nemeses or {}
    ns.db = db
end

-- Midnight (12.0) kan dölja vissa värden under strid/encounters
local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function Print(msg)
    print("|cffffd100Dagbok:|r " .. msg)
end

local function ScreenshotName()
    local fmt = GetCVar("screenshotFormat")
    local ext = (fmt == nil or fmt == "jpeg") and "jpg" or fmt
    return date("WoWScrnShot_%m%d%y_%H%M%S.") .. ext
end

local pendingShot -- inlägg som väntar på en skärmdump
local SHOT_TIMEOUT = 30

local function RequestManualScreenshot(entry)
    pendingShot = { entry = entry, time = GetTime() }
    RaidNotice_AddMessage(RaidWarningFrame, "Dagbok: tryck Print Screen för att spara ögonblicket!", ChatTypeInfo.RAID_WARNING)
end

-- Vissa spelversioner låter inte addons ta skärmdumpar. Då tänds en magenta ruta i
-- övre vänstra hörnet som Dagbok-fotografen (Fotograf\Dagbok-fotograf.ps1) ser.
-- Fotografen tar bilden när rutan släckts, så den syns inte på bilden.
local MARKER_DURATION = 0.4

local marker = CreateFrame("Frame", nil, WorldFrame)
marker:SetFrameStrata("TOOLTIP")
marker:SetSize(6, 6)
marker:SetPoint("TOPLEFT")
marker:Hide()
local markerTexture = marker:CreateTexture(nil, "OVERLAY")
markerTexture:SetAllPoints()
markerTexture:SetColorTexture(1, 0, 1, 1)

local function SignalPhotographer(entry)
    if marker:IsShown() then
        C_Timer.After(1, function() SignalPhotographer(entry) end)
        return
    end
    marker:Show()
    C_Timer.After(MARKER_DURATION, function()
        marker:Hide()
        entry.screenshot = date("Dagbok_%Y-%m-%d_%H-%M-%S.png")
        ns.RefreshUI()
    end)
end

local function TakeScreenshot(entry, delay)
    C_Timer.After(delay or ns.db.settings.screenshotDelay, function()
        local mode = ns.db.settings.screenshotMode
        if mode == "extern" then
            SignalPhotographer(entry)
        elseif mode == "manuell" then
            RequestManualScreenshot(entry)
        else
            pendingShot = { entry = entry, time = GetTime() }
            Screenshot()
        end
    end)
end

local function OnScreenshot()
    if pendingShot and GetTime() - pendingShot.time < SHOT_TIMEOUT then
        pendingShot.entry.screenshot = ScreenshotName()
        ns.RefreshUI()
    end
    pendingShot = nil
end

local function OnActionBlocked(addon, func)
    if addon ~= ADDON then return end
    if func and func:find("Screenshot") then
        ns.db.settings.screenshotMode = "extern"
        Print("spelet låter inte addons ta skärmdumpar. Bilderna tas nu av Dagbok-fotografen, starta den om den inte redan körs.")
        if pendingShot then
            SignalPhotographer(pendingShot.entry)
            pendingShot = nil
        end
    else
        Print("blockerades från " .. tostring(func))
    end
end

-- Sällskap -------------------------------------------------------------

local COMPANION_HOURS = { 1, 5, 10, 25, 50, 100, 250, 500 }
local KNOWN_COMPANION = 1800 -- sekunder tillsammans innan någon nämns vid namn i raider
local groupMembers = {} -- namn -> true för alla vi grupperar med just nu
local lastGroupTick

local function CompanionName(unit)
    local name, realm = UnitName(unit)
    if not name or IsSecret(name) or name == UNKNOWNOBJECT then return nil end
    if realm and realm ~= "" then name = name .. "-" .. realm end
    return name
end

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do tinsert(units, "raid" .. i) end
    else
        for i = 1, GetNumSubgroupMembers() do tinsert(units, "party" .. i) end
    end
    return units
end

-- Lägger tiden sedan förra räkningen på alla i gruppen och firar jämna timmar
local function TallyGroupTime()
    if not ns.db then return end
    local now = time()
    local elapsed = lastGroupTick and math.min(now - lastGroupTick, 300) or 0
    lastGroupTick = now
    if elapsed <= 0 then return end
    for name in pairs(groupMembers) do
        local c = ns.db.companions[name]
        if c then
            local before = c.seconds
            c.seconds = c.seconds + elapsed
            c.last = now
            for _, hours in ipairs(COMPANION_HOURS) do
                if before < hours * 3600 and c.seconds >= hours * 3600 then
                    local text = format("%d %s i sällskap med %s", hours, hours == 1 and "timme" or "timmar", name)
                    ns.AddEntry("companion", text, { companion = name, hours = hours, class = c.class })
                end
            end
        end
    end
    ns.db.lastGroup = { time = now, members = CopyTable(groupMembers) }
end

local function OnGroupChanged()
    if not ns.db then return end
    TallyGroupTime()
    local db = ns.db
    -- Efter /reload eller en kort frånkoppling är det samma grupp, inte en ny
    local previous = db.lastGroup and time() - db.lastGroup.time < 600 and db.lastGroup.members or {}
    local current = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
            local name = CompanionName(unit)
            if name then
                current[name] = true
                local c = db.companions[name]
                if not c then
                    c = { first = time(), seconds = 0, groups = 0, bosses = 0 }
                    db.companions[name] = c
                end
                if not groupMembers[name] and not previous[name] then c.groups = c.groups + 1 end
                c.last = time()
                c.class, c.classFile = UnitClass(unit)
                local level = UnitLevel(unit)
                if level and level > 0 then c.level = level end
            end
        end
    end
    groupMembers = current
    db.lastGroup = { time = time(), members = CopyTable(current) }
end

-- Vilka som var med när något hände; i raider bara de vi känner
local function CurrentCompany()
    local names = {}
    local raid = IsInRaid()
    for name in pairs(groupMembers) do
        local c = ns.db.companions[name]
        if not raid or (c and c.seconds >= KNOWN_COMPANION) then tinsert(names, name) end
    end
    if #names == 0 then return nil end
    table.sort(names, function(a, b) return ns.db.companions[a].seconds > ns.db.companions[b].seconds end)
    while #names > 6 do tremove(names) end
    return names
end

function ns.AddEntry(kind, text, data)
    local entry = data or {}
    local shot, delay = entry.shot, entry.delay
    entry.shot, entry.delay = nil, nil
    entry.kind = kind
    entry.text = text
    entry.time = time()
    entry.level = entry.level or UnitLevel("player")
    entry.zone = GetRealZoneText()
    local subzone = GetSubZoneText()
    if subzone and subzone ~= "" and subzone ~= entry.zone and not IsSecret(subzone) then
        entry.subzone = subzone
    end
    if kind ~= "companion" then
        entry.group = CurrentCompany()
        if IsInRaid() then entry.groupSize = GetNumGroupMembers() end
    end
    tinsert(ns.db.entries, entry)
    if shot then TakeScreenshot(entry, delay) end
    ns.RefreshUI()
end

-- Nivåer ---------------------------------------------------------------

local function OnLevelUp(level)
    ns.db.character.level = level
    ns.db.levelPlayed[level] = ns.db.stats.played
    local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
    local isMax = level == maxLevel
    local milestone = isMax or level % math.max(1, ns.db.settings.levelInterval) == 0
    local text = isMax and format("Nådde maxnivå %d!", level) or format("Nådde nivå %d", level)
    ns.AddEntry("level", text, { level = level, shot = milestone })
end

-- Loot -----------------------------------------------------------------

local function ToPattern(fmt)
    fmt = fmt:gsub("%%%d%$", "%%") -- "%1$s" -> "%s" i vissa språk
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    fmt = fmt:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. fmt .. "$"
end

-- Varianterna med antal först, annars fångar "(.+)" även "x2"
local lootPatterns = {}
for _, global in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
    if _G[global] then tinsert(lootPatterns, ToPattern(_G[global])) end
end

local craftPatterns = {}
for _, global in ipairs({ "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }) do
    if _G[global] then tinsert(craftPatterns, ToPattern(_G[global])) end
end

local function ItemName(link)
    return link:match("%[(.-)%]") or link
end

local function RecordLoot(link, qty)
    local item = Item:CreateFromItemLink(link)
    if item:IsItemEmpty() then return end
    item:ContinueOnItemLoad(function()
        local _, _, quality, _, _, _, _, _, _, icon, sellPrice = GetItemInfo(link)
        quality = quality or 0
        local value = (sellPrice or 0) * qty
        local stats = ns.db.stats
        local name = ItemName(link)
        ns.db.looted[name] = (ns.db.looted[name] or 0) + qty
        stats.items = stats.items + qty
        stats.byQuality[quality] = (stats.byQuality[quality] or 0) + qty
        stats.vendorValue = stats.vendorValue + value
        if value > (stats.bestValue or 0) then
            stats.bestValue = value
            stats.bestLink = link
        end

        local settings = ns.db.settings
        if quality >= settings.lootLogQuality then
            local text = format("Fick %s%s", link, qty > 1 and (" x" .. qty) or "")
            ns.AddEntry("loot", text, { link = link, icon = icon, quality = quality, shot = quality >= settings.lootShotQuality })
        end
    end)
end

local function OnLoot(msg)
    if IsSecret(msg) then return end
    for _, pattern in ipairs(craftPatterns) do
        local link, qty = msg:match(pattern)
        if link then
            local name = ItemName(link)
            qty = tonumber(qty) or 1
            ns.db.stats.crafts = ns.db.stats.crafts + qty
            ns.db.crafted[name] = (ns.db.crafted[name] or 0) + qty
            return
        end
    end
    for _, pattern in ipairs(lootPatterns) do
        local link, qty = msg:match(pattern)
        if link then
            RecordLoot(link, tonumber(qty) or 1)
            return
        end
    end
end

-- Bossar och bedrifter -------------------------------------------------

local function OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    if IsSecret(success) or IsSecret(encounterID) or success ~= 1 then return end
    local db = ns.db
    db.stats.bossKills = db.stats.bossKills + 1
    for name in pairs(groupMembers) do
        local c = db.companions[name]
        if c then c.bosses = c.bosses + 1 end
    end
    if not IsSecret(encounterName) then
        db.bosses[encounterName] = (db.bosses[encounterName] or 0) + 1
    end
    local run = db.run
    if run then
        run.bosses = run.bosses + 1
        local instance = db.instances[run.name]
        if instance then instance.bosses = instance.bosses + 1 end
    end

    -- Logga bara första dödandet per boss och svårighetsgrad, men räkna alla
    local key = encounterID .. ":" .. difficultyID
    local count = (db.kills[key] or 0) + 1
    db.kills[key] = count
    if count > 1 then return end

    local name = IsSecret(encounterName) and "en boss" or encounterName
    local difficulty = GetDifficultyInfo and GetDifficultyInfo(difficultyID)
    local text = format("Besegrade %s för första gången", name)
    if difficulty and difficulty ~= "" then text = text .. " (" .. difficulty .. ")" end
    ns.AddEntry("boss", text, { boss = name, difficulty = difficulty, groupSize = groupSize, shot = true })
end

local function OnAchievement(achievementID, alreadyEarned)
    if alreadyEarned then return end
    local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(achievementID)
    if name then
        ns.AddEntry("achievement", "Bedrift: " .. name, { achievement = name, icon = icon, shot = true })
    end
end

-- PvP ------------------------------------------------------------------

local playerGUID
local recentKill     -- senaste spelaren som dog av vår grupp enligt stridsloggen
local recentAttacker -- senaste som skadade oss (spelare, NPC eller omgivningen)

local function IsPlayerGUID(guid)
    return type(guid) == "string" and guid:find("^Player%-") ~= nil
end

local function RecordPvPKill(name, killingBlow)
    local pvp = ns.db.pvp
    pvp.kills = pvp.kills + 1
    if name then pvp.victims[name] = (pvp.victims[name] or 0) + 1 end
    local text
    if not name then
        text = "Dödade en fientlig spelare"
    elseif killingBlow == false then
        text = format("Var med och dödade %s", name)
    else
        text = format("Dödade %s", name)
    end
    text = text .. format(" (PvP-kill nr %d)", pvp.kills)
    local shot = pvp.kills == 1 or pvp.kills % math.max(1, ns.db.settings.pvpKillInterval) == 0
    ns.AddEntry("pvp", text, { victim = name, killNumber = pvp.kills, killingBlow = killingBlow, shot = shot })
end

-- Namnet tas från stridsloggen om den finns, annars från ett dött fientligt target
local function RecentKillInfo()
    if recentKill and GetTime() - recentKill.time < 2 then
        return recentKill.name, recentKill.mine
    end
    if UnitIsPlayer("target") and UnitIsDead("target") and UnitCanAttack("player", "target") then
        local name = UnitName("target")
        if not IsSecret(name) then return name end
    end
end

local function OnPvPKillsChanged()
    if not GetPVPLifetimeStats then return end
    local honorableKills = GetPVPLifetimeStats()
    local pvp = ns.db.pvp
    local new = honorableKills - (pvp.lastHonorableKills or honorableKills)
    pvp.lastHonorableKills = honorableKills
    -- Stora hopp betyder att räknaren synkades, inte riktiga kills
    if new < 1 or new > 5 then return end
    for _ = 1, new do
        RecordPvPKill(RecentKillInfo())
    end
end

local RARE_CLASSIFICATIONS = { rare = true, rareelite = true, worldboss = true }

local function RecordCreatureKill(guid, name)
    local db = ns.db
    db.stats.npcKills = db.stats.npcKills + 1
    if name and not IsSecret(name) then
        db.creatures[name] = (db.creatures[name] or 0) + 1
    end
    if UnitGUID("target") == guid and RARE_CLASSIFICATIONS[UnitClassification("target")] then
        ns.AddEntry("rare", format("Fällde den sällsynta %s", name or "fienden"), { creature = name, shot = true })
    end
end

local MELEE = "Närstrid"
local RECORD_LABELS = { biggestCrit = "Ny crit-rekord", biggestCritHeal = "Ny rekord-crit-heal" }

-- Sparar rekordet om det slogs; healing räknas utan överhealing
local function RecordBest(key, amount, spell, target)
    local stats = ns.db.stats
    local previous = stats[key]
    if amount <= (previous and previous.amount or 0) then return end
    stats[key] = { amount = amount, spell = spell, target = target, time = time(), level = UnitLevel("player") }
    -- Crit-rekord blir en dagboksrad när det gamla slås med minst 10 %
    local label = RECORD_LABELS[key]
    if label and previous and amount >= previous.amount * 1.1 then
        local text = format("%s: %d med %s%s", label, amount, spell or MELEE, target and (" på " .. target) or "")
        ns.AddEntry("record", text, { record = key, amount = amount, spell = spell, target = target, previous = previous.amount })
    end
end


-- Skada, healing och formler från spelaren själv
local function OnOwnCombatEvent(subevent, destName, ...)
    local db = ns.db
    local stats = db.stats
    if subevent == "SPELL_CAST_SUCCESS" then
        local _, spellName = ...
        if spellName and not IsSecret(spellName) then db.spells[spellName] = (db.spells[spellName] or 0) + 1 end
    elseif subevent == "SWING_DAMAGE" then
        local amount, _, _, _, _, _, critical = ...
        if type(amount) ~= "number" then return end
        stats.damageDone = stats.damageDone + amount
        if critical then
            stats.crits = stats.crits + 1
            RecordBest("biggestCrit", amount, MELEE, destName)
        end
        RecordBest("biggestHit", amount, MELEE, destName)
    elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "RANGE_DAMAGE" then
        local _, spellName, _, amount, _, _, _, _, _, critical = ...
        if type(amount) ~= "number" then return end
        stats.damageDone = stats.damageDone + amount
        if critical then
            stats.crits = stats.crits + 1
            RecordBest("biggestCrit", amount, spellName, destName)
        end
        RecordBest("biggestHit", amount, spellName, destName)
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local _, spellName, _, amount, overhealing, _, critical = ...
        if type(amount) ~= "number" then return end
        local effective = amount - (overhealing or 0)
        stats.healingDone = stats.healingDone + effective
        stats.overhealing = stats.overhealing + (overhealing or 0)
        if critical then
            stats.critHeals = (stats.critHeals or 0) + 1
            RecordBest("biggestCritHeal", effective, spellName, destName)
        end
        RecordBest("biggestHeal", effective, spellName, destName)
    end
end

local function OnCombatLog()
    local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, environmentalType = CombatLogGetCurrentEventInfo()
    if IsSecret(subevent) then return end
    if sourceGUID == playerGUID then
        OnOwnCombatEvent(subevent, destName, select(12, CombatLogGetCurrentEventInfo()))
    end
    if destGUID == playerGUID and subevent:find("_DAMAGE$") then
        local index = subevent == "SWING_DAMAGE" and 12 or subevent == "ENVIRONMENTAL_DAMAGE" and 13 or 15
        local amount = select(index, CombatLogGetCurrentEventInfo())
        if type(amount) == "number" then ns.db.stats.damageTaken = ns.db.stats.damageTaken + amount end
    end
    if subevent == "PARTY_KILL" then
        local mine = sourceGUID == playerGUID
        if IsPlayerGUID(destGUID) then
            recentKill = { name = destName, mine = mine, time = GetTime() }
            -- Utan hedervärda kills-räknare blir dödsstöten själva killen
            if mine and not GetPVPLifetimeStats then RecordPvPKill(destName, true) end
        elseif mine then
            RecordCreatureKill(destGUID, destName)
        end
    elseif destGUID == playerGUID and subevent == "ENVIRONMENTAL_DAMAGE" then
        recentAttacker = { environment = environmentalType, time = GetTime() }
    elseif destGUID == playerGUID and sourceName and subevent:find("_DAMAGE$") then
        recentAttacker = { name = sourceName, isPlayer = IsPlayerGUID(sourceGUID), time = GetTime() }
    end
end

local ENVIRONMENT_DEATHS = {
    Falling = "Föll till sin död",
    Drowning = "Drunknade",
    Fatigue = "Simmade för långt ut och gick under av utmattning",
    Fire = "Brann upp",
    Lava = "Föll i lava",
    Slime = "Gick under i giftigt slem",
}

local function OnPlayerDead()
    local db = ns.db
    local pvp = db.pvp
    local attacker = recentAttacker and GetTime() - recentAttacker.time < 10 and recentAttacker
    recentAttacker = nil
    local _, instanceType = IsInInstance()
    db.stats.deaths = db.stats.deaths + 1
    local zone = GetRealZoneText()
    if zone and zone ~= "" then db.deathZones[zone] = (db.deathZones[zone] or 0) + 1 end
    local cause = attacker and (attacker.name or attacker.environment)
    if cause then db.deathCauses[cause] = (db.deathCauses[cause] or 0) + 1 end

    if attacker and attacker.isPlayer then
        pvp.deaths = pvp.deaths + 1
        pvp.nemeses[attacker.name] = (pvp.nemeses[attacker.name] or 0) + 1
        ns.AddEntry("pvpdeath", format("Dödades av %s", attacker.name), { killer = attacker.name })
    elseif instanceType == "pvp" or instanceType == "arena" then
        pvp.deaths = pvp.deaths + 1
        ns.AddEntry("pvpdeath", "Stupade i strid mot andra spelare")
    elseif attacker and attacker.environment then
        local text = ENVIRONMENT_DEATHS[attacker.environment] or "Omkom i en olycka"
        ns.AddEntry("death", text, { environment = attacker.environment })
    elseif attacker then
        ns.AddEntry("death", format("Föll för %s", attacker.name), { killer = attacker.name })
    else
        ns.AddEntry("death", "Dog")
    end
end

-- Resan: zoner, instanser, uppdrag ------------------------------------

local RUN_MILESTONES = { [10] = true, [25] = true, [50] = true, [100] = true, [250] = true }
local RUN_GAP = 900 -- kommer man tillbaka inom 15 minuter är det samma körning

-- Avslutar körningen och sparar den som snabbast om alla kända bossar föll
local function EndRun()
    local db = ns.db
    local run = db.run
    db.run = nil
    local instance = run and db.instances[run.name]
    if not instance or run.bosses == 0 then return end
    local duration = run.lastSeen - run.start
    local best = instance.maxBosses or 0
    if run.bosses > best or (run.bosses == best and (not instance.fastest or duration < instance.fastest)) then
        instance.maxBosses = run.bosses
        instance.fastest = duration
    end
end

local function UpdateInstanceRun(zone)
    local db = ns.db
    local now = time()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then return end
    local run = db.run
    if run and run.name == zone and now - run.lastSeen < RUN_GAP then
        run.lastSeen = now
        return
    end
    EndRun()
    local instance = db.instances[zone] or { runs = 0, seconds = 0, bosses = 0, first = now, type = instanceType }
    db.instances[zone] = instance
    instance.runs = instance.runs + 1
    instance.last = now
    db.run = { name = zone, start = now, lastSeen = now, bosses = 0 }
    if RUN_MILESTONES[instance.runs] then
        ns.AddEntry("dungeon", format("Gick in i %s för %d:e gången", zone, instance.runs), { runs = instance.runs, instanceType = instanceType })
    end
end

-- Varje minut: speltid, tid per zon och tid i instansen
local lastPlayTick
local function TallyPlayTime()
    if not ns.db then return end
    local now = time()
    local elapsed = lastPlayTick and math.min(now - lastPlayTick, 300) or 0
    lastPlayTick = now
    if elapsed <= 0 then return end
    local db = ns.db
    db.stats.played = db.stats.played + elapsed
    local zone = GetRealZoneText()
    if not zone or zone == "" or IsSecret(zone) then return end
    db.zoneTime[zone] = (db.zoneTime[zone] or 0) + elapsed
    local run = db.run
    if run and run.name == zone and IsInInstance() then
        run.lastSeen = now
        db.instances[zone].seconds = db.instances[zone].seconds + elapsed
    end
end

local function OnZoneChanged()
    local zone = GetRealZoneText()
    if not zone or zone == "" or IsSecret(zone) then return end
    local db = ns.db
    UpdateInstanceRun(zone)
    if db.zones[zone] then return end
    db.zones[zone] = time()

    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        ns.AddEntry("zone", format("Kom till %s för första gången", zone), { shot = true, delay = 4 })
    elseif instanceType == "party" or instanceType == "raid" then
        ns.AddEntry("dungeon", format("Steg in i %s för första gången", zone), { instanceType = instanceType, shot = true, delay = 4 })
    elseif instanceType == "pvp" or instanceType == "arena" then
        ns.AddEntry("battleground", format("Kämpade i %s för första gången", zone), { shot = true, delay = 4 })
    end
end

local lastQuestTitle

local function OnQuestComplete()
    if GetTitleText then lastQuestTitle = GetTitleText() end
end

local function OnQuestTurnedIn(questID, xp, money)
    local stats = ns.db.stats
    stats.quests = stats.quests + 1
    stats.questXP = stats.questXP + (tonumber(xp) or 0)
    stats.questMoney = stats.questMoney + (tonumber(money) or 0)
    local zone = GetRealZoneText()
    if zone and zone ~= "" then ns.db.questZones[zone] = (ns.db.questZones[zone] or 0) + 1 end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID) or lastQuestTitle
    lastQuestTitle = nil
    local text = title and format("Slutförde uppdraget %s", title) or "Slutförde ett uppdrag"
    local milestone = stats.quests % 100 == 0
    if milestone then text = text .. format(" (uppdrag nr %d)", stats.quests) end
    ns.AddEntry("quest", text, { questID = questID, title = title, xp = xp, money = money, shot = milestone })
end

-- Framsteg: guld, guild, rykte, yrken, riddjur --------------------------

local MONEY_MILESTONES = { 10000, 100000, 1000000, 10000000, 100000000 } -- 1, 10, 100, 1 000, 10 000 guld

local lastMoney

local function OnMoney()
    local stats = ns.db.stats
    local money = GetMoney()
    if lastMoney then
        local change = money - lastMoney
        if change > 0 then stats.moneyEarned = stats.moneyEarned + change end
        if change < 0 then stats.moneySpent = stats.moneySpent - change end
    end
    lastMoney = money
    local best = stats.maxMoney or money
    if money <= best then
        stats.maxMoney = best
        return
    end
    for _, milestone in ipairs(MONEY_MILESTONES) do
        if best < milestone and money >= milestone then
            ns.AddEntry("gold", format("Hade för första gången %d guld på fickan", milestone / 10000), { money = money, shot = milestone >= 1000000 })
        end
    end
    stats.maxMoney = money
end

local guildReady = false -- guildinfon laddas en stund efter inloggning

local function OnGuildUpdate()
    if not guildReady then return end
    local guild = ""
    if IsInGuild() then
        guild = GetGuildInfo("player")
        if not guild then return end
    end
    local character = ns.db.character
    local previous = character.guild
    character.guild = guild
    if previous == nil or previous == guild then return end
    if guild ~= "" then
        ns.AddEntry("guild", format("Gick med i guilden <%s>", guild), { guild = guild, shot = true })
    else
        ns.AddEntry("guild", format("Lämnade guilden <%s>", previous), { guild = previous })
    end
end

local function OnReputation()
    if not GetNumFactions or not GetFactionInfo then return end
    local reputation = ns.db.reputation
    for i = 1, GetNumFactions() do
        local name, _, standingID, barMin, barMax, barValue, atWar, _, isHeader, _, hasRep = GetFactionInfo(i)
        if name and standingID and (not isHeader or hasRep) then
            local previous = reputation[name]
            reputation[name] = standingID
            if barMin and barMax and barValue then
                ns.db.factions[name] = { standing = standingID, value = barValue - barMin, max = barMax - barMin, total = barValue, atWar = atWar or nil }
            end
            -- 5 = Friendly, 8 = Exalted
            if previous and standingID > previous and standingID >= 5 then
                local label = _G["FACTION_STANDING_LABEL" .. standingID] or tostring(standingID)
                ns.AddEntry("reputation", format("Blev %s hos %s", label, name), { faction = name, standing = standingID, shot = standingID >= 7 })
            end
        end
    end
end

local function IsProfessionHeader(header)
    if not header then return false end
    for _, global in ipairs({ "TRADE_SKILLS", "SECONDARY_SKILLS" }) do
        local label = _G[global]
        if label and label:gsub(":", "") == header:gsub(":", "") then return true end
    end
    return false
end

local function OnSkillsChanged()
    if not GetNumSkillLines or not GetSkillLineInfo then return end
    local db = ns.db
    local header
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if isHeader then
            header = name
        elseif name and rank and IsProfessionHeader(header) then
            local previous = db.skills[name]
            db.skills[name] = rank
            if previous == nil then
                if db.skillsScanned then
                    ns.AddEntry("profession", format("Lärde sig %s", name), { skill = name, rank = rank })
                end
            elseif math.floor(rank / 75) > math.floor(previous / 75) then
                ns.AddEntry("profession", format("Nådde %d i %s", rank, name), { skill = name, rank = rank, shot = true })
            end
        end
    end
    db.skillsScanned = true
end

local function OnMountChanged()
    local stats = ns.db.stats
    if stats.firstMount or not IsMounted or not IsMounted() then return end
    stats.firstMount = time()
    ns.AddEntry("mount", "Red för första gången på ett eget riddjur", { shot = true, delay = 2 })
end

-- Dueller ---------------------------------------------------------------

local duelPatterns = {}
for _, global in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }) do
    if _G[global] then
        -- RETREAT skriver förloraren först ("%2$s has fled from %1$s")
        tinsert(duelPatterns, { pattern = ToPattern(_G[global]), loserFirst = global == "DUEL_WINNER_RETREAT" })
    end
end

local function OnSystemMessage(msg)
    if IsSecret(msg) then return end
    local me = UnitName("player")
    for _, duel in ipairs(duelPatterns) do
        local first, second = msg:match(duel.pattern)
        if first then
            local winner, loser = first, second
            if duel.loserFirst then winner, loser = second, first end
            local stats = ns.db.stats
            if winner == me then
                stats.duelsWon = stats.duelsWon + 1
                ns.AddEntry("duel", format("Vann en duell mot %s", loser), { opponent = loser, won = true })
            elseif loser == me then
                stats.duelsLost = stats.duelsLost + 1
                ns.AddEntry("duel", format("Förlorade en duell mot %s", winner), { opponent = winner, won = false })
            end
            return
        end
    end
end

-- Småstatistik: XP, resor, reparationer, återupplivning ----------------

local lastXP, lastMaxXP

local function OnXPUpdate(unit)
    if unit and unit ~= "player" then return end
    local xp, maxXP = UnitXP("player"), UnitXPMax("player")
    if lastXP then
        -- Har vi gått upp i nivå räknas resten av förra nivån plus det nya
        local gained = xp >= lastXP and xp - lastXP or (lastMaxXP - lastXP) + xp
        ns.db.stats.xp = ns.db.stats.xp + gained
    end
    lastXP, lastMaxXP = xp, maxXP
end

local HEARTHSTONE = 8690

local function OnSpellcastSucceeded(unit, _, spellID)
    if unit == "player" and spellID == HEARTHSTONE then
        ns.db.stats.hearths = ns.db.stats.hearths + 1
    end
end

local merchantRepairCost

local function OnDurabilityChanged()
    if not merchantRepairCost or not GetRepairAllCost then return end
    local cost = GetRepairAllCost()
    if cost < merchantRepairCost then
        ns.db.stats.repairCost = ns.db.stats.repairCost + (merchantRepairCost - cost)
    end
    merchantRepairCost = cost
end

local function OnMerchantShow()
    merchantRepairCost = GetRepairAllCost and GetRepairAllCost() or nil
end

local function OnMerchantClosed()
    merchantRepairCost = nil
end

local function OnResurrectRequest(name)
    local db = ns.db
    db.stats.resurrected = db.stats.resurrected + 1
    if name and not IsSecret(name) then db.resurrectors[name] = (db.resurrectors[name] or 0) + 1 end
end

local function OnSpiritHealer()
    ns.db.stats.spiritHealer = ns.db.stats.spiritHealer + 1
end

-- Hooks på vanliga spelfunktioner; körs efter originalet och påverkar inget
local function Count(key)
    if ns.db then ns.db.stats[key] = ns.db.stats[key] + 1 end
end

local function SafeHook(name, hook)
    if type(_G[name]) == "function" then hooksecurefunc(name, hook) end
end

SafeHook("JumpOrAscendStart", function() Count("jumps") end)
SafeHook("TakeTaxiNode", function(index)
    if not ns.db then return end
    Count("flightCount")
    local destination = TaxiNodeName and TaxiNodeName(index)
    if destination then ns.db.flights[destination] = (ns.db.flights[destination] or 0) + 1 end
end)
SafeHook("DoEmote", function(token)
    if not ns.db or type(token) ~= "string" then return end
    token = token:upper()
    ns.db.emotes[token] = (ns.db.emotes[token] or 0) + 1
end)

-- Händelser ------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name == ADDON then InitDB() end
end

function handlers.PLAYER_LOGIN()
    local db = ns.db
    playerGUID = UnitGUID("player")
    if GetPVPLifetimeStats then
        db.pvp.lastHonorableKills = GetPVPLifetimeStats()
    end

    local character = db.character
    local className, classFile = UnitClass("player")
    local raceName, raceFile = UnitRace("player")
    character.name = UnitName("player")
    character.realm = GetRealmName()
    character.class, character.classFile = className, classFile
    character.race, character.raceFile = raceName, raceFile
    character.faction = UnitFactionGroup("player")
    character.sex = UnitSex("player")
    character.level = UnitLevel("player")

    tinsert(db.sessions, { start = time(), level = character.level })

    -- Det som fanns innan dagboken räknas inte som nya händelser
    if db.stats.maxMoney == nil then db.stats.maxMoney = GetMoney() end
    local zone = GetRealZoneText()
    if next(db.zones) == nil and zone and zone ~= "" then db.zones[zone] = time() end

    if #db.entries == 0 then
        ns.AddEntry("start", format("Dagboken påbörjades. %s, nivå %d %s.", character.name, character.level, className))
    end

    C_Timer.After(10, function()
        guildReady = true
        OnGuildUpdate()
    end)
    OnGroupChanged()
    C_Timer.NewTicker(60, TallyGroupTime)
    lastMoney = GetMoney()
    lastXP, lastMaxXP = UnitXP("player"), UnitXPMax("player")
    if db.run and time() - db.run.lastSeen >= RUN_GAP then EndRun() end
    TallyPlayTime()
    C_Timer.NewTicker(60, TallyPlayTime)
end

function handlers.PLAYER_LOGOUT()
    local db = ns.db
    TallyGroupTime()
    TallyPlayTime()
    local session = db.sessions[#db.sessions]
    if session then
        session.finish = time()
        session.endLevel = UnitLevel("player")
    end
    db.character.level = UnitLevel("player")
end

handlers.PLAYER_LEVEL_UP = OnLevelUp
handlers.CHAT_MSG_LOOT = OnLoot
handlers.ENCOUNTER_END = OnEncounterEnd
handlers.ACHIEVEMENT_EARNED = OnAchievement
handlers.PLAYER_PVP_KILLS_CHANGED = OnPvPKillsChanged
handlers.PLAYER_DEAD = OnPlayerDead
handlers.SCREENSHOT_SUCCEEDED = OnScreenshot
handlers.ADDON_ACTION_BLOCKED = OnActionBlocked
handlers.ADDON_ACTION_FORBIDDEN = OnActionBlocked
handlers.ZONE_CHANGED_NEW_AREA = OnZoneChanged
handlers.PLAYER_ENTERING_WORLD = OnZoneChanged
handlers.QUEST_COMPLETE = OnQuestComplete
handlers.QUEST_TURNED_IN = OnQuestTurnedIn
handlers.PLAYER_MONEY = OnMoney
handlers.PLAYER_GUILD_UPDATE = OnGuildUpdate
handlers.UPDATE_FACTION = OnReputation
handlers.SKILL_LINES_CHANGED = OnSkillsChanged
handlers.PLAYER_MOUNT_DISPLAY_CHANGED = OnMountChanged
handlers.CHAT_MSG_SYSTEM = OnSystemMessage
handlers.GROUP_ROSTER_UPDATE = OnGroupChanged
handlers.PLAYER_XP_UPDATE = OnXPUpdate
handlers.UNIT_SPELLCAST_SUCCEEDED = OnSpellcastSucceeded
handlers.UPDATE_INVENTORY_DURABILITY = OnDurabilityChanged
handlers.MERCHANT_SHOW = OnMerchantShow
handlers.MERCHANT_CLOSED = OnMerchantClosed
handlers.RESURRECT_REQUEST = OnResurrectRequest
handlers.CONFIRM_XP_LOSS = OnSpiritHealer

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
-- Alla spelversioner har inte alla events (t.ex. bedrifter och stridsloggen)
handlers.COMBAT_LOG_EVENT_UNFILTERED = OnCombatLog
for event in pairs(handlers) do
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
        handlers[event] = nil
    end
end

-- Slash-kommandon ------------------------------------------------------

SLASH_DAGBOK1 = "/dagbok"
SlashCmdList.DAGBOK = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local settings = ns.db.settings
    if cmd == "minne" then
        ns.AddEntry("memory", rest ~= "" and rest or "Ett minnesvärt ögonblick", { note = rest ~= "" and rest or nil, shot = true })
        Print("minne sparat.")
    elseif cmd == "niva" and tonumber(rest) then
        settings.levelInterval = math.max(1, tonumber(rest))
        Print("skärmdump var " .. settings.levelInterval .. ":e nivå.")
    elseif cmd == "kvalitet" and tonumber(rest) then
        settings.lootShotQuality = tonumber(rest)
        Print("skärmdump för loot från kvalitet " .. settings.lootShotQuality .. ".")
    elseif cmd == "pvp" and tonumber(rest) then
        settings.pvpKillInterval = math.max(1, tonumber(rest))
        Print("skärmdump var " .. settings.pvpKillInterval .. ":e PvP-kill.")
    elseif cmd == "bilder" and (rest == "auto" or rest == "extern" or rest == "manuell") then
        settings.screenshotMode = rest
        Print("skärmdumpar: " .. rest .. ".")
    elseif cmd == "hjalp" then
        Print("/dagbok - öppna/stäng dagboken")
        Print("/dagbok minne <text> - spara ett eget minne med skärmdump")
        Print("/dagbok niva <N> - skärmdump var N:e nivå (nu " .. settings.levelInterval .. ")")
        Print("/dagbok kvalitet <N> - skärmdump för loot från kvalitet N, 3=blå 4=lila 5=orange (nu " .. settings.lootShotQuality .. ")")
        Print("/dagbok pvp <N> - skärmdump var N:e PvP-kill (nu " .. settings.pvpKillInterval .. ")")
        Print("/dagbok bilder auto|extern|manuell - vem tar skärmdumparna (nu " .. settings.screenshotMode .. ")")
    else
        ns.ToggleUI()
    end
end
