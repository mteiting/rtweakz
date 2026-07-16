RTweakz = RTweakz or {}

local defaults = {
    fpsOutOfInstance = 60,
    fpsInInstance = 144,
    fpsRested = 45,
    fpsAfk = 30,
    debug = false,
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

RTweakz.ApplyFPS = ApplyFPS
RTweakz.GetDesiredFPS = GetDesiredFPS
RTweakz.FormatFPS = FormatFPS

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")

frame:SetScript("OnEvent", function(self, event, arg1)
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
    local cmd, val = msg:match("^(%S+)%s*(%S*)$")

    if not cmd then
        print("|cff00ff00RTweakz|r FPS limiter (0 = uncapped)")
        print("  /rtweakz out <fps>     - open world cap (current: " .. FormatFPS(RTweakzDB.fpsOutOfInstance) .. ")")
        print("  /rtweakz in <fps>      - instance cap (current: " .. FormatFPS(RTweakzDB.fpsInInstance) .. ")")
        print("  /rtweakz rested <fps>  - rested area cap (current: " .. FormatFPS(RTweakzDB.fpsRested) .. ")")
        print("  /rtweakz afk <fps>     - AFK cap (current: " .. FormatFPS(RTweakzDB.fpsAfk) .. ")")
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
    else
        print("|cff00ff00RTweakz|r: unknown command — type /rtweakz for help")
    end
end
