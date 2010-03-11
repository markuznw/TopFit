
-- utility for rounding
function round(input, places)
    if not places then
        places = 0
    end
    if type(input) == "number" and type(places) == "number" then
        local pow = 1
        for i = 1, ceil(places) do
            pow = pow * 10
        end
        return floor(input * pow + 0.5) / pow
    else
	return input
    end
end

-- for keeping a set's icon intact when it is updated
local function GetTextureIndex(tex) -- blatantly stolen from Tekkubs EquipSetUpdate. Thanks!
    RefreshEquipmentSetIconInfo()
    tex = tex:lower()
    local numicons = GetNumMacroIcons()
    for i=INVSLOT_FIRST_EQUIPPED,INVSLOT_LAST_EQUIPPED do if GetInventoryItemTexture("player", i) then numicons = numicons + 1 end end
    for i=1,numicons do
	local texture, index = GetEquipmentSetIconInfo(i)
	if texture:lower() == tex then return index end
    end
end

-- create Addon object
TopFit = LibStub("AceAddon-3.0"):NewAddon("TopFit", "AceConsole-3.0")

-- debug function
function TopFit:Debug(text)
    if self.db.profile.debugMode then
	TopFit:Print("Debug: "..text)
    end
end

-- debug function
function TopFit:Warning(text)
    --TODO: create table of warnings and dont print any multiples
    --TopFit:Print("|cffff0000Warning: "..text)
end

-- joins any number of tables together, one after the other. elements within the input-tables will get mixed, though
function TopFit:JoinTables(...)
	local result = {}
	local tab
	
	for i=1,select("#", ...) do
		tab = select(i, ...)
		if tab then
			for index, value in pairs(tab) do
				tinsert(result, value)
			end
		end
	end
	
	return result
end

