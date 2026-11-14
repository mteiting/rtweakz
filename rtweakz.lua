RTweakz = RTweakz or {}

local defaults = {
    fpsOutOfInstance = 60,
    fpsInInstance = 144,
    fpsRested = 45,
    fpsAfk = 30,
    debug = false,
    piEnabled = false,
    piKeywords = "pi",
    piHighlight = true,
    piSound = "raidwarning",
    piOnlyReady = true,
    piMacro = false,
    logRaid = false,
    logDungeon = false,
    logStartedByAddon = false,
}

RTweakzDB = RTweakzDB or {}

local function FormatFPS(fps)
    return (fps == 0) and "uncapped" or (fps .. " FPS")
end

-- Priority: AFK > instance > rested > open world
local function GetDesiredFPS()
    if UnitIsAFK("player") then
        return RTweakzDB.fpsAfk, "AFK"
    end
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType ~= "none" then
        return RTweakzDB.fpsInInstance, "instance"
    end
    if IsResting() then
        return RTweakzDB.fpsRested, "rested"
    end
    return RTweakzDB.fpsOutOfInstance, "world"
end

local lastApplied
local function ApplyFPS()
    local fps, reason = GetDesiredFPS()
    SetCVar("maxFPS", fps)
    if RTweakzDB.debug and fps ~= lastApplied then
        print("|cff00ff00RTweakz|r: cap -> " .. FormatFPS(fps) .. " (" .. reason .. ")")
    end
    lastApplied = fps
end

-- PI request alert: whole-word match so "pi" doesn't fire on "pizza"
local function KeywordPattern(keyword)
    local escaped = keyword:gsub("%W", "%%%0")
    local prefix = keyword:find("^%w") and "%f[%w]" or ""
    local suffix = keyword:find("%w$") and "%f[%W]" or ""
    return prefix .. escaped .. suffix
end

local function MatchesPIKeyword(message)
    message = message:lower()
    for keyword in RTweakzDB.piKeywords:gmatch("[^,]+") do
        keyword = keyword:match("^%s*(.-)%s*$"):lower()
        if keyword ~= "" and message:find(KeywordPattern(keyword)) then
            return true
        end
    end
    return false
end

-- Pulsing overlay shown on the requester's party/raid frame
local HIGHLIGHT_DURATION = 5

local highlight = CreateFrame("Frame", nil, UIParent)
highlight:SetFrameStrata("HIGH")
highlight:Hide()

local highlightTexture = highlight:CreateTexture(nil, "OVERLAY")
highlightTexture:SetAllPoints()
highlightTexture:SetColorTexture(1, 0.85, 0.1, 0.4)

local pulse = highlight:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local pulseAlpha = pulse:CreateAnimation("Alpha")
pulseAlpha:SetFromAlpha(1)
pulseAlpha:SetToAlpha(0.3)
pulseAlpha:SetDuration(0.5)

local hideTimer
local function HighlightUnitFrame(unitFrame)
    highlight:ClearAllPoints()
    highlight:SetAllPoints(unitFrame)
    highlight:Show()
    pulse:Play()
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(HIGHLIGHT_DURATION, function()
        pulse:Stop()
        highlight:Hide()
    end)
end

local function FullUnitName(unit)
    local name, realm = UnitFullName(unit)
    if not name then
        return nil
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName()
    end
    return realm and (name .. "-" .. realm) or name
end

-- Whisper senders are fully qualified ("Name-Realm"); BN senders never match a unit
local function FindGroupUnit(sender)
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    end
    for i = 1, count do
        local unit = prefix .. i
        if FullUnitName(unit) == sender then
            return unit
        end
    end
end

local function FrameShowsUnit(unitFrame, unit)
    return unitFrame and unitFrame:IsVisible() and unitFrame.displayedUnit
        and UnitIsUnit(unitFrame.displayedUnit, unit)
end

