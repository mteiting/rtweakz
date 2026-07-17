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

-- Default (non raid-style) party frames live in a frame pool, not global names
local function FindPartyMemberFrame(unit)
    if not (PartyFrame and PartyFrame.PartyMemberFramePool) then
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

local function OnPIMessage(message, sender)
    if not RTweakzDB.piEnabled or not MatchesPIKeyword(message) then
        return
    end
    if sender == FullUnitName("player") then
        return -- own message in party chat
    end
    local name = Ambiguate(sender, "short")
    RaidNotice_AddMessage(RaidWarningFrame, name .. " is requesting Power Infusion!", ChatTypeInfo["RAID_WARNING"])
    PlayPISound()
    print("|cff00ff00RTweakz|r: PI request from " .. name)

    if RTweakzDB.piHighlight then
        local unit = FindGroupUnit(sender)
        local unitFrame = unit and FindUnitFrame(unit)
        if unitFrame then
            HighlightUnitFrame(unitFrame)
        elseif RTweakzDB.debug then
            print("|cff00ff00RTweakz|r: no unit frame to highlight ("
                .. (unit and (unit .. " has no visible default frame") or (sender .. " not found in group")) .. ")")
        end
    end
end

RTweakz.ApplyFPS = ApplyFPS
RTweakz.GetDesiredFPS = GetDesiredFPS
RTweakz.FormatFPS = FormatFPS

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
        OnPIMessage(arg1, arg2)
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
            .. "  sound=" .. RTweakzDB.piSound)
    else
        print("|cff00ff00RTweakz|r: unknown command — type /rtweakz for help")
    end
end
