local _, M = ...
M.MAX_BODY, M.MAX_RULES = 255, 12
M.Choices = {
    unit = {{"auto", "Normal targeting"}, {"mouseover", "Mouseover"}, {"target", "Current target"},
        {"focus", "Focus"}, {"targettarget", "Target of target"}, {"player", "Self"}, {"cursor", "At cursor"}},
    reaction = {{"any", "Any unit"}, {"help", "Friendly"}, {"harm", "Hostile"}, {"exists", "Unit exists"}},
    life = {{"any", "Alive or dead"}, {"nodead", "Alive"}, {"dead", "Dead"}},
    modifier = {{"any", "No modifier required"}, {"shift", "Shift"}, {"alt", "Alt"}, {"ctrl", "Ctrl"},
        {"nomod", "No modifiers held"}, {"mod", "Any modifier held"}},
    state = {{"any", "Any state"}, {"combat", "In combat"}, {"nocombat", "Out of combat"},
        {"stealth", "Stealthed"}, {"nostealth", "Not stealthed"}, {"mounted", "Mounted"}, {"nomounted", "Not mounted"},
        {"swimming", "Swimming"}, {"noswimming", "Not swimming"}, {"indoors", "Indoors"}, {"outdoors", "Outdoors"}},
}
M.Templates = {
    {"mouseover", "Mouseover + normal fallback"},
    {"dual", "Friendly / hostile + fallback"},
    {"heal", "Friendly mouseover > target > self"},
    {"emergency", "Stop, leave form, then two casts"},
    {"modifiers", "Shift / Alt / default"},
    {"focus", "Focus + normal fallback"},
    {"cursor", "Ground spell at cursor"},
    {"self", "Cast on yourself"},
    {"known", "First spell known"},
    {"cooldown", "Cooldown + trinkets / items"},
    {"shift", "Shift into form, then ability"},
    {"swim", "Swimming / otherwise"},
    {"blank", "Single action"},
}

function M.Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = M.Copy(v) end
    return out
end

function M.Rule(fields)
    local rule = {unit = "auto", reaction = "any", life = "any", modifier = "any", state = "any", form = "any"}
    for k, v in pairs(fields or {}) do rule[k] = v end
    return rule
end

