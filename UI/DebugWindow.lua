-- Debug Window for HeroGuide
-- Allows copying of diagnostic dumps

HeroGuide.Debug = {}
local DBG = HeroGuide.Debug

local LOG_WINDOW_NAME = "HeroGuideDebugFrame"

function DBG:CreateFrame()
    if self.Frame then return self.Frame end
    
    local f = CreateFrame("Frame", LOG_WINDOW_NAME, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(600, 500)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    f.Title = f:CreateFontString(nil, "OVERLAY")
    f.Title:SetFontObject("GameFontHighlight")
    f.Title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
    f.Title:SetText("HeroGuide Logs")
    
    -- EditBox within a ScrollFrame for large text
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(550)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    
    scrollFrame:SetScrollChild(editBox)
    
    self.Frame = f
    self.EditBox = editBox
    
    -- Clear Button
    local bClear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    bClear:SetSize(80, 22)
    bClear:SetPoint("BOTTOMLEFT", 10, 10)
    bClear:SetText("Clear")
    bClear:SetScript("OnClick", function() 
        DBG:Clear()
    end)
    
    return f
end

function DBG:Show()
    self:CreateFrame()
    self.Frame:Show()
end

function DBG:Toggle()
    if self.Frame and self.Frame:IsShown() then
        self.Frame:Hide()
    else
        self:Show()
    end
end

function DBG:Log(text)
    -- Also print to chat for visibility? maybe regular print is too spammy now.
    -- Just ensure window is created (but not necessarily shown, to avoid popping up randomly)
    if not self.Frame then self:CreateFrame() self.Frame:Hide() end
    
    local current = self.EditBox:GetText() or ""
    -- Append new line
    local newText = text .. "\n"
    self.EditBox:SetText(current .. newText)
    
    -- Auto-scroll to bottom?
    -- This is tricky in vanilla/retail mix, but setting cursor pos might work
    -- self.EditBox:SetCursorPosition(string.len(current .. newText))
end

function DBG:Clear()
    if self.EditBox then self.EditBox:SetText("") end
end

-- Slash Command to open
SLASH_HEROGUIDE_DEBUG1 = "/hg_debug"
SlashCmdList["HEROGUIDE_DEBUG"] = function()
    DBG:Toggle()
end
