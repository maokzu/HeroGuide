local UI = HeroGuide.UI

local FRAMENAME = "HeroGuideFrame"

function UI:CreateMainFrame()
    if self.MainFrame then return self.MainFrame end
    
    local f = CreateFrame("Frame", FRAMENAME, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(800, 600) -- Large window for tree view
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    f.Title = f:CreateFontString(nil, "OVERLAY")
    f.Title:SetFontObject("GameFontHighlight")
    f.Title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
    f.Title:SetText("HeroGuide V2")
    
    -- ScrollFrame (The Viewport)
    local scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 30)
    
    -- Canvas (The Infinite Map)
    local canvas = CreateFrame("Frame", nil, scrollFrame)
    canvas:SetSize(2000, 2000) -- Initial size, will resize
    scrollFrame:SetScrollChild(canvas)
    
    -- Drag to Scroll Logic (Node Editor Style)
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.panning = true
            local cx, cy = GetCursorPosition()
            self.startX = cx
            self.startY = cy
            self.startH = scrollFrame:GetHorizontalScroll()
            self.startV = scrollFrame:GetVerticalScroll()
            
            self:SetScript("OnUpdate", function(this)
                if not this.panning then return end
                local currX, currY = GetCursorPosition()
                local scale = this:GetEffectiveScale()
                
                -- Calculate Drag Delta
                local dx = (currX - this.startX) / scale
                local dy = (currY - this.startY) / scale
                
                -- Apply to ScrollFrame (Inverted direction: Drag Left -> Scroll Right)
                scrollFrame:SetHorizontalScroll(this.startH - dx)
                scrollFrame:SetVerticalScroll(this.startV + dy) -- Drag Up -> Scroll Value Increases (View Down)
            end)
        end
    end)
    canvas:SetScript("OnMouseUp", function(self)
        self.panning = false
        self:SetScript("OnUpdate", nil)
    end)
    canvas:SetScript("OnHide", function(self)
        self.panning = false
        self:SetScript("OnUpdate", nil)
    end)
    
    self.MainFrame = f
    self.Canvas = canvas
    self.ScrollFrame = scrollFrame
    self.NodePool = {}
    self.LinePool = {}
    self.ViewScale = 1.0
    
    self:CreateToolbar(f)
    
    return f
end

function UI:CreateToolbar(parent)
    local tb = CreateFrame("Frame", nil, parent)
    tb:SetSize(100, 30)
    tb:SetPoint("TOPRIGHT", -10, -30) -- Top Right, under Title
    
    -- FORCE Z-INDEX: Must be higher than ScrollFrame (and its Canvas child)
    -- ScrollFrame usually inherits parent level. We add +10 to be safe.
    tb:SetFrameLevel(parent:GetFrameLevel() + 20)
    
    local function CreateToolBtn(name, icon, onClick)
        local btn = CreateFrame("Button", nil, tb)
        btn:SetSize(24, 24)
        btn:SetNormalTexture(icon)
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        btn:SetScript("OnClick", onClick)
        return btn
    end
    
    -- Zoom In
    local btnZoomIn = CreateToolBtn("ZoomIn", "Interface\\Buttons\\UI-PlusButton-UP", function()
        -- print("Zoom In Clicked")
        self:SetViewScale((self.ViewScale or 1.0) + 0.1)
    end)
    btnZoomIn:SetPoint("RIGHT", 0, 0)
    
    -- Zoom Out
    local btnZoomOut = CreateToolBtn("ZoomOut", "Interface\\Buttons\\UI-MinusButton-UP", function()
        -- print("Zoom Out Clicked")
        self:SetViewScale((self.ViewScale or 1.0) - 0.1)
    end)
    btnZoomOut:SetPoint("RIGHT", btnZoomIn, "LEFT", -2, 0)
    
    -- Recenter (Home Icon is safer/more standardized)
    local btnCenter = CreateToolBtn("Center", "Interface\\Buttons\\UI-HomeButton", function()
        self:CenterView()
    end)
    btnCenter:SetPoint("RIGHT", btnZoomOut, "LEFT", -5, 0)
    -- Ensure it's on top
    btnCenter:SetFrameLevel(btnZoomOut:GetFrameLevel() + 1)
    
    -- Add Tooltip for Center
    btnCenter:SetScript("OnEnter", function(self) 
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Recentrer la vue")
        GameTooltip:Show()
    end)
    btnCenter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    self.Toolbar = tb
