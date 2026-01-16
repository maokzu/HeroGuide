-- Minimap Button for HeroGuide
-- Handles creation, positioning, and interaction of the minimap icon.

local addonName, addon = ...
local UI = HeroGuide.UI

-- Default Configuration
local defaultDB = {
    minimapPos = 45, -- Angle
    hideMinimap = false
}

local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Map02" -- Rolled Map Icon

function UI:CreateMinimapButton()
    if UI.MinimapButton then return end

    local btn = CreateFrame("Button", "HeroGuideMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetSize(31, 31)
    btn:SetFrameLevel(8) -- Ensure visibility above map but below tooltips
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- Icon Texture (rounded style with mask)
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    
    -- Standard Minimap Border
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", 0, 0)
    
    -- Highlight
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn.Icon = icon

    -- Interactions
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
             if HeroGuide.UI.MainFrame then
                if HeroGuide.UI.MainFrame:IsShown() then
                    HeroGuide.UI.MainFrame:Hide()
                else
                    HeroGuide.UI.MainFrame:Show()
                end
            else
                -- Try to find one if the events missed it
                -- Silent scan first...
                if HeroGuide.ScanTracked then 
                    HeroGuide:ScanTracked(true) -- Force open on manual click
                end
                
                -- Check again immediately (BuildGuide is synchronous mostly)
                if HeroGuide.UI.MainFrame and HeroGuide.UI.MainFrame:IsShown() then
                     -- Success, it opened
                else
                     print("|cffff0000[HeroGuide]|r Still no active guide found. Please track an achievement in the standard UI.")
                end
            end
        end
    end)
    
    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("HeroGuide")
        GameTooltip:AddLine("Click Left to Toggle Window", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Draggable Logic (Circular)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    
    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self.isDragging = true
        self:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local px, py = Minimap:GetCenter()
            
            x = x / scale
            y = y / scale
            
            local dx, dy = x - px, y - py
            local angle = math.deg(math.atan2(dy, dx))
            
            HeroGuideDB.minimapPos = angle
            UI:UpdateMinimapButtonPosition()
        end)
    end)
    
    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    UI.MinimapButton = btn
    UI:UpdateMinimapButtonPosition()
end

function UI:UpdateMinimapButtonPosition()
    if not UI.MinimapButton then return end
    
    local angle = HeroGuideDB.minimapPos or 45
    -- Standard Radius for circular minimap
    local radius = 80
    local r_rad = math.rad(angle)
    
    local x = math.cos(r_rad) * radius
    local y = math.sin(r_rad) * radius
    
    UI.MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Initialization
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, loadedName)
    if loadedName == "HeroGuide" then
        HeroGuideDB = HeroGuideDB or defaultDB
        if HeroGuideDB.minimapPos == nil then HeroGuideDB.minimapPos = 45 end
        
        UI:CreateMinimapButton()
    end
end)