-- Default (non raid-style) party frames: retail keeps them in a frame pool,
-- Classic-based clients (Era, WoW Forever) use global PartyMemberFrame1-4
local function FindPartyMemberFrame(unit)
    if not (PartyFrame and PartyFrame.PartyMemberFramePool) then
        for i = 1, 4 do
            local memberFrame = _G["PartyMemberFrame" .. i]
            local memberUnit = memberFrame and (memberFrame.unit or ("party" .. i))
            if memberFrame and memberFrame:IsVisible() and UnitIsUnit(memberUnit, unit) then
                return memberFrame
            end
        end
        return nil
    end
    for memberFrame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
        local memberUnit = memberFrame.unit or (memberFrame.GetUnit and memberFrame:GetUnit())
        if memberFrame:IsVisible() and memberUnit and UnitIsUnit(memberUnit, unit) then
            return memberFrame
        end
    end
end

-- Blizzard frames: default party, raid-style party, combined and separate raid groups
local function FindUnitFrame(unit)
    local partyFrame = FindPartyMemberFrame(unit)
    if partyFrame then return partyFrame end
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if FrameShowsUnit(f, unit) then return f end
    end
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if FrameShowsUnit(f, unit) then return f end
    end
    for group = 1, 8 do
        for member = 1, 5 do
            local f = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if FrameShowsUnit(f, unit) then return f end
        end
    end
end

local piSounds = {
    { key = "raidwarning", label = "Raid warning", soundKit = SOUNDKIT.RAID_WARNING },
    { key = "readycheck",  label = "Ready check",  soundKit = SOUNDKIT.READY_CHECK },
    { key = "alarm",       label = "Alarm clock",  soundKit = SOUNDKIT.ALARM_CLOCK_WARNING_3 },
    { key = "ping",        label = "Map ping",     soundKit = SOUNDKIT.MAP_PING },
    { key = "whisper",     label = "Whisper",      soundKit = SOUNDKIT.TELL_MESSAGE },
    { key = "none",        label = "No sound" },
}

-- Drop sounds this client doesn't define (SOUNDKIT differs between retail and Classic clients)
for i = #piSounds, 1, -1 do
    if piSounds[i].key ~= "none" and not piSounds[i].soundKit then
        table.remove(piSounds, i)
    end
end

local function GetPISound(key)
    for _, sound in ipairs(piSounds) do
        if sound.key == key then
            return sound
        end
    end
end

RTweakz.PISounds = piSounds
RTweakz.GetPISound = GetPISound

local function PlayPISound()
    local sound = GetPISound(RTweakzDB.piSound)
    if sound and sound.soundKit then
        PlaySound(sound.soundKit)
    end
end

-- Power Infusion has the same spell ID on retail and Classic-based clients
local PI_SPELL_ID = 10060

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

local function PlayerKnowsPI()
    return (IsPlayerSpell and IsPlayerSpell(PI_SPELL_ID)) or (IsSpellKnown and IsSpellKnown(PI_SPELL_ID)) or false
end

local function GetPISpellName()
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(PI_SPELL_ID)
    end
    return GetSpellInfo and (GetSpellInfo(PI_SPELL_ID))
end