function M.NewDraft(template)
    local draft = {version = 2, template = template, rules = {}, autoUpdate = true}
    local function add(fields) draft.rules[#draft.rules + 1] = M.Rule(fields) end
    if template == "mouseover" then
        add({unit = "mouseover", reaction = "auto", life = "nodead", link = 1})
        add({link = 1})
    elseif template == "dual" then
        add({unit = "mouseover", reaction = "help", life = "nodead", link = 1})
        add({unit = "target", reaction = "help", life = "nodead", link = 1})
        add({unit = "target", reaction = "harm", life = "nodead", link = 2})
        add({link = 1})
    elseif template == "heal" then
        add({unit = "mouseover", reaction = "help", life = "nodead", link = 1})
        add({unit = "target", reaction = "help", life = "nodead", link = 1})
        add({unit = "player", link = 1})
    elseif template == "emergency" then
        draft.stopcasting, draft.stopattack, draft.cancelform = true, true, true
        add(); add({newLine = true})
    elseif template == "modifiers" then
        add({modifier = "shift"}); add({modifier = "alt"}); add()
    elseif template == "focus" then
        add({unit = "focus", reaction = "exists", life = "nodead", link = 1}); add({link = 1})
    elseif template == "cursor" then add({unit = "cursor"})
    elseif template == "self" then add({unit = "player"})
    elseif template == "known" then add({known = true}); add({known = true}); add()
    elseif template == "shift" then
        add({formNot = true, formFollow = true}); add({newLine = true, formFollow = true})
    elseif template == "swim" then add({state = "swimming"}); add()
    else
        add()
        if template == "cooldown" then draft.trinket1, draft.trinket2 = true, true end
    end
    return draft
end

function M.ValidDraft(draft)
    if type(draft) ~= "table" or type(draft.rules) ~= "table" or #draft.rules == 0 or #draft.rules > M.MAX_RULES then return false end
    for _, rule in ipairs(draft.rules) do
        if type(rule) ~= "table" then return false end
        if rule.action ~= nil and (type(rule.action) ~= "table" or type(rule.action.name) ~= "string") then return false end
    end
    return draft.tooltip == nil or (type(draft.tooltip) == "table" and type(draft.tooltip.name) == "string")
end

-- A bare target such as [@focus] always matches, so nothing after it would run.
function M.RepairDraft(draft)
    if not M.ValidDraft(draft) or M.Build(draft) then return false end
    local rules = M.Copy(draft.rules)
    local changed = false
    for _, rule in ipairs(rules) do
        local unit = rule.unit
        if unit and unit ~= "auto" and unit ~= "player" and unit ~= "cursor"
            and (rule.reaction or "any") == "any" and rule.life ~= "dead" then
            rule.reaction, changed = "exists", true
        end
    end
    local repaired = M.Copy(draft); repaired.rules = rules
    if not changed or not M.Build(repaired) then return false end
    draft.rules = rules
    return true
end

function M.NameForms(draft)
    if not M.LiveForms or not M.ValidDraft(draft) then return end
    local live, families
    for _, rule in ipairs(draft.rules) do
        local slot = type(rule.form) == "string" and tonumber(rule.form:match("^([1-9])$"))
        if slot then
            live = live or M.LiveForms()
            families = families or M.ClassForms()
            local form = live[slot]
            local key = form and form.name and M.FormKey(form, families)
            if key and key ~= "any" and key ~= "0" and not key:find("[%c%[%];|,]") then rule.form = key end
        end
    end
end

function M.Migrate(draft)
    if type(draft) ~= "table" then return M.NewDraft("blank") end
    if draft.version == 2 and type(draft.rules) == "table" then return draft end
    local out = {version = 2, template = "custom", rules = {}}
    local function add(unit, reaction, spell)
        local action = M.Copy(spell)
        if action then action.kind = "spell" end
        out.rules[#out.rules + 1] = M.Rule({unit = unit, reaction = reaction, life = "nodead", action = action})
    end
    if draft.mode ~= "harm" then add("mouseover", "help", draft.help) end
    if draft.mode ~= "help" then add("mouseover", "harm", draft.harm) end
    if draft.target then
        if draft.mode ~= "harm" then add("target", "help", draft.help) end
        if draft.mode ~= "help" then add("target", "harm", draft.harm) end
    end
    if draft.self and draft.mode ~= "harm" then add("player", "help", draft.help) end
    return out
end

function M.MakeCustom(draft)
    draft.template = "custom"
    for _, rule in ipairs(draft.rules) do rule.link, rule.formFollow = nil, nil end
end

function M.Unlink(draft, index)
    local rule = draft.rules[index]
    if not rule then return end
    local link, follow = rule.link, rule.formFollow
    rule.link, rule.formFollow = nil, nil
    local linked, following = {}, {}
    for _, r in ipairs(draft.rules) do
        if link and r.link == link then linked[#linked + 1] = r end
        if follow and r.formFollow then following[#following + 1] = r end
    end
    if #linked == 1 then linked[1].link = nil end
    if #following == 1 then following[1].formFollow = nil end
end

function M.LinkedWith(draft, index)
    local rule, spell, form = draft.rules[index], {}, {}
    if not rule then return nil, nil end
    for i, r in ipairs(draft.rules) do
        if i ~= index and rule.link and r.link == rule.link then spell[#spell + 1] = tostring(i) end
        if i ~= index and rule.formFollow and r.formFollow then form[#form + 1] = tostring(i) end
    end
    return #spell > 0 and table.concat(spell, ", ") or nil, #form > 0 and table.concat(form, ", ") or nil
end

function M.SetAction(draft, index, action)
    local selected = draft.rules[index]
    if not selected then return end
    for _, rule in ipairs(draft.rules) do
        if rule == selected or (selected.link and rule.link == selected.link) then
            if not (rule.action and action.kind == rule.action.kind and action.name == rule.action.name) then rule.rank = nil end
            rule.action = M.Copy(action)
            rule.cancel = action.kind == "aura" or nil
            rule.planned = action.kind == "spell" and action.available == false or nil
            if rule.autoKnown or action.kind ~= "spell" then rule.known, rule.autoKnown = nil, nil end
            if action.kind ~= "spell" or rule.cancel then rule.noToggle = nil end
        end
    end
    local form = selected.formFollow and M.ActionForm and M.ActionForm(action)
    if form then
        for _, rule in ipairs(draft.rules) do if rule.formFollow then rule.form = form end end
    end
end

local function safeName(name)
    return type(name) == "string" and #name > 0 and not name:find("[%c%[%];|]")
end

function M.FormPending(rule)
    local form = rule.form
    return type(form) == "string" and form ~= "any" and not form:match("^%d$")
        and not (M.FormIndex and M.FormIndex(form))
end

local function inChoices(key, value)
    if value == nil then return true end
    for _, choice in ipairs(M.Choices[key]) do if choice[1] == value then return true end end
end

function M.Conditions(rule)
    for _, key in ipairs({"unit", "reaction", "life", "modifier", "state"}) do
        if not (key == "reaction" and rule.reaction == "auto") and not inChoices(key, rule[key]) then
            return nil, "Choose a valid " .. key .. "."
        end
    end
    local c = {}
    local mod = rule.modifier or "any"
    if mod ~= "any" then c[#c + 1] = (mod == "nomod" or mod == "mod") and mod or ("mod:" .. mod) end
    if rule.action and rule.action.pet and not rule.cancel then c[#c + 1] = "pet" end
    if rule.known and not (rule.action and rule.action.pet) then
        if not rule.action or rule.action.kind ~= "spell" or not safeName(rule.action.name) or rule.action.name:find("[,/]") then
            return nil, "'Only if known' needs a spell."
        end
        c[#c + 1] = "known:" .. rule.action.name
    end
    if rule.form ~= nil and rule.form ~= "any" then
        local form = rule.form
        if type(form) ~= "string" or not (form:match("^%d$") or (safeName(form) and not form:find(","))) then
            return nil, "Choose a valid form / stance."
        end
        c[#c + 1] = (rule.formNot and "noform:" or "form:") .. (form:match("^%d$") or (M.FormIndex and M.FormIndex(form)) or "?")
    end
    if rule.state and rule.state ~= "any" then c[#c + 1] = rule.state end
    if rule.unit and rule.unit ~= "auto" then c[#c + 1] = "@" .. rule.unit end
    local reaction = rule.reaction or "any"
    if reaction == "auto" then
        local a = rule.action or {}
        reaction = a.helpful and "help" or (a.harmful and "harm" or "exists")
    end
    if rule.unit == "cursor" and (reaction ~= "any" or (rule.life and rule.life ~= "any")) then
        return nil, "At cursor needs Any unit and Alive or dead."
    end
    if reaction ~= "any" then c[#c + 1] = reaction end
    if rule.life and rule.life ~= "any" then c[#c + 1] = rule.life end
    return #c > 0 and ("[" .. table.concat(c, ",") .. "]") or ""
end

local function alwaysMatches(condition)
    for part in condition:sub(2, -2):gmatch("[^,]+") do
        if part:sub(1, 1) ~= "@" and part ~= "nodead" then return false end
    end
    return true
end

function M.Build(draft)
    if not draft or type(draft.rules) ~= "table" or #draft.rules == 0 then return nil, "Add an action." end
    if #draft.rules > M.MAX_RULES then return nil, "Use at most 12 rules." end
    local function tooltipText(t)
        if type(t) ~= "table" or not safeName(t.name) then return nil end
        if t.kind == "spell" or t.kind == "aura" then return " " .. t.name
        elseif t.kind == "item" and type(t.id) == "number" and t.id > 0 and t.id % 1 == 0 then return " item:" .. t.id
        elseif t.kind == "slot" and type(t.id) == "number" and t.id >= 1 and t.id <= 19 and t.id % 1 == 0 then return " " .. t.id end
    end
    local tooltip = ""
    if draft.tooltip then
        tooltip = tooltipText(draft.tooltip)
        if not tooltip then return nil, "Choose a valid tooltip action." end
    elseif draft.trinket1 or draft.trinket2 then
        tooltip = tooltipText(draft.rules[1].action) or ""
    end
    local lines = {"#showtooltip" .. tooltip}
    if draft.stopcasting then lines[#lines + 1] = "/stopcasting" end
    if draft.stopattack then lines[#lines + 1] = "/stopattack" end
    if draft.cancelform then lines[#lines + 1] = "/cancelform" end
    if draft.startattack then lines[#lines + 1] = "/startattack" end
    if draft.petattack then lines[#lines + 1] = "/petattack" end
    if draft.trinket1 then lines[#lines + 1] = "/use 13" end
    if draft.trinket2 then lines[#lines + 1] = "/use 14" end
    local groups, group = {}, nil
    for i, rule in ipairs(draft.rules) do
        local action = rule.action
        if not action or not safeName(action.name) then return nil, "Choose an action for rule " .. i .. "." end
        local command, value
        if action.kind == "spell" then
            command, value = rule.cancel and "/cancelaura" or "/cast", action.name
            if rule.rank ~= nil and not rule.cancel then
                local rank = rule.rank
                if type(rank) ~= "number" or rank < 1 or rank > 99 or rank % 1 ~= 0 then return nil, "Rule " .. i .. ": choose a valid rank." end
                value = value .. "(" .. M.RankText(rank) .. ")"
            end
            if rule.noToggle and not rule.cancel then value = "!" .. value end
        elseif action.kind == "aura" and rule.cancel then command, value = "/cancelaura", action.name
        elseif action.kind == "item" and type(action.id) == "number" and action.id > 0 and action.id % 1 == 0 then
            command, value = "/use", "item:" .. action.id
        elseif action.kind == "slot" and type(action.id) == "number" and action.id >= 1 and action.id <= 19 and action.id % 1 == 0 then
            command, value = "/use", tostring(action.id)
        else return nil, "Invalid action in rule " .. i .. "." end
        if rule.cancel and action.kind ~= "spell" and action.kind ~= "aura" then return nil, "Cancel aura needs a spell or buff." end
        local condition, problem = M.Conditions(rule)
        if not condition then return nil, "Rule " .. i .. ": " .. problem end
        if not group or rule.newLine or group.command ~= command then
            group = {command = command, clauses = {}}
            groups[#groups + 1] = group
        elseif group.unconditional then
            return nil, "Rule " .. i .. " cannot follow a rule that always matches. Move it earlier, select New command line,"
                .. " or give the earlier rule a Unit type such as Unit exists."
        end
        local previous = group.clauses[#group.clauses]
        if previous and previous.value == value then
            previous.condition = previous.condition .. (condition == "" and "[]" or condition)
        else group.clauses[#group.clauses + 1] = {value = value, condition = condition} end
        group.unconditional = alwaysMatches(condition)
    end
    for _, entry in ipairs(groups) do
        local clauses = {}
        for _, clause in ipairs(entry.clauses) do clauses[#clauses + 1] = clause.condition .. clause.value end
        lines[#lines + 1] = entry.command .. " " .. table.concat(clauses, ";")
    end
    local body = table.concat(lines, "\n")
    if #body > M.MAX_BODY then return nil, #body .. " / 255 bytes. Remove a rule or split into two macros.", #body end
    return body
end

function M.Limits()
    local c = Constants and Constants.MacroConsts or {}
    return c.MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACROS or 120, c.MAX_CHARACTER_MACROS or MAX_CHARACTER_MACROS or 18
end

function M.AutoName(draft, body)
    local action = draft.rules[1] and draft.rules[1].action
    local stem = action and action.name or "Macro"
    local cut = math.min(#stem, 12)
    while cut > 0 and stem:byte(cut + 1) and stem:byte(cut + 1) >= 128 and stem:byte(cut + 1) < 192 do cut = cut - 1 end
    stem = stem:sub(1, cut)
    stem = stem:gsub("|", ""):match("^%s*(.-)%s*$")
    if stem == "" then stem = "Macro" end
    local names, base = {}, M.Limits()
    if GetNumMacros and GetMacroInfo then
        local _, count = GetNumMacros()
        for index = base + 1, base + count do
            local name, _, text = GetMacroInfo(index)
            if name then
                names[name] = true
                if text == body and (not M.CanReuse or M.CanReuse(name, body, draft)) then return name end
            end
        end
    end
    if not names[stem] then return stem end
    for number = 2, 999 do
        local name = stem .. " " .. number
        if not names[name] then return name end
    end
    return "MW Macro"
end

function M.Save(draft, requestedName)
    if M.InCombat() then return nil, "Leave combat to create or pick up macros." end
    local body, problem = M.Build(draft)
    if not body then return nil, problem end
    if M.SaveBody then
        body, problem = M.SaveBody(draft, M.ScanSpells())
        if not body then return nil, problem end
    end
    if body:find("form:?", 1, true) then return nil, "Enable Auto-update saved macro to plan a form or stance not yet learned." end
    if not GetNumMacros or not GetMacroInfo or not CreateMacro then return nil, "Macro creation API unavailable." end
    local name = (requestedName or ""):match("^%s*(.-)%s*$")
    local target = type(draft.target) == "string" and draft.target or nil
    if name == "" then name = target or M.AutoName(draft, body) end
    if #name > 16 or name:find("[%c|]") then return nil, "Use a macro name of 1-16 bytes, or leave it blank for an automatic name." end
    local base, capacity = M.Limits()
    local _, count = GetNumMacros()
    if target and name ~= target and M.Owns and EditMacro then
        local from
        for index = base + 1, base + count do
            local existing, _, text = GetMacroInfo(index)
            if existing == name then return nil, "Another macro is already named " .. name .. "." end
            if existing == target and M.Owns(target, text) then from = index end
        end
        if from then
            -- WoW may re-sort macros by name, so find the renamed one again.
            local ok = pcall(EditMacro, from, name, nil, body)
            local renamed
            for index = base + 1, base + count do
                local savedName, _, savedBody = GetMacroInfo(index)
                if savedName == name and savedBody == body then renamed = index end
            end
            if not ok or not renamed then return nil, "WoW could not rename the macro." end
            MacroWeaverDB.managed[target] = nil
            M.TrackMacro(name, body, draft)
            draft.target = name
            return renamed, nil, name, true
        end
    end
    for index = base + 1, base + count do
        local existing, _, text = GetMacroInfo(index)
        if existing == name then
            if text == body and (not M.CanReuse or M.CanReuse(name, body, draft)) then
                if M.TrackMacro then M.TrackMacro(name, body, draft) end
                return index, nil, name
            end
            if M.Owns and M.Owns(name, text) and EditMacro then
                local ok = pcall(EditMacro, index, nil, nil, body)
                local savedName, _, savedBody = GetMacroInfo(index)
                if not ok or savedName ~= name or savedBody ~= body then return nil, "WoW could not update the macro." end
                M.TrackMacro(name, body, draft)
                return index, nil, name, true
            end
            return nil, "That name belongs to a different macro. Clear the name for an automatic new name."
        end
    end
    if count >= capacity then return nil, "Character macro slots are full. Free a slot in WoW's Macros window." end
    local ok, index = pcall(CreateMacro, name, "INV_MISC_QUESTIONMARK", body, true)
    if not ok or type(index) ~= "number" or index <= base then return nil, "WoW could not create the character macro." end
    local savedName, _, savedBody = GetMacroInfo(index)
    if savedName ~= name or savedBody ~= body then return nil, "WoW did not save the complete macro. Check the Macros window." end
    if M.TrackMacro then M.TrackMacro(name, body, draft) end
    return index, nil, name
end

function M.Pickup(draft, name)
    if M.InCombat() then return nil, "Leave combat to create or pick up macros." end
    if not PickupMacro then return nil, "Macro pickup API unavailable." end
    if GetCursorInfo and GetCursorInfo() then return nil, "Place or clear the item on your cursor first." end
    local index, problem, savedName, updated = M.Save(draft, name)
    if not index then return nil, problem end
    local ok = pcall(PickupMacro, index)
    if not ok then return nil, "WoW blocked macro pickup. Try again outside combat." end
    return index, nil, savedName, updated
end