end

function UI:SetViewScale(scale)
    scale = math.max(0.5, math.min(2.0, scale)) -- Clamp 0.5 to 2.0
    -- print("Setting Scale: " .. scale)
    self.ViewScale = scale
    self.Canvas:SetScale(scale)
end

function UI:CenterView()
    if not self.RootNode then return end
    
    -- Reset Scale to 1.0? User might want to keep zoom.
    -- Let's keep zoom but center on Root.
    
    local root = self.RootNode
    local viewW = self.ScrollFrame:GetWidth() / self.ViewScale
    local viewH = self.ScrollFrame:GetHeight() / self.ViewScale
    
    -- Root Pos
    local x = root._x
    local y = -(root._y) -- Scroll is positive, Y coords are weird.
    -- Actually LayoutEngine uses Downwards stacking now?
    -- Wait, node._y is now derived from (startV - height). It's likely negative?
    -- No, I swapped correction to "currentY - height". StartY was -10. 
    -- So node._y is negative.
    -- ScrollFrame VerticalScroll is Positive (0 to ContentHeight).
    -- To show y=-100, we scroll to 100? Depends on anchor.
    -- Anchor is TOPLEFT.
    -- So yes, ScrollV should be positive equivalent of negative Y.
    
    -- Target Scroll
    -- Center the node in View
    local targetX = x - (viewW / 2) + (root._treeWidth or 220)/2
    local targetY = (-root._y) - (viewH / 2) -- Invert Y for Scroll
    
    self.ScrollFrame:SetHorizontalScroll(math.max(0, targetX))
    self.ScrollFrame:SetVerticalScroll(math.max(0, targetY))
end

-- --- POOL MANAGEMENT ---
function UI:AcquireNode(index)
    if not self.NodePool[index] then
        self.NodePool[index] = HeroGuide.UI.Drawing:CreateNodeFrame(self.Canvas, index)
    end
    return self.NodePool[index]
end

function UI:ResetPools()
    for _, node in pairs(self.NodePool) do node:Hide() end
    -- Lines are tricky because CreateLine returns a texture object that can't be purely hidden/shown in a pool array easily?
    -- Actually they can.
    if self.Canvas.lines then
        for _, line in ipairs(self.Canvas.lines) do line:Hide() end
    end
    self.Canvas.lines = {} -- Reset active list
end