local function GetSpellCooldownInfo(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            return info.startTime, info.duration
        end
        return nil
    end
    if GetSpellCooldown then
        return GetSpellCooldown(spellID)
    end
end

-- Remaining PI cooldown in seconds (0 = ready), or nil when unknown:
-- PI not known on this character, or the client hides cooldowns as secret values
local function GetPICooldownRemaining()
    if not PlayerKnowsPI() then
        return nil
    end
    local ok, start, duration = pcall(GetSpellCooldownInfo, PI_SPELL_ID)
    if not ok or start == nil or duration == nil or IsSecret(start) or IsSecret(duration) then
        return nil
    end
    if duration <= 1.5 then
        return 0 -- not on cooldown, or only on the global cooldown
    end
    return math.max(0, start + duration - GetTime())
end

-- Character macro that casts PI on the last requester; macros can't be edited in combat,
-- so a request during combat is applied as soon as combat ends
local PI_MACRO_NAME = "RTweakzPI"
local pendingMacroTarget

local function PIMacroBody(target)
    local spell = GetPISpellName() or "Power Infusion"
    local condition = target and ("[@" .. target .. ",help,nodead]") or "[@mouseover,help,nodead]"
    return "#showtooltip " .. spell .. "\n/cast " .. condition .. "[] " .. spell
end

local function WritePIMacro(target)
    local body = PIMacroBody(target)
    local index = GetMacroIndexByName(PI_MACRO_NAME)
    if index and index > 0 then
        EditMacro(index, PI_MACRO_NAME, nil, body)
        return true
    end
    local ok, newIndex = pcall(CreateMacro, PI_MACRO_NAME, "INV_MISC_QUESTIONMARK", body, true)
    if not ok or not newIndex then
        print("|cff00ff00RTweakz|r: could not create the " .. PI_MACRO_NAME .. " macro (character macro slots full?)")
        return false
    end
    print("|cff00ff00RTweakz|r: created character macro " .. PI_MACRO_NAME .. " — drag it to your action bars")
    return true
end

local function SetPIMacroTarget(target)
    if InCombatLockdown() then
        pendingMacroTarget = target
        print("|cff00ff00RTweakz|r: " .. PI_MACRO_NAME .. " will target " .. target .. " after combat")
        return
    end
    pendingMacroTarget = nil
    if WritePIMacro(target) then
        print("|cff00ff00RTweakz|r: " .. PI_MACRO_NAME .. " now targets " .. target)
    end
end

-- silent: automatic check on login (settings are account-wide, so alts without PI stay quiet)
local function EnsurePIMacro(silent)
    if not RTweakzDB.piMacro then
        return
    end
    if not PlayerKnowsPI() then
        if not silent then
            print("|cff00ff00RTweakz|r: this character doesn't know Power Infusion — no macro created")
        end
        return
    end
    if InCombatLockdown() then
        if not silent then
            print("|cff00ff00RTweakz|r: leave combat to create the " .. PI_MACRO_NAME .. " macro")
        end
        return
    end
    local index = GetMacroIndexByName(PI_MACRO_NAME)
    if not index or index == 0 then
        WritePIMacro(nil) -- mouseover until the first request comes in
    end
end

local function ApplyPendingPIMacro()
    if pendingMacroTarget and RTweakzDB.piMacro then
        SetPIMacroTarget(pendingMacroTarget)
    end
end

-- Name usable in a macro's @ condition: "Name" on your realm, "Name-Realm" otherwise
local function MacroTargetName(sender, event, unit)
    if unit then
        local name = GetUnitName(unit, true)
        if name and not IsSecret(name) then
            return name
        end
    end
    if event == "CHAT_MSG_BN_WHISPER" then
        return nil -- BN sender is a Battle.net name, not a character
    end
    return Ambiguate(sender, "none")
end

local function OnPIMessage(message, sender, event)
    if IsSecret(message) or IsSecret(sender) then
        return -- chat content hidden by the client (retail combat restrictions)
    end
    if not RTweakzDB.piEnabled or not MatchesPIKeyword(message) then
        return
    end
    if sender == FullUnitName("player") then
        return -- own message in party chat
    end
    local name = Ambiguate(sender, "short")

    if RTweakzDB.piOnlyReady then
        local remaining = GetPICooldownRemaining()
        if remaining and remaining > 0 then
            print("|cff00ff00RTweakz|r: PI request from " .. name .. " ignored — PI on cooldown ("
                .. math.ceil(remaining) .. "s)")
            return
        end
    end

    RaidNotice_AddMessage(RaidWarningFrame, name .. " is requesting Power Infusion!", ChatTypeInfo["RAID_WARNING"])
    PlayPISound()
    print("|cff00ff00RTweakz|r: PI request from " .. name)

    local unit = FindGroupUnit(sender)

    if RTweakzDB.piMacro and PlayerKnowsPI() then
        local target = MacroTargetName(sender, event, unit)
        if target then
            SetPIMacroTarget(target)
        end
    end

    if RTweakzDB.piHighlight then
        local unitFrame = unit and FindUnitFrame(unit)
        if unitFrame then
            HighlightUnitFrame(unitFrame)
        elseif RTweakzDB.debug then
            print("|cff00ff00RTweakz|r: no unit frame to highlight ("
                .. (unit and (unit .. " has no visible default frame") or (sender .. " not found in group")) .. ")")
        end
    end
end

-- Auto combat log: start in raids/dungeons (per setting), stop on leaving —
-- but only stop a log RTweakz started itself, never a manual /combatlog
local function UpdateCombatLog()
    local inInstance, instanceType = IsInInstance()
    local want = inInstance and ((instanceType == "raid" and RTweakzDB.logRaid)
        or (instanceType == "party" and RTweakzDB.logDungeon)) or false
    local logging = LoggingCombat()
    if want and not logging then
        pcall(SetCVar, "advancedCombatLogging", 1) -- needed for Warcraft Logs
        LoggingCombat(true)
        RTweakzDB.logStartedByAddon = true
        if RTweakzDB.debug then
            print("|cff00ff00RTweakz|r: combat log started (" .. instanceType .. ")")
        end
    elseif not want and logging and RTweakzDB.logStartedByAddon then
        LoggingCombat(false)
        RTweakzDB.logStartedByAddon = false
        if RTweakzDB.debug then
            print("|cff00ff00RTweakz|r: combat log stopped")
        end
    elseif not logging then
        RTweakzDB.logStartedByAddon = false
    end
end

RTweakz.ApplyFPS = ApplyFPS
RTweakz.GetDesiredFPS = GetDesiredFPS
RTweakz.FormatFPS = FormatFPS
RTweakz.UpdateCombatLog = UpdateCombatLog
RTweakz.EnsurePIMacro = EnsurePIMacro

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")

local piEvents = {
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
}

frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if piEvents[event] then
        OnPIMessage(arg1, arg2, event)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        ApplyPendingPIMacro()
        return
    end
    if event == "PLAYER_LOGIN" then
        for k, v in pairs(defaults) do
            if RTweakzDB[k] == nil then
                RTweakzDB[k] = v
            end
        end
    elseif event == "PLAYER_FLAGS_CHANGED" and arg1 ~= "player" then
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        UpdateCombatLog()
    end
    if event == "PLAYER_ENTERING_WORLD" and arg1 then
        -- initial login only; delayed because macros may not be loaded yet
        -- (an empty macro list would make us create a duplicate)
        C_Timer.After(5, function() EnsurePIMacro(true) end)
    end
    ApplyFPS()
end)

