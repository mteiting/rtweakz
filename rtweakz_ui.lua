local SLIDER_MAX = 240

local function CreateFPSRow(panel, anchor, yOffset, labelText, dbKey, onChanged)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
    label:SetWidth(150)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    local slider = CreateFrame("Slider", nil, panel, "UISliderTemplateWithLabels")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(220, 17)
    slider:SetPoint("LEFT", label, "RIGHT", 16, 0)
    slider:SetMinMaxValues(0, SLIDER_MAX)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    if slider.Low then slider.Low:SetText("0") end
    if slider.High then slider.High:SetText(tostring(SLIDER_MAX)) end
    if slider.Text then slider.Text:SetText("") end

    local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    box:SetSize(48, 20)
    box:SetPoint("LEFT", slider, "RIGHT", 24, 0)
    box:SetNumeric(true)
    box:SetMaxLetters(4)
    box:SetAutoFocus(false)

    local syncing = false

    -- Values above SLIDER_MAX are allowed via the edit box; the slider just pins at max.
    local function SetValue(value)
        value = math.max(0, math.floor(value + 0.5))
        RTweakzDB[dbKey] = value
        syncing = true
        slider:SetValue(math.min(value, SLIDER_MAX))
        box:SetText(value)
        syncing = false
        onChanged()
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if syncing then return end
        SetValue(value)
    end)

    local function CommitBox()
        if syncing then return end
        local value = tonumber(box:GetText())
        if value then
            SetValue(value)
        else
            box:SetText(RTweakzDB[dbKey])
        end
        box:ClearFocus()
    end
    box:SetScript("OnEnterPressed", CommitBox)
    box:SetScript("OnEditFocusLost", CommitBox)

    local function Refresh()
        syncing = true
        slider:SetValue(math.min(RTweakzDB[dbKey], SLIDER_MAX))
        box:SetText(RTweakzDB[dbKey])
        syncing = false
    end

    return { Refresh = Refresh, label = label }
end

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RTweakz")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("FPS limiter — 0 = uncapped. Priority: AFK > instance > rested > open world")

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

    local function UpdateStatus()
        local fps, reason = RTweakz.GetDesiredFPS()
        status:SetText("Active cap: " .. RTweakz.FormatFPS(fps) .. " (" .. reason .. ")")
    end

    local function OnChanged()
        RTweakz.ApplyFPS()
        UpdateStatus()
    end

    local rows = {
        CreateFPSRow(panel, subtitle, -32,  "Open world:",   "fpsOutOfInstance", OnChanged),
        CreateFPSRow(panel, subtitle, -72,  "In instance:",  "fpsInInstance",    OnChanged),
        CreateFPSRow(panel, subtitle, -112, "Rested area:",  "fpsRested",        OnChanged),
        CreateFPSRow(panel, subtitle, -152, "AFK:",          "fpsAfk",           OnChanged),
    }

    local debugCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    debugCheck:SetSize(26, 26)
    debugCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -196)
    debugCheck:SetScript("OnClick", function(self)
        RTweakzDB.debug = self:GetChecked() and true or false
    end)

    local debugLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    debugLabel:SetPoint("LEFT", debugCheck, "RIGHT", 4, 0)
    debugLabel:SetText("Debug: print cap changes to chat")

    status:SetPoint("TOPLEFT", debugCheck, "BOTTOMLEFT", 4, -12)

    panel:SetScript("OnShow", function()
        for _, row in ipairs(rows) do
            row.Refresh()
        end
        debugCheck:SetChecked(RTweakzDB.debug)
        UpdateStatus()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "RTweakz")
    Settings.RegisterAddOnCategory(category)

    RTweakz.OpenConfig = function()
        Settings.OpenToCategory(category:GetID())
    end
end

-- Delay until after SavedVariables are loaded
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    CreateSettingsPanel()
    self:UnregisterAllEvents()
end)