-- --- RENDER LOGIC ---
-- --- RENDER LOGIC ---
function UI:RenderTree(data)
    local f = self:CreateMainFrame()
    
    -- Smart Visibility: Only force show if requested (New tracking or Login)
    if HeroGuide.ForceOpen then
        f:Show()
        HeroGuide.ForceOpen = false
    end
    -- If frame is hidden and no force open, we perform the render (update content) but don't show it.
    -- This fixes the "Jump opens window" bug on CRITERIA_UPDATE.
    f.Title:SetText(data.title)
    
    -- Clear previous
    self:ResetPools()
    
    -- RECONSTRUCTION STEP:
    -- Separate Graph Children (Sub-Achieves) from Criteria (Tasks)
    
    -- We need persistent state (expanded) to survive re-renders.
    -- We can match nodes by Name or ID.
    local oldExpanded = {}
    if self.RootNode then
        local function SaveState(node)
            if node.expanded then oldExpanded[node.id or node.name] = true end
            if node.children then for _, c in ipairs(node.children) do SaveState(c) end end
        end
        SaveState(self.RootNode)
    end

    local root = { 
        name = data.title, 
        icon = data.icon, 
        id = data.id,
        children = {}, 
        internalCriteria = {},
        _x=0, _y=0,
        height = 80, -- Base height
        isRoot = true
    }
    
    -- Sort input nodes into Graph Children vs Internal Criteria
    local rawChildren = {}

        
        if node.childAchievementID or node.renderAsNode then
             -- It's a Sub-Achievement OR Important Quest -> Graph Node
             table.insert(rawChildren, node)
        else
             -- It's a simple task -> Internal Criteria
             table.insert(root.internalCriteria, node)
        end
    end
    
    -- Apply Grouping to Graph Children
    root.children = self:ProcessGroupCompleted(rawChildren)
    
    -- Recursively apply 'expanded' state and height
    local function RestoreState(n)
        if oldExpanded[n.id or n.name] then
            n.expanded = true
            
            if n.internalCriteria then
                 -- Calculate height based on criteria
                 local count = #n.internalCriteria
                 local todo = 0
                 for _, c in ipairs(n.internalCriteria) do if not c.completed then todo = todo + 1 end end
                 local done = #n.internalCriteria - todo
                 
                 local lines = todo
                 if done > 0 then lines = lines + 1 end 
                 if n.showDone then lines = lines + done end
                 
                 n.height = 42 + (lines * 20) + 10 
            else
                 n.height = 42
            end
        else
            n.height = 42
        end
        
        if n.children then
             for _, c in ipairs(n.children) do 
                RestoreState(c)
             end
        end
    end
    RestoreState(root)
    
    self.RootNode = root

    -- Calculate Layout
    local totalW, totalH = HeroGuide.UI.Layout:Process(root)
    
    -- Draw Root
    self:DrawNodeRecursive(root, 1)
    
    -- Center Canvas
    local viewW = self.ScrollFrame:GetWidth()
    local targetX = root._x - (viewW / 2)
    
    self.Canvas:SetSize(math.max(viewW, totalW + 200), math.max(600, totalH + 200))
    self.ScrollFrame:SetHorizontalScroll(math.max(0, targetX))
end

