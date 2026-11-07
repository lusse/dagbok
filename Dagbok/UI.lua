local ADDON, ns = ...

local KIND_ICONS = {
    start = "Interface\\Icons\\INV_Misc_Book_09",
    level = "Interface\\Icons\\Achievement_Level_10",
    boss = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    memory = "Interface\\Icons\\INV_Misc_Note_01",
    pvp = "Interface\\Icons\\Ability_DualWield",
    pvpdeath = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    death = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    zone = "Interface\\Icons\\INV_Misc_Map_01",
    dungeon = "Interface\\Icons\\INV_Misc_Key_03",
    battleground = "Interface\\Icons\\INV_BannerPVP_01",
    quest = "Interface\\Icons\\INV_Scroll_03",
    rare = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    gold = "Interface\\Icons\\INV_Misc_Coin_01",
    guild = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
    reputation = "Interface\\Icons\\INV_Misc_Ribbon_01",
    profession = "Interface\\Icons\\Trade_BlackSmithing",
    mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
    duel = "Interface\\Icons\\Ability_Warrior_Challange",
    companion = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
}

local FILTERS = {
    { label = "Allt", exclude = { quest = true } },
    { label = "Framsteg", kinds = { level = true, profession = true, reputation = true, gold = true, guild = true, mount = true } },
    { label = "Loot", kinds = { loot = true } },
    { label = "Resan", kinds = { zone = true, dungeon = true, battleground = true, quest = true } },
    { label = "Strid", kinds = { boss = true, rare = true, achievement = true, death = true, duel = true } },
    { label = "PvP", kinds = { pvp = true, pvpdeath = true } },
    { label = "Minnen", kinds = { memory = true, start = true, companion = true } },
}
local activeFilter = FILTERS[1]

local COIN_ICONS = {
    gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

-- Egen variant eftersom GetCoinTextureString inte finns i alla spelversioner
local function FormatMoney(copper)
    copper = math.floor(copper or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    copper = copper % 100
    local parts = {}
    if gold > 0 then tinsert(parts, gold .. COIN_ICONS.gold) end
    if silver > 0 then tinsert(parts, silver .. COIN_ICONS.silver) end
    if copper > 0 or #parts == 0 then tinsert(parts, copper .. COIN_ICONS.copper) end
    return table.concat(parts, " ")
end

local function MostFrequent(counts)
    local bestName, bestCount
    for name, count in pairs(counts) do
        if not bestCount or count > bestCount then
            bestName, bestCount = name, count
        end
    end
    return bestName, bestCount
end

local frame = CreateFrame("Frame", "DagbokFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(600, 650)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()
tinsert(UISpecialFrames, "DagbokFrame") -- stängs med Escape

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", 0, -5)
title:SetText("Dagbok")

local statsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statsText:SetPoint("TOPLEFT", 14, -34)
statsText:SetPoint("TOPRIGHT", -14, -34)
statsText:SetJustifyH("LEFT")
statsText:SetSpacing(3)

local prevButton
for _, filter in ipairs(FILTERS) do
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(78, 22)
    if prevButton then
        button:SetPoint("LEFT", prevButton, "RIGHT", 4, 0)
    else
        button:SetPoint("TOPLEFT", 12, -114)
    end
    button:SetText(filter.label)
    button:SetScript("OnClick", function()
        activeFilter = filter
        ns.RefreshUI()
    end)
    filter.button = button
    prevButton = button
end

local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
scrollBox:SetPoint("TOPLEFT", 12, -142)
scrollBox:SetPoint("BOTTOMRIGHT", -30, 10)

local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 8, 0)
scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 8, 0)

local function ShowTooltip(row)
    local entry = row.entry
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.link then
        GameTooltip:SetHyperlink(entry.link)
    else
        GameTooltip:SetText(entry.text, 1, 1, 1, 1, true)
    end
    if entry.screenshot then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Skärmdump: " .. entry.screenshot, 0.6, 0.8, 1)
    end
    GameTooltip:Show()
end

local function InitRow(row, entry)
    if not row.icon then
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(38, 38)
        row.icon:SetPoint("LEFT", 6, 0)

        row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.meta:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        row.shot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.shot:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)

        row:SetScript("OnEnter", ShowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self)
            if self.entry.link and IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(self.entry.link)
            end
        end)
    end

    row.entry = entry
    row.icon:SetTexture(entry.icon or KIND_ICONS[entry.kind] or KIND_ICONS.memory)
    row.meta:SetText(format("%s  -  Nivå %d  -  %s", date("%Y-%m-%d %H:%M", entry.time), entry.level or 0, entry.zone or ""))
    row.text:SetText(entry.text)
    row.shot:SetText(entry.screenshot and ("Bild: " .. entry.screenshot) or "")
end

local view = CreateScrollBoxListLinearView()
view:SetElementExtent(50)
view:SetElementInitializer("Button", InitRow)
ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

function ns.RefreshUI()
    if not frame:IsShown() or not ns.db then return end
    local db = ns.db
    local stats = db.stats

    local epics = 0
    for quality, count in pairs(stats.byQuality) do
        if quality >= 4 then epics = epics + count end
    end
    local text = format("Föremål lootade: %d     Episka eller bättre: %d     Bossar besegrade: %d\nTotalt försäljningsvärde: %s",
        stats.items, epics, stats.bossKills, FormatMoney(stats.vendorValue))
    if stats.bestLink then
        text = text .. format("\nVärdefullaste fyndet: %s (%s)", stats.bestLink, FormatMoney(stats.bestValue))
    end
    local pvp = db.pvp
    local pvpLine = format("PvP: %d kills, %d dödsfall", pvp.kills, pvp.deaths)
    local victim, victimCount = MostFrequent(pvp.victims)
    if victim then pvpLine = pvpLine .. format("     Favoritoffer: %s (%d)", victim, victimCount) end
    local nemesis, nemesisCount = MostFrequent(pvp.nemeses)
    if nemesis then pvpLine = pvpLine .. format("     Ärkefiende: %s (%d)", nemesis, nemesisCount) end
    text = text .. "\n" .. pvpLine

    local friends = {}
    for name, c in pairs(db.companions) do
        if c.seconds >= 600 then tinsert(friends, { name = name, seconds = c.seconds }) end
    end
    table.sort(friends, function(a, b) return a.seconds > b.seconds end)
    if #friends > 0 then
        local names = {}
        for i = 1, math.min(3, #friends) do
            tinsert(names, format("%s (%.1f h)", friends[i].name, friends[i].seconds / 3600))
        end
        text = text .. "\nFöljeslagare: " .. table.concat(names, ", ")
    end
    statsText:SetText(text)

    for _, filter in ipairs(FILTERS) do
        filter.button:SetEnabled(filter ~= activeFilter)
    end

    local dataProvider = CreateDataProvider()
    for i = #db.entries, 1, -1 do
        local entry = db.entries[i]
        local included = activeFilter.kinds and activeFilter.kinds[entry.kind]
            or not activeFilter.kinds and not (activeFilter.exclude and activeFilter.exclude[entry.kind])
        if included then
            dataProvider:Insert(entry)
        end
    end
    scrollBox:SetDataProvider(dataProvider)
end

frame:SetScript("OnShow", function()
    title:SetText(UnitName("player") .. "s dagbok")
    ns.RefreshUI()
end)

function ns.ToggleUI()
    frame:SetShown(not frame:IsShown())
end

function Dagbok_OnAddonCompartmentClick()
    ns.ToggleUI()
end
