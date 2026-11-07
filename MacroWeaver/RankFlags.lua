local _, M = ...
-- A checkbox in WoW's Macros window that raises Spell(Rank N) in a macro after training.

local function escape(text) return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

function M.BumpRanks(body, spells)
    local changed = false
    local formats = {M.rankFormat or "Rank %d"}
    if formats[1] ~= "Rank %d" then formats[2] = "Rank %d" end
    for _, spell in ipairs(spells or {}) do
        if spell.available and type(spell.rank) == "number" and type(spell.name) == "string" and spell.name ~= "" then
            for _, format in ipairs(formats) do
                local before, after = format:match("^(.-)%%d(.*)$")
                local pattern = "([%s%];,!])(" .. escape(spell.name) .. "%(" .. escape(before) .. ")(%d+)(" .. escape(after) .. "%))"
                body = body:gsub(pattern, function(lead, head, rank, close)
                    if tonumber(rank) < spell.rank then
                        changed = true
                        return lead .. head .. spell.rank .. close
                    end
                end)
            end
        end
    end
    return body, changed
end

local function macroFrameOpen()
    return MacroFrame and MacroFrame.IsShown and MacroFrame:IsShown()
end

local warned = {}
function M.UpdateRankFlags(spells)
    local flags = MacroWeaverDB and MacroWeaverDB.rankFlags
    if type(flags) ~= "table" or next(flags) == nil or M.InCombat() or not GetMacroInfo or not EditMacro then return end
    -- The Macros window writes its text back when it closes, so wait until it's closed.
    if macroFrameOpen() then return end
    spells = spells or M.ScanSpells()
    if not spells then return end
    local base = M.Limits()
    local _, count = GetNumMacros()
    local byName = {}
    for index = base + 1, base + count do
        local name, _, body = GetMacroInfo(index)
        if name then
            if byName[name] == nil then byName[name] = {index = index, body = body} else byName[name] = false end
        end
    end
    for name, flagged in pairs(flags) do
        local current = byName[name]
        if type(name) ~= "string" or flagged ~= true then
            flags[name] = nil
        elseif current and type(current.body) == "string" and not (MacroWeaverDB.managed and MacroWeaverDB.managed[name]) then
            local body, changed = M.BumpRanks(current.body, spells)
            if changed and #body > M.MAX_BODY then
                if warned[name] ~= current.body then
                    warned[name] = current.body
                    print("MacroWeaver: " .. name .. " would exceed 255 bytes with its new ranks, so it was left unchanged.")
                end
            elseif changed then
                local ok = pcall(EditMacro, current.index, nil, nil, body)
                local actualName, _, actualBody = GetMacroInfo(current.index)
                if ok and actualName == name and actualBody == body then
                    print("MacroWeaver: raised spell ranks in " .. name .. ".")
                end
            end
        end
    end
end

local holder, box
local function selectedMacro()
    if not MacroFrame then return nil end
    local ok, index = pcall(function()
        if MacroFrame.GetSelectedIndex and MacroFrame.GetMacroDataIndex then
            local selected = MacroFrame:GetSelectedIndex()
            return selected and MacroFrame:GetMacroDataIndex(selected)
        end
        return MacroFrame.selectedMacro
    end)
    return ok and type(index) == "number" and index or nil
end

local function refreshBox()
    if not box or not MacroWeaverDB then return end
    if type(MacroWeaverDB.rankFlags) ~= "table" then MacroWeaverDB.rankFlags = {} end
    local index = selectedMacro()
    local base = M.Limits()
    local name = index and M.SafeCall(GetMacroInfo, index)
    local managed = name and MacroWeaverDB.managed and MacroWeaverDB.managed[name]
    box.macroName = type(name) == "string" and index > base and not managed and name or nil
    box:SetEnabled(box.macroName ~= nil and not M.InCombat())
    box:SetChecked(box.macroName ~= nil and MacroWeaverDB.rankFlags[box.macroName] == true)
    local text = "Keep spell ranks current (MacroWeaver)"
    if managed then text = "Spell ranks: set in /mw for this MacroWeaver macro"
    elseif index and index <= base then text = "Spell ranks: character macros only"
    elseif not name then text = "Select a macro to keep its spell ranks current" end
    box.label:SetText(text)
end
M.RefreshRankFlagBox = refreshBox

local function attach()
    if box or not MacroFrame or not CreateFrame then return end
    holder = CreateFrame("Frame", nil, MacroFrame, "BackdropTemplate")
    holder:SetSize(330, 30); holder:SetPoint("TOPLEFT", MacroFrame, "BOTTOMLEFT", 0, -2)
    if holder.SetBackdrop then
        holder:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        holder:SetBackdropColor(0.045, 0.065, 0.085, 0.95); holder:SetBackdropBorderColor(0.25, 0.52, 0.52, 1)
    end
    box = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
    box:SetSize(24, 24); box:SetPoint("LEFT", 4, 0)
    box.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.label:SetPoint("LEFT", box, "RIGHT", 2, 0); box.label:SetWidth(292); box.label:SetJustifyH("LEFT")
    box:SetScript("OnClick", function(self)
        if not self.macroName or not MacroWeaverDB then refreshBox(); return end
        MacroWeaverDB.rankFlags[self.macroName] = self:GetChecked() and true or nil
    end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("After you train a new rank, each Spell(Rank N) in this macro is raised to the highest rank you know."
            .. " Leave it off to keep a lower rank for downranking. Changes are made when this window closes.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    M.rankFlagBox = box
    if hooksecurefunc then
        if MacroFrame_SelectMacro then hooksecurefunc("MacroFrame_SelectMacro", refreshBox) end
        if MacroFrame.SelectMacro then hooksecurefunc(MacroFrame, "SelectMacro", refreshBox) end
    end
    if MacroFrame.HookScript then
        MacroFrame:HookScript("OnShow", refreshBox)
        MacroFrame:HookScript("OnHide", function()
            if C_Timer and C_Timer.After then C_Timer.After(0.3, function() M.UpdateRankFlags() end)
            else M.UpdateRankFlags() end
        end)
    end
    refreshBox()
end

local events = CreateFrame and CreateFrame("Frame")
if not events then return end
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "UPDATE_MACROS", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_MacroUI" then attach()
    elseif event == "PLAYER_LOGIN" then
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        if MacroFrame or (loaded and M.SafeCall(loaded, "Blizzard_MacroUI")) then attach() end
    elseif box then refreshBox() end
end)