function UI:DrawNodeRecursive(node, poolIndex)
    local btn = self:AcquireNode(poolIndex)
    btn:Show()
    
    -- Position
    btn:SetPoint("TOPLEFT", self.Canvas, "TOPLEFT", node._x, node._y) -- Y is Top
    btn:SetSize(220, node.height or 42) -- Updated to Horizontal Layout Width
    
    -- Content
    btn.Text:SetText(node.name)
    if node.icon then btn.Icon:SetTexture(node.icon) end
    
    -- Status & Borders
    if node.completed then
        btn.Check:Show()
        btn.Text:SetTextColor(0.5, 0.5, 0.5)
        btn:SetBackdropBorderColor(0, 1, 0, 0.8)
    else
        btn.Check:Hide()
        btn.Text:SetTextColor(1, 0.82, 0)
        
        if node.isMeta or (node.children and #node.children > 0) then
             btn:SetBackdropBorderColor(1, 0.82, 0, 0.8) -- Gold for Meta/Graph
        elseif node.renderAsNode then
             btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) -- Silver for Quest Node
        else
             btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) -- Silver for Leaf
        end
    end

    -- Collapse Icon Logic
    -- Collapse Icon Logic
    if node.children and #node.children > 0 then
        btn.CollapseIcon:Show()
        if node.collapsed then
            btn.CollapseIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
        else
            btn.CollapseIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")
        end
    else
        btn.CollapseIcon:Hide()
    end
    
    -- Accordion Logic
    if node.internalCriteria and #node.internalCriteria > 0 then
        -- Show "Expand" indicator?
        -- Maybe the border or separate icon. 
        -- Let's use the Click to expand.
    end
    
    -- Internal List Rendering (Custom Frame inside Button?)
    if not btn.ContentFrame then
        btn.ContentFrame = CreateFrame("Frame", nil, btn)
        btn.ContentFrame:SetPoint("TOPLEFT", 10, -45)
        btn.ContentFrame:SetPoint("BOTTOMRIGHT", -10, 5)
        
        -- Block clicks in the content area from triggering the Parent's Toggle
        btn.ContentFrame:EnableMouse(true)
        btn.ContentFrame:SetScript("OnMouseDown", function() end) 
    end
    
    -- Clear previous content lines
    if btn.ContentLines then for _, l in pairs(btn.ContentLines) do l:Hide() end end
    btn.ContentLines = btn.ContentLines or {}
    
    if node.expanded and node.internalCriteria then
        local y = 0
        
        -- Helper: Add styled line
        local function AddLine(text, color, onClick, showGPS, gpsData)
            local l = btn.ContentLines[y+1]
            if not l then
                 l = HeroGuide.UI.Drawing:CreateAccordionLine(btn.ContentFrame)
                 btn.ContentLines[y+1] = l
            end
            l:SetPoint("TOPLEFT", 0, -(y * 20))
            l:Show()
            
            l.Text:SetText(text)
            if color then l.Text:SetTextColor(unpack(color)) end
            
            -- Row Interaction
            if onClick then 
                l:SetScript("OnClick", onClick)
                l:EnableMouse(true)
            else 
                l:SetScript("OnClick", nil)
                l:EnableMouse(false)
            end
            
            -- GPS Button
            if showGPS and gpsData then
                l.GPS:Show()
                l.GPS:SetScript("OnClick", function() self:SetWaypoint(gpsData) end)
            else
                l.GPS:Hide()
            end
            
            y = y + 1
        end
        
        -- Sort: Todo first
        local todo = {}
        local done = {}
        for _, c in ipairs(node.internalCriteria) do
            if c.completed then table.insert(done, c) else table.insert(todo, c) end
        end
        
        for _, c in ipairs(todo) do
            local hasGPS = (c.coords ~= nil)
            local rowClick = nil
            if hasGPS then rowClick = function() self:SetWaypoint(c) end end
            
            AddLine(c.name, {1, 1, 1}, rowClick, hasGPS, c)
        end
        
        if #done > 0 then
            local headerText = (node.showDone and "[-] Validés" or "[+] Validés ("..#done..")")
            AddLine(headerText, {0, 1, 0}, function() 
                node.showDone = not node.showDone
                -- Trigger Layout Refresh
                self:RenderTree({title=self.RootNode.name, nodes=self.RootNode.children, id=self.RootNode.id}) 
                -- Wait, this resets the tree logic? 
                -- We constructed RootNode manually. We should just re-call Layout and Draw.
                -- But RestoreState is called in RenderTree.
                -- Ideally we separate Data Build from Draw.
                -- For now, Quick Refresh:
                self:RefreshLayout()
            end)
            
            if node.showDone then
                for _, c in ipairs(done) do
                    AddLine(c.name, {0.5, 0.5, 0.5}, nil, false)
                end
            end
        end
    end

    
    -- Header Button (Invisible, handles Node Toggling)
    if not btn.Header then
        btn.Header = CreateFrame("Button", nil, btn)
        btn.Header:SetPoint("TOPLEFT", 0, 0)
        btn.Header:SetPoint("TOPRIGHT", 0, 0)
        btn.Header:SetHeight(40) -- Active area for toggling
        -- Debug: btn.Header:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="", tile=false}) 
    end
    
    -- Click Handler (MOVED TO HEADER)
    btn.Header:SetScript("OnClick", function()

        
        -- Sticky Scroll Logic: Capture old Y Position (Visual) relative to Screen
        -- We want the clicked node to remain at the same Screen Y.
        -- Screen Y = (Node_Y - ScrollOffset) * Scale
        -- If Node_Y changes by dY, we must adjust ScrollOffset by dY to keep Screen Y constant.
        -- (NewNodeY - NewScroll) = (OldNodeY - OldScroll)
        -- NewScroll = NewNodeY - OldNodeY + OldScroll
        
        local oldY = node._y
        local oldScroll = self.ScrollFrame:GetVerticalScroll() * self.ViewScale -- Scroll is in unscaled units? No, Scroll is applied to Canvas anchor.
        -- Wait, ScrollFrame works in Canvas units usually.
        oldScroll = self.ScrollFrame:GetVerticalScroll()
        
        local needsRefresh = false
        
        if node.internalCriteria and #node.internalCriteria > 0 then
            -- Leaf Toggle
            node.expanded = not node.expanded
            needsRefresh = true
            

        elseif node.children and #node.children > 0 and (not node.childAchievementID or node.subLoaded) then
            node.collapsed = not node.collapsed
            needsRefresh = true
            
        elseif node.childAchievementID then
             -- Lazy Load Sub-Achievement
             -- If we have existing children (e.g. SourceQuests), we MERGE.
             if not node.subLoaded then

                 local res = HeroGuide:FetchCriteria(node.childAchievementID)
                 
                 -- Process result: Split into Graph Children vs Internal Criteria
                 -- RenderTree logic does this splitting. Here we emulate it locally or just append to children?
                 -- For simplicity and current bug fix: Append all to children.
                 -- Ideally we should re-run ProcessGroupCompleted?
                 
                 node.children = node.children or {}
                 
                 -- Merge fetched nodes
                 local combined = {}
                 -- Keep existing (e.g. SQs)
                 for _, c in ipairs(node.children) do table.insert(combined, c) end
                 
                 if res then
                     for _, rNode in ipairs(res) do
                         table.insert(combined, rNode)
                         -- rNode.parent = node 
                     end
                 end
                 
                 -- Apply Grouping (Validés (X))
                 node.children = self:ProcessGroupCompleted(combined)
                 node.subLoaded = true
             end
             
             node.collapsed = false
             needsRefresh = true
                 

        elseif node.hasGPS then
            self:SetWaypoint(node)
        end
        
        if needsRefresh then
            self:RefreshLayout()
            
            -- Apply Stickiness
            -- Layout operates with Negative Y (Downwards).
            -- Scroll works with Positive (Downwards).
            -- Coordinate Mapping: Canvas Y = node._y.
            -- ScrollFrame View Top = -VerticalScroll.
            -- Visual Y = node._y - (-VerticalScroll) = node._y + VerticalScroll.
            -- We want NewVisualY == OldVisualY
            -- NewNodeY + NewScroll = OldNodeY + OldScroll
            -- NewScroll = OldNodeY - NewNodeY + OldScroll
            
            -- Wait. ScrollFrame:SetVerticalScroll(val) sets the offset.
            -- If Scroll=0, View Top is at Canvas Y=0.
            -- If Scroll=100, View Top is at Canvas Y=-100.
            -- So yes, Scroll is effectively Positive magnitude of Negative Y.
            
            -- Let's trace direction:
            -- If Node moves UP (e.g. -500 to -400), NewY > OldY.
            -- Old (-500) - New (-400) = -100.
            -- Scroll should reduce by 100.
            -- NewScroll = -100 + OldScroll. (Scroll Up). Correct.
            
            -- If Node moves DOWN (-400 to -500), NewY < OldY.
            -- Old (-400) - New (-500) = +100.
            -- Scroll should increase by 100. (Scroll Down). Correct.
            
            if node._y and oldY then
                 local delta = oldY - node._y -- (-500) - (-400) = -100
                 -- Actually, ScrollFrame checks bounds. Clamp?
                 local newS = oldScroll + delta 
                 -- print("Sticky: OldY="..oldY.." NewY="..node._y.." Delta="..delta.." OldS="..oldScroll.." NewS="..newS)
                 
                 self.ScrollFrame:SetVerticalScroll(newS)
            end
        end
    end)
    
    -- Pass mouse events from main frame to header if needed? No, separating them is better.
    -- Ensure main frame doesn't eat clicks intended for Header?
    -- btn is a Button, so it captures clicks. We should disable its click handling or make it a Frame.
    -- But CreateNodeFrame makes it a Button.
    -- Let's just disable its script.
    btn:SetScript("OnClick", nil)
    btn:EnableMouse(true) -- Still needs to block World Clicks? Or should we make it purely visual?
    -- If we keep it EnableMouse(true), it blocks walk-clicks.
    -- But since we took away OnClick, it won't do anything.
    -- However, we want the CONTENT AREA to be handled by ContentFrame.
    -- And HEADER AREA by Header.
    -- So btn can just sit there.
    
    -- Draw Lines to Children (Recursion)
    if node.children and not node.collapsed then
        -- Horizontal Layout Connection
        
        -- Parent Anchor Point: Right Center
        -- Node X is Left. Width is 220 (Config in LayoutEngine, hardcoded here as fallback or read?)
        local nodeWidth = 220 -- Match LayoutEngine Config
        local myX = node._x + nodeWidth
        local myY = node._y - (node.height / 2) -- Center Vertical
        
        for i, child in ipairs(node.children) do
            -- Child Anchor Point: Left Center
            local childX = child._x
            local childY = child._y - (child.height / 2)
            
            -- Mid Point for the "Fork" or "Bus"
            -- We want a vertical bar at mid-distance
            local midX = (myX + childX) / 2
            
            -- Draw Fork Line
            local lines = HeroGuide.UI.Drawing:DrawHorizontalFork(
                self.Canvas, 
                myX, myY, 
                childX, childY, 
                midX,
                2, {0.6, 0.6, 0.6, 0.6}
            )
            for _, l in ipairs(lines) do table.insert(self.Canvas.lines, l) end
            
            poolIndex = self:DrawNodeRecursive(child, poolIndex + 1)
        end
    end
    
    return poolIndex