-- find out all we need to know about an item. and maybe even more
function TopFit:GetItemInfoTable(item, location)
    local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(item)
    local itemID = string.gsub(itemLink, ".*|Hitem:([0-9]*):.*", "%1")
    itemID = tonumber(itemID)

    local enchantID = string.gsub(itemLink, ".*|Hitem:[0-9]*:([0-9]*):.*", "%1")
    enchantID = tonumber(enchantID)
    
    -- gems
    local gemBonus = {}
    local gems = {}
    for i = 1,3 do
	local _, gem = GetItemGem(item, i) -- name, itemlink
	if gem then
	    gems[i] = gem
	    
	    local gemID = string.gsub(gem, ".*|Hitem:([0-9]*):.*", "%1")
	    gemID = tonumber(gemID)
	    if (TopFit.gemIDs[gemID]) then
		-- collect stats
		
		for stat, value in pairs(TopFit.gemIDs[gemID].stats) do
		    if (gemBonus[stat]) then
			gemBonus[stat] = gemBonus[stat] + value
		    else
			gemBonus[stat] = value
		    end
		end
	    else
		-- unknown gem, tell the user
		TopFit:Warning("Could not identify gem "..i.." ("..gem..") of your "..itemLink..". Please tell the author so its stats can be added.")
	    end
	end
    end
	
    if #gems > 0 then
	-- REFERENCE: Pawn.lua line ~1000
	--TODO: check killLines
	
	-- try to find socket bonus by scanning item tooltip (though I hoped to avoid that entirely)
	TopFit.scanTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	TopFit.scanTooltip:SetHyperlink(itemLink)
	local numLines = TopFit.scanTooltip:NumLines()
	
	local socketBonusString = _G["ITEM_SOCKET_BONUS"] -- "Socket Bonus: %s" in enUS client, for example
	socketBonusString = string.gsub(socketBonusString, "%%s", "(.*)")
	
	--TopFit:Debug("Socket Bonus String: "..socketBonusString)
	
	local socketBonusIsValid = false
	local socketBonus = nil
	for i = 1, numLines do
	    local leftLine = getglobal("TFScanTooltip".."TextLeft"..i)
	    local leftLineText = leftLine:GetText()
	    
	    if string.find(leftLineText, socketBonusString) then
		-- This line is the socket bonus.
		if leftLine.GetTextColor then
		    socketBonusIsValid = (leftLine:GetTextColor() == 0) -- green's red component is 0, but grey's red component is .5	
		else
		    socketBonusIsValid = true -- we can't get the text color, so we assume the bonus is valid
		end
		
		--TopFit:Debug("Socket Bonus Found! It is "..(socketBonusIsValid and "" or "in").."active. Bonus: "..string.gsub(leftLineText, "^"..socketBonusString.."$", "%1"))
		socketBonus = string.gsub(leftLineText, "^"..socketBonusString.."$", "%1")
	    end
	end
	
	if (socketBonusIsValid) then
	    -- go through our stats to find the bonus
	    for _, sTable in pairs(TopFit.statList) do
		for _, statCode in pairs(sTable) do
		    if (string.find(socketBonus, _G[statCode])) then -- simple short stat codes like "Intellect", "Hit Rating"
			local bonusValue = string.gsub(socketBonus, _G[statCode], "")
			--TopFit:Debug("Value: \""..bonusValue.."\"")
			--TopFit:Debug("ToNumber: "..(tonumber(bonusValue) or "nil"))
			
			bonusValue = (tonumber(bonusValue) or 0)
			
			if (gemBonus[statCode]) then
			    gemBonus[statCode] = gemBonus[statCode] + bonusValue
			else
			    gemBonus[statCode] = bonusValue
			end
		    end
		end
	    end
	end
	
	TopFit.scanTooltip:Hide()
    end
    
    --equippable slots
    locations = {}
    for slotName, slotID in pairs(TopFit.slots) do
	slotAvailableItems = GetInventoryItemsForSlot(slotID)
	if (slotAvailableItems) then
	    for availableLocation, availableItemID in pairs(slotAvailableItems) do
		if (itemID == availableItemID) then
		    --TopFit:Debug(itemLink.." is equippable in Slot "..slotID.." ("..slotName..")")
		    tinsert(locations, slotID)
		    if not location then
			location = availableLocation
		    end
		end
	    end
	end
    end
    
    local enchantBonus = {}
    if enchantID > 0 then
	for _, slotID in pairs(locations) do
	    if (TopFit.enchantIDs[slotID] and TopFit.enchantIDs[slotID][enchantID]) then
		-- TopFit:Debug("Enchant found! ID: "..enchantID)
		enchantBonus = TopFit.enchantIDs[slotID][enchantID]
	    end
	end
    end
    
    local result = {
	["itemLink"] = itemLink,
	["itemID"] = itemID,
	["itemMinLevel"] = itemMinLevel,
	["itemEquipLoc"] = itemEquipLoc,
	["itemBonus"] = GetItemStats(itemLink),
	["gems"] = gems,
	["enchantBonus"] = enchantBonus,
	["gemBonus"] = gemBonus,
	["equipLocations"] = locations,
	["itemLocation"] = location,
	["totalBonus"] = {},
    }
    
    -- dirty little mana regen fix! TODO: better synonim handling
    result["itemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((result["itemBonus"]["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (result["itemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    result["itemBonus"]["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if (result["itemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0) then result["itemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end
    
    result["gemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((result["gemBonus"]["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (result["gemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    result["gemBonus"]["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if (result["gemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0) then result["gemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end
    
    result["enchantBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((result["gemBonus"]["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (result["gemBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    result["enchantBonus"]["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if (result["enchantBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0) then result["enchantBonus"]["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end
    
    -- calculate total values
    for _, bonusTable in pairs({result["itemBonus"], result["gemBonus"], result["enchantBonus"]}) do
	for stat, value in pairs(bonusTable) do
	    result["totalBonus"][stat] = (result["totalBonus"][stat] or 0) + value
	end
    end
    
    return result
end

-- collect items
function TopFit:AddToAvailableItems(item, bag, slot, invSlot, location)
    if item then
	-- check if it's equipment
	if IsEquippableItem(item) then
	    itemTable = TopFit:GetItemInfoTable(item, location)
	    
	    itemTable["bag"] = bag
	    itemTable["slot"] = slot
	    itemTable["invSlot"] = invSlot
	    
	    -- new table with slot ids
	    for _, slotID in pairs(itemTable["equipLocations"]) do
		if not TopFit.itemListBySlot[slotID] then
		    TopFit.itemListBySlot[slotID] = {}
		end
		
		tinsert(TopFit.itemListBySlot[slotID], itemTable)
	    end
	end
    end
end

-- calculate an item's score relative to a given set
function TopFit:CalculateItemTableScore(itemTable, set, caps)
    TopFit.debug = caps
    local bonuses = itemTable["totalBonus"]
    
    -- calculate item score
    itemScore = 0
    -- iterate given weights
    for stat, statValue in pairs(set) do
	if bonuses[stat] then
	    -- check for hard cap on this stat
	    if ((not caps) or (not caps[stat]) or (not caps[stat]["active"]) or (caps[stat]["soft"])) then
		itemScore = itemScore + statValue * bonuses[stat]
	    end
	end
    end
    
    itemTable["itemScore"] = itemScore
end

-- calculate item scores
function TopFit:CalculateScores(set, caps)
    -- iterate all equipment locations
    for slotID, itemsTable in pairs(TopFit.itemListBySlot) do
	-- iterate all items of given location
	for _, itemTable in pairs(itemsTable) do
	    TopFit:CalculateItemTableScore(itemTable, set, caps)
	end
    end
end

function TopFit:EquipRecommendedItems()
    -- equip them
    for slotID, recTable in pairs(TopFit.itemRecommendations) do
	itemTable = recTable["itemTable"]
	
	TopFit:Debug("Recommend "..itemTable["itemLink"].." for Slot "..slotID)
	
	if ((itemTable["bag"]) and (itemTable["slot"])) then
	    PickupContainerItem(itemTable["bag"], itemTable["slot"])
	elseif (itemTable["invSlot"]) then
	    PickupInventoryItem(itemTable["invSlot"])
	end
	EquipCursorItem(slotID)
    end
    
    TopFit.updateEquipmentCounter = 0
    TopFit.updateFrame:SetScript("OnUpdate", TopFit.onUpdateForEquipment)
end

function TopFit:onUpdateForEquipment()
    allDone = true
    for slotID, recTable in pairs(TopFit.itemRecommendations) do
	if (recTable["itemTable"]["itemScore"] > 0) then
	    slotItemID = GetInventoryItemID("player", slotID)
	    if (slotItemID ~= recTable["itemTable"]["itemID"]) then
		allDone = false
	    end
	end
    end
    
    TopFit.updateEquipmentCounter = TopFit.updateEquipmentCounter + 1
    
    -- if all items have been equipped, save equipment set and unregister script
    -- also abort if it takes to long, just save the items that _have_ been equipped
    if ((allDone) or (TopFit.updateEquipmentCounter > 450)) then
	if (not allDone) then
	    TopFit:Print("Oh. I am sorry, but I must have made a mistake. I can not equip all the items I chose:")
	    
	    for slotID, recTable in pairs(TopFit.itemRecommendations) do
		slotItemID = GetInventoryItemID("player", slotID)
		if (slotItemID ~= recTable["itemTable"]["itemID"]) then
		    TopFit:Print("  "..recTable["itemTable"]["itemLink"].." into Slot "..slotID.." ("..TopFit.slotNames[slotID]..")")
		    TopFit.itemRecommendations[slotID] = nil
		end
	    end
	end
	
	TopFit:Debug("All Done!")
	TopFit.updateFrame:SetScript("OnUpdate", nil)
	
	EquipmentManagerClearIgnoredSlotsForSave()
	for _, slotID in pairs(TopFit.slots) do
	    if (not TopFit.itemRecommendations[slotID]) then
		TopFit:Debug("Ignoring slot "..slotID)
		EquipmentManagerIgnoreSlotForSave(slotID)
	    end
	end
	
	-- save equipment set
	if (CanUseEquipmentSets()) then
	    setName = TopFit:GenerateSetName(TopFit.currentSetName)
	    -- check if a set with this name exists
	    if (GetEquipmentSetInfoByName(setName)) then
		texture = GetEquipmentSetInfoByName(setName)
		texture = "Interface\\Icons\\"..texture
		
		textureIndex = GetTextureIndex(texture)
	    else
		textureIndex = GetTextureIndex("Interface\\Icons\\Spell_Holy_EmpowerChampion")
	    end
	    
	    TopFit:Debug("Trying to save set: "..setName..", "..(textureIndex or "nil"))
	    SaveEquipmentSet(setName, textureIndex)
	end
    
	-- we are done with this set
	TopFit.isBlocked = false
	
	TopFit:Print("Here you are, master. All nice and spiffy looking, just as you like it.")
	
	-- initiate next round if necessary
	if (#TopFit.workSetList > 0) then
	    TopFit:CalculateSets()
	end
    end
end

function TopFit:GenerateSetName(name)
    -- using substr because blizzard interface only allows 16 characters
    -- although technically SaveEquipmentSet & co allow more ;)
    return (((name ~= nil) and string.sub(name.." ", 1, 12).."(TF)") or "TopFit")
end

function TopFit:ChatCommand(input)
    if not input or input:trim() == "" then
	InterfaceOptionsFrame_OpenToCategory(TopFit.optionsFrame)
    else
	LibStub("AceConfigCmd-3.0").HandleCommand(TopFit, "tf", "TopFit", input)
    end
end

function TopFit:OnInitialize()
    -- load saved variables
    self.db = LibStub("AceDB-3.0"):New("TopFitDB")
    
    -- create gametooltip for scanning
    TopFit.scanTooltip = CreateFrame('GameTooltip', 'TFScanTooltip', UIParent, 'GameTooltipTemplate')

    -- check if any set is saved already, if not, create default
    if (not self.db.profile.sets) then
	self.db.profile.sets = {
	    set_1 = {
		name = "Default Set",
		weights = {},
		caps = {},
		forced = {},
	    },
	}
    end
    
    -- for savedvariable updates: check if each set has a forced table
    for set, table in pairs(self.db.profile.sets) do
	if table.forced == nil then
	    table.forced = {}
	end
    end
    
    -- list of inventory slot names
    TopFit.slotList = {
	--"AmmoSlot",
	"BackSlot",
	"ChestSlot",
	"FeetSlot",
	"Finger0Slot",
	"Finger1Slot",
	"HandsSlot",
	"HeadSlot",
	"LegsSlot",
	"MainHandSlot",
	"NeckSlot",
	"RangedSlot",
	"SecondaryHandSlot",
	"ShirtSlot",
	"ShoulderSlot",
	"TabardSlot",
	"Trinket0Slot",
	"Trinket1Slot",
	"WaistSlot",
	"WristSlot",
    }
    
    -- create list of slot names with corresponding slot IDs
    TopFit.slots = {}
    TopFit.slotNames = {}
    for _, slotName in pairs(TopFit.slotList) do
	slotID, _, _ = GetInventorySlotInfo(slotName)
	TopFit.slots[slotName] = slotID;
	TopFit.slotNames[slotID] = slotName;
    end
    
    -- create frame for OnUpdate
    TopFit.updateFrame = CreateFrame("Frame")
    
    -- create Ace3 options table
    TopFit:createOptionsTable()

    -- add profile management to options
    TopFit.myOptions.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    
    -- register Slash command
    LibStub("AceConfig-3.0"):RegisterOptionsTable("TopFit", TopFit.GetOptionsTable)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("TopFit", "TopFit")
    self:RegisterChatCommand("topfit", "ChatCommand")
    self:RegisterChatCommand("tf", "ChatCommand")
end

function TopFit:OnEnable()
    -- Called when the addon is enabled
end

function TopFit:OnDisable()
    -- Called when the addon is disabled
end

function TopFit:collectItems()
    -- collect items
    TopFit.itemList = {}
    TopFit.itemListBySlot = {}
    -- check bags
    for bag = 0,4 do
	for slot = 1, GetContainerNumSlots(bag) do
	    local item = GetContainerItemLink(bag,slot)
	    
	    TopFit:AddToAvailableItems(item, bag, slot, nil, nil)
	end
    end
    
    -- check equipped items
    for _, invSlot in pairs(TopFit.slots) do
	local item = GetInventoryItemLink("player", invSlot)
	
	TopFit:AddToAvailableItems(item, nil, nil, invSlot, nil)
    end
end


-- Tooltip functions
local cleared = true
local function OnTooltipCleared(self)
    cleared = true   
end

local function OnTooltipSetItem(self)
    if cleared then
	local name, link = self:GetItem()
	if (name) then
	    local equippable = IsEquippableItem(link)
	    --local item = link:match("Hitem:(%d+)")
	    --	item = tonumber(item)
	    if (not equippable) then
		-- Do nothing
	    else
		-- GameTooltip:AddLine("Item not in an equipment set", 1, 0.2, 0.2)
		local itemTable = TopFit:GetItemInfoTable(link, nil)
		
		if (TopFit.db.profile.debugMode) then
		    -- item stats
		    GameTooltip:AddLine("Item stats as seen by TopFit:", 0.5, 0.9, 1)
		    for stat, value in pairs(itemTable["itemBonus"]) do
			local valueString = ""
			local first = true
			for _, setTable in pairs(TopFit.db.profile.sets) do
			    local weightedValue = (setTable.weights[stat] or 0) * value
			    if first then
				first = false
			    else
				valueString = valueString.." / "
			    end
			    valueString = valueString..(tonumber(weightedValue) or "0")
			end
			GameTooltip:AddDoubleLine("  +"..value.." ".._G[stat], valueString, 0.5, 0.9, 1)
		    end
		    
		    -- enchantment stats
		    if (itemTable["enchantBonus"]) then
			GameTooltip:AddLine("Enchant:", 1, 0.9, 0.5)
			for stat, value in pairs(itemTable["enchantBonus"]) do
			    local valueString = ""
			    local first = true
			    for _, setTable in pairs(TopFit.db.profile.sets) do
				local weightedValue = (setTable.weights[stat] or 0) * value
				if first then
				    first = false
				else
				    valueString = valueString.." / "
				end
				valueString = valueString..(tonumber(weightedValue) or "0")
			    end
			    GameTooltip:AddDoubleLine("  +"..value.." ".._G[stat], valueString, 1, 0.9, 0.5)
			end
		    end
		    
		    -- gems
		    if (itemTable["gemBonus"]) then
			local first = true
			for stat, value in pairs(itemTable["gemBonus"]) do
			    if first then
				first = false
				GameTooltip:AddLine("Gems:", 0.8, 0.2, 0)
			    end
			    
			    local valueString = ""
			    local first = true
			    for _, setTable in pairs(TopFit.db.profile.sets) do
				local weightedValue = (setTable.weights[stat] or 0) * value
				if first then
				    first = false
				else
				    valueString = valueString.." / "
				end
				valueString = valueString..(tonumber(weightedValue) or "0")
			    end
			    GameTooltip:AddDoubleLine("  +"..value.." ".._G[stat], valueString, 0.8, 0.2, 0)
			end
		    end
		end
		
		if (TopFit.db.profile.showTooltip) then
		    -- scores for sets
		    local first = true
		    for _, setTable in pairs(TopFit.db.profile.sets) do
			if first then
			    first = false
			    GameTooltip:AddLine("Set Values:", 0.6, 1, 0.7)
			end
			
			-- TopFit:Debug("Calculating Score for set "..setTable.name)
			TopFit:CalculateItemTableScore(itemTable, setTable.weights, setTable.caps)
			GameTooltip:AddLine("  "..itemTable.itemScore.." - "..setTable.name, 0.6, 1, 0.7)
		    end
		end
	    end
	    cleared = false
	end
    end
end

GameTooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)