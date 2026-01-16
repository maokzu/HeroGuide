-- UI/TreeDrawing.lua
-- Handles low-level drawing (Lines and Node Frames)
HeroGuide.UI.Drawing = {}
local Drawing = HeroGuide.UI.Drawing

-- --- LINE DRAWING ---
-- Draws a line between two frames (or points)
function Drawing:DrawLine(parentFrame, startX, startY, endX, endY, thickness, color)
    local line = parentFrame:CreateLine()
    line:SetThickness(thickness or 2)
    
    local r, g, b, a = 1, 1, 1, 0.5
    if color then r,g,b,a = unpack(color) end
    line:SetColorTexture(r, g, b, a)
    
    line:SetStartPoint("TOPLEFT", startX, startY)
    line:SetEndPoint("TOPLEFT", endX, endY)
    
    return line
end

-- Draws orthogonal 3-segment line
function Drawing:DrawManhattanLine(parentFrame, startX, startY, endX, endY, midY, thickness, color)
    local lines = {}
    local r, g, b, a = 0.6, 0.6, 0.6, 0.5
    if color then r,g,b,a = unpack(color) end
    
    local function CreateSeg()
        local l = parentFrame:CreateLine()
        l:SetThickness(thickness or 2)
        l:SetColorTexture(r,g,b,a)
        return l
    end
    
    -- Segment 1: Vertical Down from Parent
    local l1 = CreateSeg()
    l1:SetStartPoint("TOPLEFT", startX, startY)
    l1:SetEndPoint("TOPLEFT", startX, midY)
    table.insert(lines, l1)
    
    -- Segment 2: Horizontal to Child Column
    local l2 = CreateSeg()
    l2:SetStartPoint("TOPLEFT", startX, midY)
    l2:SetEndPoint("TOPLEFT", endX, midY)
    table.insert(lines, l2)
    
    -- Segment 3: Vertical Down to Child
    local l3 = CreateSeg()
    l3:SetStartPoint("TOPLEFT", endX, midY)
    l3:SetEndPoint("TOPLEFT", endX, endY)
    table.insert(lines, l3)
    
    return lines
end

-- Draws Horizontal Fork (Parent Right -> Horizontal -> Vertical -> Horizontal -> Child Left)
-- Actually, Diagram shows: Parent --+--> Child 1
--                                   |
--                                   +--> Child 2
-- Simple 3-segment:
-- 1. Horizontal from Parent Right to MidX (Shared Bus)
-- 2. Vertical along MidX
-- 3. Horizontal from MidX to Child Left
function Drawing:DrawHorizontalFork(parentFrame, startX, startY, endX, endY, midX, thickness, color)
    local lines = {}
    local r, g, b, a = 0.6, 0.6, 0.6, 0.5
    if color then r,g,b,a = unpack(color) end
    
    local function CreateSeg()
        local l = parentFrame:CreateLine()
        l:SetThickness(thickness or 2)
        l:SetColorTexture(r,g,b,a)
        return l
    end
    
    -- Segment 1: Horizontal from Parent
    -- Only draw this ONCE if we are managing it? The Renderer calls this per child.
    -- If we draw per child, we draw overlap. That's fine for now, or we optimize in Renderer.
    -- Let's stick to per-child simple drawing calls.
    
    -- 1. Parent Out (Horizontal)
    -- Actually, if we want a shared bus, we need the logic in Renderer.
    -- If we just draw (Parent -> Child), for a tree it looks like:
    -- Parent --|-- Child
    --          |-- Child
    
    -- Correct Path:
    -- (startX, startY) -> (midX, startY)  <-- Horizontal from Parent
    -- (midX, startY)   -> (midX, endY)    <-- Vertical Bus
    -- (midX, endY)     -> (endX, endY)    <-- Horizontal to Child
    
    -- Segment 1: Right from Parent to Mid X
    local l1 = CreateSeg()
    l1:SetStartPoint("TOPLEFT", startX, startY)
    l1:SetEndPoint("TOPLEFT", midX, startY)
    table.insert(lines, l1)
    
    -- Segment 2: Vertical Bus at Mid X (From Parent Y to Child Y)
    local l2 = CreateSeg()
    l2:SetStartPoint("TOPLEFT", midX, startY)
    l2:SetEndPoint("TOPLEFT", midX, endY)
    table.insert(lines, l2)
    
    -- Segment 3: Right from Mid X to Child
    local l3 = CreateSeg()
    l3:SetStartPoint("TOPLEFT", midX, endY)
    l3:SetEndPoint("TOPLEFT", endX, endY)
    table.insert(lines, l3)
    
    return lines