end

function UI:RefreshLayout()
    -- Recalculate heights
    local function UpdateHeights(n)
        if n.expanded and n.internalCriteria then
             local todo = 0
             for _, c in ipairs(n.internalCriteria) do if not c.completed then todo = todo + 1 end end
             local done = #n.internalCriteria - todo
             local lines = todo
             if done > 0 then lines = lines + 1 end
             if n.showDone then lines = lines + done end
             n.height = 42 + (lines * 20) + 10
        else
             n.height = 42
        end
        if n.children then for _, c in ipairs(n.children) do UpdateHeights(c) end end
    end
    UpdateHeights(self.RootNode)
    
    -- Re-run Layout
    -- Important: If node is collapsed, we should temporarily pretend it has no children?
    -- LayoutEngine doesn't toggle. 
    -- Let's just modify LayoutEngine slightly or manipulate data?
    -- Simpler: TreeRenderer uses 'if node.children and not node.collapsed'.
    -- But Layout::CalculateTreeMetrics recurses blindly.
    -- We need to pass the 'collapsed' logic to Layout or modify structure.
    -- Dynamic modification:
    -- If collapsed, hide children from Layout logic?
    -- Or update LayoutEngine to check 'collapsed'.
    
    local totalW, totalH = HeroGuide.UI.Layout:Process(self.RootNode)
    
    -- Re-draw
    self:ResetPools()
    self:DrawNodeRecursive(self.RootNode, 1)
    
    -- Canvas Resize
    local viewW = self.ScrollFrame:GetWidth()
    self.Canvas:SetSize(math.max(viewW, totalW + 200), math.max(600, totalH + 200))
