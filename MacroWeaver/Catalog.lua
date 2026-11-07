local _, M = ...

function M.SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end
local call = M.SafeCall

function M.InCombat()
    return InCombatLockdown and InCombatLockdown()
end

function M.ActionKey(action)
    return (action.pet and "pet:" or "player:") .. action.name
end

function M.Flavor()
    if GetBuildInfo then
        local _, _, _, interface = GetBuildInfo()
        if interface and interface >= 16000 and interface < 20000 then return "forever" end
    end
    return "classic"
end

function M.RankText(rank)
    return (M.rankFormat or "Rank %d"):format(rank)
end

local function rankOf(subtext)
    if type(subtext) ~= "string" then return nil end
    local format, digits = subtext:gsub("%d+", "%%d")
    if digits ~= 1 then return nil end
    if not M.rankFormat and not subtext:find("[%c%[%];|,/%(%)%%]") then M.rankFormat = format end
    return tonumber(subtext:match("%d+"))
end

function M.ScanSpells()
    if M.InCombat() then return nil, "Leave combat to refresh your spellbook." end
    local spells, seen = {}, {}
    local function add(id, name, icon, passive, offspec, helpful, harmful, pet, subtext)
        if not id or not name or passive then return end
        if subtext == "" then subtext = nil end
        local rank = rankOf(subtext or (C_Spell and call(C_Spell.GetSpellSubtext, id)) or call(GetSpellSubtext, id))
        local key = (pet and "pet:" or "player:") .. name
        local existing = seen[key]
        if existing then
            if not offspec then
                existing.available = true; existing.id = id; existing.icon = icon or existing.icon
                existing.helpful, existing.harmful = helpful == true, harmful == true
                if rank and rank > (existing.rank or 0) then existing.rank = rank end
            end
            return
        end
        local entry = {kind = "spell", id = id, name = name, icon = icon, rank = not offspec and rank or nil,
            helpful = helpful == true, harmful = harmful == true, available = not offspec, pet = pet}
        spells[#spells + 1], seen[key] = entry, entry
    end
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local types = Enum and Enum.SpellBookItemType
    if book and bank and types and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo then
        for tab = 1, (call(book.GetNumSpellBookSkillLines) or 0) do
            local line = call(book.GetSpellBookSkillLineInfo, tab)
            if line and not line.isGuild then
                local offspec = line.offSpecID and line.offSpecID ~= 0
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local info = call(book.GetSpellBookItemInfo, slot, bank)
                    if info and info.itemType == types.Spell then
                        add(info.spellID, info.name, info.iconID, info.isPassive, offspec or info.isOffSpec,
                            call(book.IsSpellBookItemHelpful, slot, bank), call(book.IsSpellBookItemHarmful, slot, bank), nil, info.subName)
                    elseif info and types.Flyout and info.itemType == types.Flyout and GetFlyoutInfo and GetFlyoutSlotInfo then
                        local _, _, count, known = GetFlyoutInfo(info.actionID)
                        if known then
                            for index = 1, count do
                                local id, override, learned = GetFlyoutSlotInfo(info.actionID, index)
                                if learned then
                                    id = override or id
                                    local data = C_Spell and call(C_Spell.GetSpellInfo, id)
                                    if data then
                                        add(id, data.name, data.iconID, call(C_Spell.IsSpellPassive, id), offspec,
                                            call(C_Spell.IsSpellHelpful, id), call(C_Spell.IsSpellHarmful, id))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count, _, offspec = GetSpellTabInfo(tab)
            for slot = offset + 1, offset + count do
                local kind, id = GetSpellBookItemInfo(slot, "spell")
                if kind == "SPELL" then
                    local ok, name, subtext = pcall(GetSpellBookItemName, slot, "spell")
                    add(id, ok and name or nil, call(GetSpellBookItemTexture, slot, "spell"),
                        call(IsPassiveSpell, slot, "spell"), offspec and offspec ~= 0,
                        call(IsHelpfulSpell, slot, "spell"), call(IsHarmfulSpell, slot, "spell"), nil, ok and subtext or nil)
                end
            end
        end
    else
        return nil, "This client's spellbook API is unavailable."
    end
    local petBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    local petCount = call(book and book.HasPetSpells) or call(HasPetSpells) or 0
    if type(petCount) ~= "number" then petCount = 0 end
    for slot = 1, petCount do
        if book and book.GetSpellBookItemInfo and petBank and types then
            local info = call(book.GetSpellBookItemInfo, slot, petBank)
            if info and info.itemType == types.Spell then
                add(info.spellID, info.name, info.iconID, info.isPassive, false,
                    call(book.IsSpellBookItemHelpful, slot, petBank), call(book.IsSpellBookItemHarmful, slot, petBank), true, info.subName)
            end
        elseif GetSpellBookItemInfo then
            local kind, id = GetSpellBookItemInfo(slot, "pet")
            -- Legacy pet books mix commands (Attack, Follow) in with castable spells.
            if kind == "PETACTION" and type(id) == "number" then
                id = id % 0x1000000
                if GetSpellInfo and call(GetSpellInfo, id) ~= call(GetSpellBookItemName, slot, "pet") then kind = nil end
            end
            if kind == "SPELL" or kind == "PETACTION" then
                local ok, name, subtext = pcall(GetSpellBookItemName, slot, "pet")
                add(id, ok and name or nil, call(GetSpellBookItemTexture, slot, "pet"),
                    call(IsPassiveSpell, slot, "pet"), false,
                    call(IsHelpfulSpell, slot, "pet"), call(IsHarmfulSpell, slot, "pet"), true, ok and subtext or nil)
            end
        end
    end
    if GetPetActionInfo then
        for slot = 1, (NUM_PET_ACTION_SLOTS or 10) do
            local ok, name, icon, token, _, _, _, id = pcall(GetPetActionInfo, slot)
            if ok and not token and type(id) == "number" then
                add(id, name, icon, call(C_Spell and C_Spell.IsSpellPassive or IsPassiveSpell, id), false,
                    call(C_Spell and C_Spell.IsSpellHelpful or IsHelpfulSpell, id),
                    call(C_Spell and C_Spell.IsSpellHarmful or IsHarmfulSpell, id), true)
            end
        end
    end
    table.sort(spells, function(a, b) return a.name < b.name end)
    return spells
end

function M.ClassCatalog(spells)
    local result, seen = {}, {}
    for _, entry in ipairs(spells or {}) do
        result[#result + 1] = entry; seen[M.ActionKey(entry)] = entry
    end
    local _, class = UnitClass("player")
    local flavor = M.Flavor()
    for _, row in ipairs(M.ClassSpells and M.ClassSpells[class] or {}) do
        if row[flavor] then
            local info, id
            if flavor == "forever" then
                id = row.ids and row.ids[1]
                info = id and C_Spell and call(C_Spell.GetSpellInfo, id)
            end
            local name = info and info.name or (id and call(GetSpellInfo, id)) or row.name
            local entry = {kind = "spell", name = name, id = id, pet = row.pet, available = false, rankCount = row.ranks,
                icon = info and info.iconID or row.icon,
                helpful = call(C_Spell and C_Spell.IsSpellHelpful or IsHelpfulSpell, id or name) == true,
                harmful = call(C_Spell and C_Spell.IsSpellHarmful or IsHarmfulSpell, id or name) == true}
            local key = M.ActionKey(entry)
            if not seen[key] then result[#result + 1] = entry; seen[key] = true
            elseif type(seen[key]) == "table" and row.ranks then seen[key].rankCount = row.ranks end
        end
    end
    return result
end

function M.ScanItems()
    if M.InCombat() then return {} end
    local result, seen = {}, {}
    for _, slot in ipairs({13, 14, 6, 10}) do
        local names = {[13] = "Top trinket", [14] = "Bottom trinket", [6] = "Belt", [10] = "Gloves"}
        result[#result + 1] = {kind = "slot", id = slot, name = names[slot],
            icon = call(GetInventoryItemTexture, "player", slot)}
    end
    local container = C_Container or {}
    local slots = container.GetContainerNumSlots or GetContainerNumSlots
    local itemID = container.GetContainerItemID or GetContainerItemID
    local itemAPI = C_Item or {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (call(slots, bag) or 0) do
            local id = call(itemID, bag, slot)
            if id and not seen[id] then
                local usable = call(itemAPI.GetItemSpell or GetItemSpell, id)
                local name = call(itemAPI.GetItemInfo or GetItemInfo, id)
                if usable and name then
                    seen[id] = true
                    result[#result + 1] = {kind = "item", id = id, name = name,
                        icon = call(itemAPI.GetItemIconByID or GetItemIcon, id)}
                end
            end
        end
    end
    return result
end

local formCache = {}
function M.ClassForms()
    local result, seen, class = {}, {}, nil
    if UnitClass then _, class = UnitClass("player") end
    local flavor = M.Flavor()
    local cacheKey = tostring(class) .. flavor .. tostring(M.ClassSpells) .. tostring(C_Spell)
    if formCache[cacheKey] then return formCache[cacheKey] end
    formCache[cacheKey] = result
    for _, row in ipairs(M.ClassSpells and M.ClassSpells[class] or {}) do
        if row.form and row[flavor] then
            local family = seen[row.form]
            if not family then
                family = {key = row.form, names = {}, ids = {}}
                seen[row.form] = family
                result[#result + 1] = family
            end
            family.names[row.name] = true
            if flavor == "forever" then
                for _, id in ipairs(row.ids or {}) do family.ids[id] = true end
                local name = row.ids and row.ids[1] and C_Spell and call(C_Spell.GetSpellName, row.ids[1])
                if name then family.names[name] = true end
            end
            if row.form == row.name then
                local id = flavor == "forever" and row.ids and row.ids[1]
                family.label = id and C_Spell and call(C_Spell.GetSpellName, id) or row.name
            end
        end
    end
    for _, family in ipairs(result) do family.label = family.label or family.key end
    return result
end

function M.LiveForms()
    local forms = {}
    for index = 1, (call(GetNumShapeshiftForms) or 0) do
        local id, name
        if GetShapeshiftFormInfo then
            local ok, _, _, _, spellID = pcall(GetShapeshiftFormInfo, index)
            id = ok and type(spellID) == "number" and spellID or nil
            name = id and C_Spell and call(C_Spell.GetSpellName, id)
            name = name or (id and call(GetSpellInfo, id))
        end
        forms[#forms + 1] = {index = index, id = id, name = type(name) == "string" and name or nil}
    end
    return forms
end

function M.FormKey(form, families)
    for _, family in ipairs(families or M.ClassForms()) do
        if (form.id and family.ids[form.id]) or (form.name and family.names[form.name]) then return family.key end
    end
    return form.name
end

function M.ActionForm(action)
    if type(action) ~= "table" or action.kind ~= "spell" or action.pet then return nil end
    for _, family in ipairs(M.ClassForms()) do
        if (action.id and family.ids[action.id]) or (action.name and family.names[action.name]) then return family.key end
    end
end

function M.FormIndex(key)
    if type(key) ~= "string" then return nil end
    if key:match("^%d$") then return key end
    local families = M.ClassForms()
    for _, form in ipairs(M.LiveForms()) do
        if form.index <= 9 and M.FormKey(form, families) == key then return tostring(form.index) end
    end
end

function M.RankChoices(action)
    local choices = {{"highest", "Highest known"}}
    if type(action) ~= "table" or action.kind ~= "spell" then return choices end
    local known = type(action.rank) == "number" and action.rank or 0
    local count = math.max(known, type(action.rankCount) == "number" and action.rankCount or 0)
    for rank = 1, math.min(count, 99) do
        local unlearned = rank > known and (known > 0 or action.available == false)
        choices[#choices + 1] = {rank, M.RankText(rank) .. (unlearned and " *" or ""), planned = unlearned or nil}
    end
    return choices
end

function M.FormChoices(all)
    local choices, seen = {{"any", "Any form"}, {"0", "No form / stance"}}, {}
    local families = M.ClassForms()
    for _, form in ipairs(M.LiveForms()) do
        local key = form.name and M.FormKey(form, families) or tostring(form.index)
        if not seen[key] then
            seen[key] = true
            choices[#choices + 1] = {key, form.name or ("Form / stance " .. form.index)}
        end
    end
    if all then
        for _, family in ipairs(families) do
            if not seen[family.key] then
                seen[family.key] = true
                choices[#choices + 1] = {family.key, family.label .. " *", planned = true}
            end
        end
    end
    return choices
end

function M.ScanAuras()
    local result, seen = {}, {}
    if M.InCombat() or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return result end
    for index = 1, 80 do
        local aura = call(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not aura then break end
        if aura.name and aura.spellId and not seen[aura.name] then
            seen[aura.name] = true
            result[#result + 1] = {kind = "aura", id = aura.spellId, name = aura.name, icon = aura.icon}
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end
