local addonName, M = ...
local frame, canvas, draft, popup
local catalog, selected, page, rulePage, source = {}, 1, 1, 1, "spell"
local listRows, ruleRows, fields, options = {}, {}, {}, {}
local Refresh, RefreshList, RefreshCatalog, createUI, openSaved

local function label(parent, text, x, y, width, font)
    if parent == frame then parent = canvas end
    local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    s:SetPoint("TOPLEFT", x, y); s:SetWidth(width); s:SetJustifyH("LEFT"); s:SetText(text)
    return s
end
local function button(parent, text, x, y, width, callback)
    if parent == frame then parent = canvas end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 26); b:SetPoint("TOPLEFT", x, y); b:SetText(text); b:SetScript("OnClick", callback)
    return b
end
local function check(parent, text, x, y, callback, width)
    if parent == frame then parent = canvas end
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(24, 24); b:SetPoint("TOPLEFT", x, y)
    label(parent, text, x + 28, y - 5, width or 185, "GameFontHighlightSmall")
    b:SetScript("OnClick", function(self) callback(self:GetChecked() and true or false) end)
    return b
end
local function status(text) if frame then frame.status:SetText(text or "") end end
local function closeMenu() if popup then popup:Hide() end end
local function menu(anchor, choices, callback)
    if popup and popup:IsShown() and popup.anchor == anchor then closeMenu(); return end
    closeMenu()
    if not popup then
        popup = CreateFrame("Frame", "MacroWeaverMenu", canvas, "BackdropTemplate")
        popup:SetFrameStrata("TOOLTIP"); popup:SetClampedToScreen(true); popup:EnableMouse(true)
        popup:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        popup:SetBackdropColor(0.06, 0.09, 0.12, 1); popup:SetBackdropBorderColor(0.3, 0.6, 0.6, 1)
        popup.buttons = {}
        tinsert(UISpecialFrames, "MacroWeaverMenu")
        popup:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
        popup:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN"); self.anchor = nil end)
        popup:SetScript("OnEvent", function(self)
            if not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then self:Hide() end
        end)
        popup:Hide()
    end
    popup.anchor = anchor
    popup:ClearAllPoints(); popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    popup:SetSize(282, #choices * 26 + 8)
    for _, b in ipairs(popup.buttons) do b:Hide() end
    for i, choice in ipairs(choices) do
        local b = popup.buttons[i]
        if not b then b = button(popup, "", 4, -4 - (i - 1) * 26, 274, nil); popup.buttons[i] = b end
        b:SetText(choice[2])
        b:SetScript("OnClick", function() closeMenu(); callback(choice[1]) end)
        b:Show()
    end
    popup:Show()
end
local function choiceName(key, value)
    if value == "auto" and key == "reaction" then return "Match selected spell" end
    local choices = key == "form" and M.FormChoices(true) or M.Choices[key]
    for _, choice in ipairs(choices) do if choice[1] == value then return choice[2] end end
    if key == "form" and type(value) == "string" then
        return value:match("^%d$") and ("Form / stance " .. value) or (value .. " *")
    end
    return value or "Any"
end
local function changed()
    MacroWeaverDB.draft = draft
    status("")
    Refresh()
end
local function newTemplate(template)
    closeMenu()
    draft = M.NewDraft(template)
    selected, page, rulePage, source = 1, 1, 1, "spell"
    MacroWeaverDB.name = ""
    frame.name:SetText("")
    frame.search:SetText("")
    changed()
end
openSaved = function(entry)
    closeMenu()
    local saved = MacroWeaverDB.managed and MacroWeaverDB.managed[entry.name]
    if type(saved) ~= "table" or saved.body ~= entry.body or not M.ValidDraft(saved.draft) then
        status(entry.name .. " was changed outside MacroWeaver, so it can't be opened here.")
        return
    end
    draft = M.Copy(saved.draft)
    draft.target = entry.name
    MacroWeaverDB.draft = draft
    selected, rulePage, source, page = 1, 1, "spell", 1
    MacroWeaverDB.name = entry.name
    frame.name:SetText(entry.name)
    M.NameForms(draft)
    changed()
    status("Editing " .. entry.name .. ". Save changes updates it in place; a new name renames it.")
end
local function chooseRule(index)
    selected = index
    rulePage = math.floor((selected - 1) / #ruleRows) + 1
    closeMenu()
    Refresh()
end

RefreshList = function()
    local entries, query = {}, frame.search:GetText():lower()
    local filter = MacroWeaverDB.spellFilter or "all"
    for _, entry in ipairs(source == "saved" and M.SavedMacros() or catalog) do
        local matches = source == "saved" or source == "spell" and entry.kind == "spell" and (filter == "all" or (filter == "pet") == (entry.pet == true))
            or source == "item" and (entry.kind == "item" or entry.kind == "slot")
            or source == "aura" and entry.kind == "aura"
        if matches and (entry.available ~= false or MacroWeaverDB.allSpells) and entry.name:lower():find(query, 1, true) then
            entries[#entries + 1] = entry
        end
    end
    local pages = math.max(1, math.ceil(#entries / #listRows))
    page = math.max(1, math.min(page, pages))
    frame.page:SetText(#entries .. (source == "saved" and " macros" or " actions") .. "  |  " .. page .. " / " .. pages)
    frame.previous:SetEnabled(page > 1); frame.next:SetEnabled(page < pages)
    local empty = "No matches. Try another search, or refresh after learning a spell or obtaining an item."
    if source == "spell" and filter == "pet" then empty = "No pet abilities. Summon your pet and refresh, or turn on All class spells." end
    if source == "saved" then empty = "No macros made here yet. Macros you save with MacroWeaver are listed here to edit." end
    frame.empty:SetText(#entries == 0 and empty or "")
    frame.spells:SetEnabled(source ~= "spell"); frame.items:SetEnabled(source ~= "item"); frame.auras:SetEnabled(source ~= "aura")
    frame.saved:SetEnabled(source ~= "saved")
    frame.filter:SetText(source == "spell" and ({all = "Show: All", class = "Show: Class", pet = "Show: Pet"})[filter] or "Show: All")
    frame.filter:SetEnabled(source == "spell")
    for i, row in ipairs(listRows) do
        local entry = entries[(page - 1) * #listRows + i]
        row.entry = entry
        if entry then
            row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.text:SetText(entry.name .. (entry.pet and " (pet)" or "") .. (entry.available == false and " *" or ""))
            row:Show()
        else row:Hide() end
    end
end

Refresh = function()
    if not frame then return end
    selected = math.max(1, math.min(selected, #draft.rules))
    local rule = draft.rules[selected]
    frame.template:SetText("Preset: " .. (function()
        for _, entry in ipairs(M.Templates) do if entry[1] == draft.template then return entry[2] end end
        return "Custom"
    end)())
    local count = math.max(1, math.ceil(#draft.rules / #ruleRows))
    rulePage = math.max(1, math.min(rulePage, count))
    frame.rulePage:SetText(rulePage .. " / " .. count)
    frame.rulePrevious:SetEnabled(rulePage > 1); frame.ruleNext:SetEnabled(rulePage < count)
    for i, b in ipairs(ruleRows) do
        local index = (rulePage - 1) * #ruleRows + i
        b.index = index
        local r = draft.rules[index]
        if r then
            local when = M.Conditions(r) or "[choose conditions]"
            if when == "" then when = "Otherwise / normal targeting" end
            if M.FormPending(r) then when = when .. "  |  added once " .. r.form .. " is learned" end
            local spellWith, formWith = M.LinkedWith(draft, index)
            local function rules(list) return (list:find(",", 1, true) and "rules " or "rule ") .. list end
            if spellWith then when = when .. "  |  same spell as " .. rules(spellWith) end
            if formWith then when = when .. "  |  same form as " .. rules(formWith) end
            local action = r.action and (r.action.name .. (type(r.rank) == "number" and " (" .. M.RankText(r.rank) .. ")" or ""))
                or "Choose an action from the left"
            b.text:SetText(index .. ". " .. action .. (r.newLine and "  (new command)" or ""))
            b.detail:SetText(when)
            b.text:SetTextColor(index == selected and 1 or 0.9, index == selected and 0.82 or 0.9, index == selected and 0.2 or 0.9)
            b:Show()
        else b:Hide() end
    end
    for key, b in pairs(fields) do b:SetText(choiceName(key, rule[key])) end
    frame.known:SetChecked(rule.known)
    frame.newLine:SetChecked(rule.newLine)
    frame.cancel:SetChecked(rule.cancel)
    frame.rank:SetText("Rank: " .. (type(rule.rank) == "number" and M.RankText(rule.rank) or "Highest"))
    frame.rank:SetEnabled(#M.RankChoices(rule.action) > 1 and not rule.cancel)
    frame.formNot:SetChecked(rule.formNot)
    frame.formNot:SetEnabled(rule.form ~= nil and rule.form ~= "any")
    frame.noToggle:SetChecked(rule.noToggle)
    frame.noToggle:SetEnabled(rule.action ~= nil and rule.action.kind == "spell" and not rule.cancel)
    frame.unlink:SetText(rule.link and "Give this rule its own spell" or "Give this rule its own form")
    if rule.link or rule.formFollow then frame.unlink:Show() else frame.unlink:Hide() end
    frame.autoUpdate:SetChecked(draft.autoUpdate ~= false)
    frame.editor:SetText("Rule " .. selected .. "  |  " .. (rule.action and rule.action.name or "Pick a spell or item"))
    for key, b in pairs(options) do b:SetChecked(draft[key]) end
    frame.up:SetEnabled(selected > 1)
    frame.down:SetEnabled(selected < #draft.rules)
    frame.remove:SetEnabled(#draft.rules > 1)
    frame.add:SetEnabled(#draft.rules < M.MAX_RULES)
    frame.duplicate:SetEnabled(#draft.rules < M.MAX_RULES)
    local body, problem, bytes = M.SaveBody(draft, catalog)
    frame.preview:SetText(body or problem)
    frame.length:SetText((body and #body or bytes or 0) .. " / 255 bytes")
    local combat = M.InCombat()
    frame.save:SetEnabled(body ~= nil and not combat)
    frame.drag:SetEnabled(body ~= nil and not combat)
    frame.refresh:SetEnabled(not combat)
    local action = draft.rules[1] and draft.rules[1].action
    frame.drag.icon:SetTexture(action and action.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local typed, target = frame.name:GetText(), draft.target
    if target then
        frame.autoName:SetText((typed == "" or typed == target) and ("Updates " .. target) or ("Renames " .. target))
    else
        frame.autoName:SetText(typed == "" and ("Auto: " .. M.AutoName(draft, body)) or "Custom macro name")
    end
    frame.save:SetText(target and "Save changes" or "Save macro")
    frame.combat:SetText(combat and "Combat: save and drag are locked."
        or (target and ("Editing " .. target .. ". New macro starts a new one.") or "Saved as a character macro"))
    RefreshList()
end

RefreshCatalog = function()
    if M.InCombat() then Refresh(); return end
    local spells, problem = M.ScanSpells()
    if not spells then status(problem); Refresh(); return end
    catalog = M.ClassCatalog(spells)
    local byName = {}
    for _, entry in ipairs(catalog) do byName[M.ActionKey(entry)] = entry end
    MacroWeaverDB.spells = MacroWeaverDB.spells or {}
    for _, old in pairs(MacroWeaverDB.spells) do
        local key = type(old) == "table" and type(old.name) == "string" and M.ActionKey(old)
        if key and not byName[key] then
            local entry = M.Copy(old); entry.available = false
            catalog[#catalog + 1] = entry; byName[key] = entry
        end
    end
    for _, entry in ipairs(spells) do MacroWeaverDB.spells[M.ActionKey(entry)] = M.Copy(entry) end
    table.sort(catalog, function(a, b) return a.name < b.name end)
    for _, entry in ipairs(M.ScanItems()) do catalog[#catalog + 1] = entry end
    for _, entry in ipairs(M.ScanAuras()) do catalog[#catalog + 1] = entry end
    for _, rule in ipairs(draft.rules) do
        if rule.action and rule.action.kind == "spell" then
            local fresh = byName[M.ActionKey(rule.action)]
            if fresh then rule.action = M.Copy(fresh) end
        end
    end
    M.NameForms(draft)
    Refresh()
end

createUI = function()
    frame = CreateFrame("Frame", "MacroWeaverFrame", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER")
    canvas = CreateFrame("Frame", nil, frame)
    canvas:SetSize(1000, 800); canvas:SetPoint("TOPLEFT")
    frame.canvas = canvas
    local scale, fitting = 1, false
    local function fit(wanted)
        local largest = math.min((UIParent:GetWidth() - 32) / 1000, (UIParent:GetHeight() - 32) / 800)
        if type(wanted) ~= "number" or wanted ~= wanted then wanted = 1 end
        scale = math.max(math.min(0.65, largest), math.min(wanted, largest))
        canvas:SetScale(scale)
        MacroWeaverDB.width, MacroWeaverDB.height = 1000 * scale, 800 * scale
        if not fitting then fitting = true; frame:SetSize(1000 * scale, 800 * scale); fitting = false end
        closeMenu()
    end
    frame.Fit = function() fit(scale) end
    frame:SetScript("OnSizeChanged", function(self)
        if not fitting then fit(math.min(self:GetWidth() / 1000, self:GetHeight() / 800)) end
    end)
    fit(math.min((tonumber(MacroWeaverDB.width) or 1000) / 1000, (tonumber(MacroWeaverDB.height) or 800) / 800))
    frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function() closeMenu() end)
    frame:SetScript("OnDragStart", function(self) closeMenu(); self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetScript("OnHide", function(self) self:StopMovingOrSizing(); if self.resize then self.resize:SetScript("OnUpdate", nil) end; closeMenu() end)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    frame:SetBackdropColor(0.045, 0.065, 0.085, 0.98); frame:SetBackdropBorderColor(0.25, 0.52, 0.52, 1)
    tinsert(UISpecialFrames, "MacroWeaverFrame")
    label(frame, "MacroWeaver", 22, -18, 700, "GameFontNormalLarge")
    label(frame, (UnitName("player") or "Player") .. " / " .. (UnitClass("player") or "Character") .. "  |  Pick actions. Set conditions. Drag to your bar.", 22, -44, 890)
    button(frame, "X", 951, -14, 28, function() frame:Hide() end)
    frame.template = button(frame, "", 22, -76, 440, function(self) menu(self, M.Templates, newTemplate) end)
    button(frame, "New macro", 474, -76, 130, function() newTemplate("blank") end)
    button(frame, "Tooltip", 616, -76, 120, function(self)
        local choices = {{"auto", "Automatic tooltip"}}
        for index, rule in ipairs(draft.rules) do
            if rule.action then choices[#choices + 1] = {index, rule.action.name} end
        end
        menu(self, choices, function(value)
            local rule = draft.rules[value]
            if value == "auto" or not (rule and rule.action) then draft.tooltip = nil else draft.tooltip = M.Copy(rule.action) end
            changed()
        end)
    end)
    frame.login = check(frame, "Open on login", 756, -76, function(v) MacroWeaverDB.openOnLogin = v end)
    frame.login:SetChecked(MacroWeaverDB.openOnLogin)
    label(frame, "1. Your actions", 22, -122, 265, "GameFontNormal")
    frame.spells = button(frame, "Spells", 22, -148, 63, function() source, page = "spell", 1; RefreshList() end)
    frame.items = button(frame, "Items", 89, -148, 63, function() source, page = "item", 1; RefreshList() end)
    frame.auras = button(frame, "Buffs", 156, -148, 63, function() source, page = "aura", 1; RefreshList() end)
    frame.saved = button(frame, "Saved", 223, -148, 64, function() source, page = "saved", 1; RefreshList() end)
    frame.search = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    frame.search:SetSize(253, 24); frame.search:SetPoint("TOPLEFT", 28, -184); frame.search:SetAutoFocus(false)
    frame.search:SetScript("OnTextChanged", function() page = 1; if #listRows > 0 then RefreshList() end end)
    frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    label(frame, "Search (optional)", 28, -211, 150, "GameFontDisableSmall")
    frame.filter = button(frame, "Show: All", 182, -207, 105, function()
        MacroWeaverDB.spellFilter = ({class = "pet"})[MacroWeaverDB.spellFilter] or (MacroWeaverDB.spellFilter == nil and "class" or nil)
        page = 1; RefreshList()
    end)
    for i = 1, 10 do
        local row = CreateFrame("Button", nil, canvas)
        row:SetSize(265, 32); row:SetPoint("TOPLEFT", 22, -235 - (i - 1) * 34)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(26, 26); row.icon:SetPoint("LEFT", 0, 0)
        row.text = label(row, "", 34, -8, 229)
        row:SetScript("OnClick", function(self)
            if self.entry.kind == "saved" then openSaved(self.entry); return end
            M.SetAction(draft, selected, self.entry); changed()
        end)
        row:SetScript("OnEnter", function(self)
            local entry = self.entry
            if not entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if entry.kind == "saved" then GameTooltip:SetText(entry.name .. "\n" .. entry.body, 1, 1, 1, 1, true)
            elseif entry.id and (entry.kind == "spell" or entry.kind == "aura") and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(entry.id)
            elseif entry.kind == "item" and GameTooltip.SetItemByID then GameTooltip:SetItemByID(entry.id)
            else GameTooltip:SetText(entry.name) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        listRows[i] = row
    end
    frame.empty = label(frame, "", 22, -242, 260)
    frame.previous = button(frame, "<", 22, -584, 32, function() page = page - 1; RefreshList() end)
    frame.next = button(frame, ">", 255, -584, 32, function() page = page + 1; RefreshList() end)
    frame.page = label(frame, "", 61, -591, 190, "GameFontHighlightSmall")
    frame.otherSpecs = check(frame, "All class spells (any level) *", 22, -621, function(v)
        MacroWeaverDB.allSpells = v; page = 1; RefreshList()
    end)
    frame.otherSpecs:SetChecked(MacroWeaverDB.allSpells)
    frame.refresh = button(frame, "Refresh actions", 22, -657, 265, RefreshCatalog)
    frame.autoUpdate = check(frame, "Auto-update saved macro", 22, -691, function(v) draft.autoUpdate = v; changed() end)
    frame.autoUpdate:SetChecked(draft.autoUpdate ~= false)
    label(frame, "* Not currently learned / available.\nPet abilities depend on your active pet.\nDrag the bottom-right corner to resize.", 22, -723, 265, "GameFontHighlightSmall")
    frame.combat = label(frame, "", 22, -775, 280, "GameFontDisableSmall")

    label(frame, "2. Rules in priority order", 310, -122, 530, "GameFontNormal")
    frame.rulePrevious = button(frame, "<", 839, -116, 30, function() rulePage = rulePage - 1; Refresh() end)
    frame.ruleNext = button(frame, ">", 946, -116, 30, function() rulePage = rulePage + 1; Refresh() end)
    frame.rulePage = label(frame, "", 885, -123, 55, "GameFontHighlightSmall")
    for i = 1, 5 do
        local row = CreateFrame("Button", nil, canvas)
        row:SetSize(666, 34); row:SetPoint("TOPLEFT", 310, -151 - (i - 1) * 36)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.text = label(row, "", 4, -2, 650)
        row.detail = label(row, "", 20, -19, 634, "GameFontDisableSmall")
        row:SetScript("OnClick", function(self) chooseRule(self.index) end)
        ruleRows[i] = row
    end
    frame.add = button(frame, "Add rule", 310, -339, 112, function()
        if #draft.rules >= M.MAX_RULES then return end
        M.MakeCustom(draft)
        table.insert(draft.rules, selected + 1, M.Rule())
        chooseRule(selected + 1); changed()
    end)
    frame.duplicate = button(frame, "Duplicate", 428, -339, 112, function()
        if #draft.rules >= M.MAX_RULES then return end
        M.MakeCustom(draft)
        table.insert(draft.rules, selected, M.Copy(draft.rules[selected])); chooseRule(selected); changed()
    end)
    frame.up = button(frame, "Move up", 546, -339, 112, function()
        if selected > 1 then draft.rules[selected], draft.rules[selected - 1] = draft.rules[selected - 1], draft.rules[selected]; chooseRule(selected - 1); changed() end
    end)
    frame.down = button(frame, "Move down", 664, -339, 112, function()
        if selected < #draft.rules then draft.rules[selected], draft.rules[selected + 1] = draft.rules[selected + 1], draft.rules[selected]; chooseRule(selected + 1); changed() end
    end)
    frame.remove = button(frame, "Remove", 782, -339, 112, function()
        if #draft.rules > 1 then M.MakeCustom(draft); table.remove(draft.rules, selected); chooseRule(math.min(selected, #draft.rules)); changed() end
    end)
    frame.editor = label(frame, "", 310, -383, 520, "GameFontNormal")
    frame.rank = button(frame, "", 836, -377, 140, function(self)
        local rule = draft.rules[selected]
        menu(self, M.RankChoices(rule.action), function(value)
            local rank = value ~= "highest" and value or nil
            for _, r in ipairs(draft.rules) do
                if r == rule or (rule.link and r.link == rule.link) then r.rank = rank end
            end
            changed()
        end)
    end)
    local specs = {{"unit", "Target", 310, -411}, {"reaction", "Unit type", 536, -411}, {"modifier", "Modifier", 762, -411},
        {"life", "Life", 310, -464}, {"form", "Form / stance", 536, -464}, {"state", "State", 762, -464}}
    for _, spec in ipairs(specs) do
        local key = spec[1]
        label(frame, spec[2], spec[3], spec[4], 210, "GameFontDisableSmall")
        fields[key] = button(frame, "", spec[3], spec[4] - 17, 214, function(self)
            local choices = key == "form" and M.FormChoices(MacroWeaverDB.allSpells) or M.Copy(M.Choices[key])
            if key == "reaction" then table.insert(choices, 1, {"auto", "Match selected spell"}) end
            menu(self, choices, function(value) draft.rules[selected][key] = value; changed() end)
        end)
    end
    frame.fields = fields
    frame.known = check(frame, "Only if spell known", 310, -519, function(v)
        draft.rules[selected].known, draft.rules[selected].autoKnown = v, nil; changed()
    end)
    frame.newLine = check(frame, "New command line", 536, -519, function(v) draft.rules[selected].newLine = v; changed() end)
    frame.cancel = check(frame, "Cancel this spell's aura", 762, -519, function(v) draft.rules[selected].cancel = v; changed() end)
    frame.unlink = button(frame, "Give this rule its own spell", 310, -546, 214, function()
        M.Unlink(draft, selected); changed()
    end)
    frame.unlink:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("This preset fills some rules from one pick. Detach this rule so it keeps its own spell.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.unlink:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.newLine:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Each command tries its first matching rule. New lines try extra actions.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.newLine:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.formNot = check(frame, "Not in this form / stance", 536, -547, function(v) draft.rules[selected].formNot = v or nil; changed() end)
    frame.noToggle = check(frame, "Don't toggle off (!)", 762, -547, function(v) draft.rules[selected].noToggle = v or nil; changed() end)
    local extras = {{"stopcasting", "Stop casting", 310, -579}, {"stopattack", "Stop attack", 476, -579},
        {"cancelform", "Leave form / stance", 642, -579}, {"startattack", "Start attack", 808, -579},
        {"petattack", "Pet attack", 310, -606}, {"trinket1", "Use top trinket", 476, -606}, {"trinket2", "Use bottom trinket", 642, -606}}
    for _, extra in ipairs(extras) do
        local key = extra[1]
        options[key] = check(frame, extra[2], extra[3], extra[4], function(v) draft[key] = v; changed() end, 136)
    end
    frame.options = options
    frame.length = label(frame, "", 808, -612, 168, "GameFontDisableSmall")
    frame.preview = label(frame, "", 310, -642, 666, "GameFontHighlightSmall")
    frame.preview:SetHeight(80); frame.preview:SetJustifyV("TOP")
    frame.previewArea = CreateFrame("Frame", nil, canvas)
    frame.previewArea:SetSize(666, 80); frame.previewArea:SetPoint("TOPLEFT", 310, -642); frame.previewArea:EnableMouse(true)
    frame.previewArea:SetScript("OnEnter", function(self)
        local body, problem = M.SaveBody(draft, catalog)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(body or problem, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.previewArea:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.name = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    frame.name:SetSize(198, 24); frame.name:SetPoint("TOPLEFT", 316, -737); frame.name:SetAutoFocus(false)
    frame.name:SetMaxLetters(16); frame.name:SetText(MacroWeaverDB.name or "")
    frame.name:SetScript("OnTextChanged", function(self) MacroWeaverDB.name = self:GetText(); if frame.autoName then Refresh() end end)
    frame.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.autoName = label(frame, "", 316, -769, 220, "GameFontDisableSmall")
    frame.save = button(frame, "Save macro", 536, -735, 130, function()
        local index, problem, name, updated = M.Save(draft, frame.name:GetText())
        local editing = draft.target ~= nil
        status(index and ((editing and "Saved changes to " or (updated and "Updated existing macro " or "Saved ")) .. name
            .. (editing and "." or ". Drag its icon onto your bar.")) or problem)
        if index and editing then MacroWeaverDB.name = name end
        frame.name:ClearFocus(); Refresh()
    end)
    frame.drag = CreateFrame("Button", nil, canvas)
    frame.drag:SetSize(42, 42); frame.drag:SetPoint("TOPLEFT", 684, -732)
    frame.drag.icon = frame.drag:CreateTexture(nil, "ARTWORK"); frame.drag.icon:SetAllPoints()
    frame.drag:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    frame.drag:RegisterForDrag("LeftButton")
    local function pickup()
        local index, problem, name, updated = M.Pickup(draft, frame.name:GetText())
        status(index and ((updated and ("Updated existing macro " .. name .. "; it") or name)
            .. " is on your cursor. Drop it onto an action bar.") or problem)
        Refresh()
    end
    frame.drag:SetScript("OnDragStart", pickup); frame.drag:SetScript("OnClick", pickup)
    frame.status = label(frame, "Drag the icon to save and place the macro.", 740, -735, 236, "GameFontHighlightSmall")
    frame.status:SetHeight(57); frame.status:SetJustifyV("TOP")
    frame.resize = CreateFrame("Button", nil, frame)
    frame.resize:SetSize(22, 22); frame.resize:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local function stopSizing() frame.resize:SetScript("OnUpdate", nil) end
    frame.resize:SetScript("OnMouseDown", function(grip, key)
        if key ~= "LeftButton" then return end
        closeMenu()
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
        local ui, startScale = UIParent:GetEffectiveScale(), scale
        local startX, startY = GetCursorPosition()
        grip:SetScript("OnUpdate", function()
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then stopSizing(); return end
            local x, y = GetCursorPosition()
            local across, down = startScale + (x - startX) / ui / 1000, startScale + (startY - y) / ui / 800
            fit(math.abs(across - startScale) >= math.abs(down - startScale) and across or down)
        end)
    end)
    frame.resize:SetScript("OnMouseUp", stopSizing)
    frame:SetScript("OnShow", RefreshCatalog)
    RefreshCatalog()
end

local function toggle()
    if not draft then return end
    if not frame then
        if M.InCombat() then print("MacroWeaver: open the builder outside combat."); return end
        createUI()
    elseif frame:IsShown() then frame:Hide()
    else frame:Show() end
end
local events = CreateFrame("Frame")
local pending, updateNeeded, formSignature
local spellEvents = {PLAYER_LOGIN = true, SPELLS_CHANGED = true, LEARNED_SPELL_IN_TAB = true,
    LEARNED_SPELL_IN_SKILL_LINE = true, TRAINER_UPDATE = true, UNIT_PET = true, PET_BAR_UPDATE = true,
    PLAYER_REGEN_ENABLED = true, PLAYER_ENTERING_WORLD = true, PLAYER_TALENT_UPDATE = true, UPDATE_SHAPESHIFT_FORMS = true,
    UPDATE_MACROS = true}
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
    "LEARNED_SPELL_IN_SKILL_LINE", "TRAINER_UPDATE", "UNIT_PET", "PET_BAR_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE",
    "UPDATE_SHAPESHIFT_FORMS", "UPDATE_MACROS",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "UNIT_AURA",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED"}) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        if type(MacroWeaverDB) ~= "table" then MacroWeaverDB = {} end
        if MacroWeaverDB.version ~= 2 then
            MacroWeaverDB.draft = M.Migrate(MacroWeaverDB.draft)
            MacroWeaverDB.name, MacroWeaverDB.version = "", 2
        end
        if not M.ValidDraft(MacroWeaverDB.draft) then MacroWeaverDB.draft = M.NewDraft("blank") end
        local untouched = MacroWeaverDB.draft.template == "mouseover"
        for _, rule in ipairs(MacroWeaverDB.draft.rules) do if rule.action then untouched = false end end
        if untouched then MacroWeaverDB.draft = M.NewDraft("blank") end
        M.RepairDraft(MacroWeaverDB.draft)
        for _, rule in ipairs(MacroWeaverDB.draft.rules) do
            if rule.autoKnown then rule.known, rule.autoKnown = nil, nil end
        end
        for _, key in ipairs({"managed", "spells", "rankFlags"}) do
            if MacroWeaverDB[key] ~= nil and type(MacroWeaverDB[key]) ~= "table" then MacroWeaverDB[key] = nil end
        end
        if type(MacroWeaverDB.name) ~= "string" then MacroWeaverDB.name = "" end
        if MacroWeaverDB.spellFilter ~= "class" and MacroWeaverDB.spellFilter ~= "pet" then MacroWeaverDB.spellFilter = nil end
        if type(MacroWeaverDB.draft.target) ~= "string" then MacroWeaverDB.draft.target = nil end
        draft = MacroWeaverDB.draft
        if draft.autoUpdate == nil then draft.autoUpdate = true end
        if MacroWeaverDB.allSpells == nil then MacroWeaverDB.allSpells = MacroWeaverDB.otherSpecs or false end
        if MacroWeaverDB.openOnLogin == nil then MacroWeaverDB.openOnLogin = true end
        SLASH_MACROWEAVER1, SLASH_MACROWEAVER2 = "/mw", "/macroweaver"
        SlashCmdList.MACROWEAVER = toggle
        return
    end
    if not draft or event == "ADDON_LOADED" or ((event == "UNIT_AURA" or event == "UNIT_PET") and name ~= "player") then return end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if frame then frame.Fit() end
        return
    end
    if event == "UPDATE_SHAPESHIFT_FORMS" then
        -- Some clients send this on every shapeshift.
        local ids = {}
        for _, form in ipairs(M.LiveForms()) do ids[#ids + 1] = tostring(form.id or form.name) end
        local signature = table.concat(ids, ",")
        if signature == formSignature then return end
        formSignature = signature
    end
    if event == "PLAYER_LOGIN" and MacroWeaverDB.openOnLogin and not frame and not M.InCombat() then createUI() end
    if spellEvents[event] then updateNeeded = true end
    if event == "PLAYER_REGEN_DISABLED" then closeMenu(); Refresh(); return end
    if M.InCombat() or pending then return end
    local function refresh()
        pending = nil
        if M.InCombat() then return end
        if updateNeeded then updateNeeded = nil; M.UpdateMacros(); M.UpdateRankFlags() end
        if frame and frame:IsShown() then RefreshCatalog() end
    end
    if C_Timer and C_Timer.After then pending = true; C_Timer.After(0.2, refresh)
    else refresh() end
end)