end

-- --- NODE CREATION ---
-- Creates a single visual node (Box)
function Drawing:CreateNodeFrame(parent, id)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
    f:SetSize(160, 42) -- Standard size
    
    -- Backdrop (Dark Box)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Icon (Left side)
    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetSize(36, 36)
    f.Icon:SetPoint("TOPLEFT", 6, -6) -- Top aligned (approx centered in top 48px)
    f.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Zoom/Crop
    
    -- Text (Name)
    f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.Text:SetPoint("TOPLEFT", f.Icon, "TOPRIGHT", 8, -2)
    f.Text:SetPoint("RIGHT", -5, 0)
    f.Text:SetJustifyH("LEFT")
    f.Text:SetWordWrap(true)
    f.Text:SetText("Unknown Node")
    f.Text:SetTextColor(1, 0.82, 0) -- Gold value default
    
    -- Completed Checkmark (Overlay on Icon)
    f.Check = f:CreateTexture(nil, "OVERLAY", nil, 7)
    f.Check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    f.Check:SetSize(24, 24)
    f.Check:SetPoint("CENTER", f.Icon, "CENTER", 0, 0)
    f.Check:Hide()
    
    -- Interaction Highlight
    f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    
    -- GPS Indicator (Small icon bottom right)
    f.GPSIcon = f:CreateTexture(nil, "OVERLAY")
    f.GPSIcon:SetTexture("Interface\\Minimap\\Tracking\\FlightMaster")
    f.GPSIcon:SetSize(14, 14)
    f.GPSIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.GPSIcon:Hide()
    
    -- Collapse/Expand Indicator (Bottom Center)
    f.CollapseIcon = f:CreateTexture(nil, "OVERLAY")
    f.CollapseIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-UP") -- Default to Expanded (Minus to collapse)
    f.CollapseIcon:SetSize(16, 16)
    f.CollapseIcon:SetPoint("BOTTOM", 0, -6) -- Slightly sticking out? Or inside?
    -- If inside: "BOTTOM", 0, 2. If overlapping edge: "BOTTOM", 0, -8.
    -- Let's put it inside at the bottom edge.
    f.CollapseIcon:SetPoint("BOTTOM", 0, 2)
    f.CollapseIcon:Hide()

    return f
end

-- --- ACCORDION ITEM CREATION ---
function Drawing:CreateAccordionLine(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(140, 20)
    
    -- Background (Alternating strip style, set color later)
    btn.Bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.Bg:SetAllPoints()
    btn.Bg:SetColorTexture(1, 1, 1, 0.05)
    
    -- Small Icon (Generic Bullet or Specific)
    btn.Icon = btn:CreateTexture(nil, "ARTWORK")
    btn.Icon:SetSize(14, 14)
    btn.Icon:SetPoint("LEFT", 2, 0)
    btn.Icon:SetTexture("Interface\\QuestFrame\\UI-Quest-BulletPoint")
    
    -- Text
    btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.Text:SetPoint("LEFT", btn.Icon, "RIGHT", 4, 0)
    btn.Text:SetPoint("RIGHT", -20, 0) -- Leave room for GPS button
    btn.Text:SetJustifyH("LEFT")
    btn.Text:SetWordWrap(false) -- Prevent overlapping lines
    
    -- GPS Button (Right Side)
    btn.GPS = CreateFrame("Button", nil, btn)
    btn.GPS:SetSize(16, 16)
    btn.GPS:SetPoint("RIGHT", 0, 0)
    btn.GPS:SetNormalTexture("Interface\\Minimap\\Tracking\\FlightMaster")
    btn.GPS:GetNormalTexture():SetDesaturated(true)
    btn.GPS:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    btn.GPS:Hide() -- Hidden by default
    
    -- Scripts
    -- GPS Scripts
    btn.GPS:SetScript("OnEnter", function(self) 
        self:GetNormalTexture():SetDesaturated(false) 
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Cliquer pour le GPS", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn.GPS:SetScript("OnLeave", function(self) 
        self:GetNormalTexture():SetDesaturated(true) 
        GameTooltip:Hide()
    end)
    
    -- Main Button Scripts (Tooltip for long text)
    btn:SetScript("OnEnter", function(self)
        if self.Text:IsTruncated() or true then -- Always show for clarity?
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.Text:GetText(), 1, 1, 1, 1, true) -- Wrap in tooltip
            GameTooltip:Show()
        end
        -- Highlight
        self.Bg:SetColorTexture(1, 1, 1, 0.1)
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.Bg:SetColorTexture(1, 1, 1, 0.05)
    end)
    
    return btn
end