local keyMap = {
    out = "fpsOutOfInstance",
    ["in"] = "fpsInInstance",
    rested = "fpsRested",
    afk = "fpsAfk",
}

SLASH_RTWEAKZ1 = "/rtweakz"
SlashCmdList["RTWEAKZ"] = function(msg)
    local cmd, val = msg:match("^(%S+)%s*(.-)%s*$")

    if not cmd then
        print("|cff00ff00RTweakz|r FPS limiter (0 = uncapped)")
        print("  /rtweakz out <fps>     - open world cap (current: " .. FormatFPS(RTweakzDB.fpsOutOfInstance) .. ")")
        print("  /rtweakz in <fps>      - instance cap (current: " .. FormatFPS(RTweakzDB.fpsInInstance) .. ")")
        print("  /rtweakz rested <fps>  - rested area cap (current: " .. FormatFPS(RTweakzDB.fpsRested) .. ")")
        print("  /rtweakz afk <fps>     - AFK cap (current: " .. FormatFPS(RTweakzDB.fpsAfk) .. ")")
        print("  /rtweakz pi            - toggle PI request alert on whispers and party chat")
        print("  /rtweakz pikey <words> - set PI keywords, comma-separated (current: " .. RTweakzDB.piKeywords .. ")")
        print("  /rtweakz pihighlight   - toggle unit frame highlight on PI request")
        print("  /rtweakz pisound <key> - set PI alert sound (current: " .. RTweakzDB.piSound .. ")")
        print("  /rtweakz piready       - toggle: ignore PI requests while PI is on cooldown")
        print("  /rtweakz pimacro       - toggle: keep macro " .. PI_MACRO_NAME .. " targeting the last requester")
        print("  /rtweakz lograid       - toggle auto combat log in raids")
        print("  /rtweakz logdungeon    - toggle auto combat log in dungeons")
        print("  /rtweakz debug         - toggle chat messages on cap changes")
        print("  /rtweakz status        - show current settings and active cap")
        print("  /rtweakz config        - open settings panel")
        return
    end

    cmd = cmd:lower()
    local numVal = tonumber(val)
    local dbKey = keyMap[cmd]

    if dbKey and numVal and numVal >= 0 then
        RTweakzDB[dbKey] = math.floor(numVal)
        print("|cff00ff00RTweakz|r: " .. cmd .. " cap set to " .. FormatFPS(RTweakzDB[dbKey]))
        ApplyFPS()
    elseif cmd == "pi" then
        RTweakzDB.piEnabled = not RTweakzDB.piEnabled
        print("|cff00ff00RTweakz|r: PI request alert " .. (RTweakzDB.piEnabled and "enabled" or "disabled"))
    elseif cmd == "pikey" then
        if val ~= "" then
            RTweakzDB.piKeywords = val
        end
        print("|cff00ff00RTweakz|r: PI keywords: " .. RTweakzDB.piKeywords)
    elseif cmd == "pihighlight" then
        RTweakzDB.piHighlight = not RTweakzDB.piHighlight
        print("|cff00ff00RTweakz|r: PI unit frame highlight " .. (RTweakzDB.piHighlight and "enabled" or "disabled"))
    elseif cmd == "pisound" then
        local sound = val ~= "" and RTweakz.GetPISound(val:lower()) or nil
        if sound then
            RTweakzDB.piSound = sound.key
            if sound.soundKit then PlaySound(sound.soundKit) end
            print("|cff00ff00RTweakz|r: PI sound set to " .. sound.label)
        else
            local keys = {}
            for _, s in ipairs(RTweakz.PISounds) do
                keys[#keys + 1] = s.key
            end
            print("|cff00ff00RTweakz|r: PI sound: " .. RTweakzDB.piSound .. "  (options: " .. table.concat(keys, ", ") .. ")")
        end
    elseif cmd == "piready" then
        RTweakzDB.piOnlyReady = not RTweakzDB.piOnlyReady
        print("|cff00ff00RTweakz|r: ignore PI requests while on cooldown " .. (RTweakzDB.piOnlyReady and "enabled" or "disabled"))
    elseif cmd == "pimacro" then
        RTweakzDB.piMacro = not RTweakzDB.piMacro
        print("|cff00ff00RTweakz|r: PI macro " .. (RTweakzDB.piMacro and "enabled" or "disabled"))
        EnsurePIMacro()
    elseif cmd == "lograid" or cmd == "logdungeon" then
        local key = (cmd == "lograid") and "logRaid" or "logDungeon"
        RTweakzDB[key] = not RTweakzDB[key]
        print("|cff00ff00RTweakz|r: auto combat log in " .. ((cmd == "lograid") and "raids" or "dungeons") .. " "
            .. (RTweakzDB[key] and "enabled" or "disabled"))
        UpdateCombatLog()
    elseif cmd == "debug" then
        RTweakzDB.debug = not RTweakzDB.debug
        print("|cff00ff00RTweakz|r: debug messages " .. (RTweakzDB.debug and "enabled" or "disabled"))
    elseif cmd == "config" then
        if RTweakz.OpenConfig then RTweakz.OpenConfig() end
    elseif cmd == "status" then
        local fps, reason = GetDesiredFPS()
        print("|cff00ff00RTweakz|r: out=" .. FormatFPS(RTweakzDB.fpsOutOfInstance)
            .. "  in=" .. FormatFPS(RTweakzDB.fpsInInstance)
            .. "  rested=" .. FormatFPS(RTweakzDB.fpsRested)
            .. "  afk=" .. FormatFPS(RTweakzDB.fpsAfk))
        print("|cff00ff00RTweakz|r: active=" .. FormatFPS(fps) .. " (" .. reason .. ")  maxFPS cvar=" .. GetCVar("maxFPS"))
        print("|cff00ff00RTweakz|r: PI alert=" .. (RTweakzDB.piEnabled and "on" or "off")
            .. "  keywords=" .. RTweakzDB.piKeywords
            .. "  highlight=" .. (RTweakzDB.piHighlight and "on" or "off")
            .. "  sound=" .. RTweakzDB.piSound
            .. "  onlyReady=" .. (RTweakzDB.piOnlyReady and "on" or "off")
            .. "  macro=" .. (RTweakzDB.piMacro and "on" or "off"))
        print("|cff00ff00RTweakz|r: auto log raid=" .. (RTweakzDB.logRaid and "on" or "off")
            .. "  dungeon=" .. (RTweakzDB.logDungeon and "on" or "off")
            .. "  logging now=" .. (LoggingCombat() and "yes" or "no"))
    else
        print("|cff00ff00RTweakz|r: unknown command — type /rtweakz for help")
    end
end