end

function UI:SetWaypoint(node)
    if not node.coords then return end
    if not TomTom then print("TomTom missing"); return end
    
    -- Extract Coords (Same logic as before)
    -- ... (Simplified for brevity, assuming Format 1 usually from our Bridge)
    -- We can reuse the smart logic from previous version or minimal version:
    
    local pt = nil
    if node.coords[1] and type(node.coords[1]) == "table" then pt = node.coords[1]
    elseif type(node.coords) == "table" then
        for k, v in pairs(node.coords) do
            if type(v) == "table" then pt = v[1]; break end
        end
    end
    
    if pt then
        local x, y, m = pt[1], pt[2], pt[3]
        if x > 1 then x=x/100; y=y/100 end
        TomTom:AddWaypoint(m, x, y, { title = node.name })
        print("|cff00ff00[HeroGuide]|r GPS set for: " .. node.name)
    end
end

-- HELPER: Group Completed Graph Nodes
function UI:ProcessGroupCompleted(nodes)
    local active = {}
    local completed = {}
    
    for _, n in ipairs(nodes) do
        if n.completed and (n.childAchievementID or n.renderAsNode) then
            table.insert(completed, n)
        else
            table.insert(active, n)
        end
    end
    
    if #completed > 0 then
        -- Create Virtual Group Node
        local groupNode = {
            name = "Validés (" .. #completed .. ")",
            icon = "Interface\\RaidFrame\\ReadyCheck-Ready",
            children = completed, -- These will be hidden unless this group is expanded
            collapsed = true,     -- Start collapsed
            isMeta = true,        -- Treat as graph parent
            isVirtual = true,     -- Tag for potential special handling
            height = 42
        }
        table.insert(active, groupNode)
    end
    
    return active
end



