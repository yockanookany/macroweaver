local _, M = ...

function M.SaveBody(draft, spells)
    local body, problem, bytes = M.Build(draft)
    if not body then return nil, problem, bytes end
    local known = {}
    for _, spell in ipairs(spells or {}) do
        if spell.available then known[M.ActionKey(spell)] = spell end
    end
    local active = M.Copy(draft)
    active.rules = {}
    local group, lastGroup, previousCommand = 0, nil, nil
    for _, rule in ipairs(draft.rules) do
        local a = rule.action
        local command = rule.cancel and "cancel" or (a.kind == "spell" and "cast" or "use")
        if rule.newLine or command ~= previousCommand then group = group + 1 end
        previousCommand = command
        if M.FormPending(rule) then
            if draft.autoUpdate == false then
                return nil, "Enable updates after training to plan a form or stance not yet learned."
            end
        else
            local copy = M.Copy(rule)
            local fresh = a.kind == "spell" and known[M.ActionKey(a)]
            if fresh then copy.action = M.Copy(fresh) end
            if copy.autoKnown then copy.known, copy.autoKnown = nil, nil end
            copy.newLine = #active.rules > 0 and group ~= lastGroup or nil
            active.rules[#active.rules + 1] = copy
            lastGroup = group
        end
    end
    if #active.rules == 0 then return "#showtooltip" end
    return M.Build(active)
end

local function plan(draft)
    local parts = {M.Build(draft) or ""}
    for _, rule in ipairs(draft.rules or {}) do parts[#parts + 1] = tostring(rule.form) end
    return table.concat(parts, "\n")
end

function M.CanReuse(name, body, draft)
    local saved = MacroWeaverDB and MacroWeaverDB.managed and MacroWeaverDB.managed[name]
    if type(saved) == "table" and M.ValidDraft(saved.draft) then return plan(saved.draft) == plan(draft) end
    if saved then return false end
    return body ~= "#showtooltip"
end

function M.Owns(name, body)
    local saved = MacroWeaverDB and MacroWeaverDB.managed and MacroWeaverDB.managed[name]
    return type(saved) == "table" and saved.body == body
end

function M.TrackMacro(name, body, draft)
    if not MacroWeaverDB then return end
    MacroWeaverDB.managed = MacroWeaverDB.managed or {}
    local copy = M.Copy(draft)
    copy.target = nil
    MacroWeaverDB.managed[name] = {body = body, draft = copy}
end

function M.SavedMacros()
    local list = {}
    if not MacroWeaverDB or type(MacroWeaverDB.managed) ~= "table" or not GetNumMacros or not GetMacroInfo then return list end
    local base = M.Limits()
    local _, count = GetNumMacros()
    for index = base + 1, base + (count or 0) do
        local ok, name, icon, body = pcall(GetMacroInfo, index)
        local saved = ok and type(name) == "string" and MacroWeaverDB.managed[name]
        if type(saved) == "table" and saved.body == body and M.ValidDraft(saved.draft) then
            list[#list + 1] = {kind = "saved", index = index, name = name, icon = icon, body = body}
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function M.UpdateMacros()
    if M.InCombat() or not MacroWeaverDB or not MacroWeaverDB.managed or not GetMacroInfo or not EditMacro then return end
    local spells = M.ScanSpells()
    if not spells then return end
    local base = M.Limits()
    local _, count = GetNumMacros()
    local byName = {}
    for index = base + 1, base + count do
        local name, _, body = GetMacroInfo(index)
        if name then
            if byName[name] then byName[name].duplicate = true
            else byName[name] = {index = index, body = body} end
        end
    end
    for name, saved in pairs(MacroWeaverDB.managed) do
        local current = byName[name]
        if type(name) ~= "string" or type(saved) ~= "table" or not M.ValidDraft(saved.draft) then
            MacroWeaverDB.managed[name] = nil
        elseif not current and count == 0 then
            -- Macros may still be loading at login.
        elseif not current or current.duplicate or current.body ~= saved.body then
            MacroWeaverDB.managed[name] = nil
            if saved.draft.autoUpdate ~= false then
                print("MacroWeaver: automatic updates stopped for " .. name .. " because it was edited, removed or renamed.")
            end
        elseif saved.draft.autoUpdate == false then
        elseif current.body:find("form:[1-9]") and (M.SafeCall(GetNumShapeshiftForms) or 0) == 0 then
            -- An empty shapeshift bar hasn't loaded yet.
        else
            M.NameForms(saved.draft)
            if M.RepairDraft(saved.draft) then
                print("MacroWeaver: " .. name .. ": targets that always matched now require Unit exists, so later rules can run.")
            end
            local body, problem = M.SaveBody(saved.draft, spells)
            if body and body ~= current.body then
                local ok = pcall(EditMacro, current.index, nil, nil, body)
                local actualName, _, actualBody = GetMacroInfo(current.index)
                if ok and actualName == name and actualBody == body then saved.body = body
                else problem = "WoW blocked the update; it will be retried after the next spellbook change." end
            end
            if problem and problem ~= saved.problem then
                print("MacroWeaver: " .. name .. ": " .. problem)
            end
            saved.problem = problem
        end
    end
end
