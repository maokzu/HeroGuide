-- UI/LayoutEngine.lua
-- Calculates X,Y coordinates for a Horizontal Tree structure (Left -> Right).

HeroGuide.UI.Layout = {}
local Layout = HeroGuide.UI.Layout

local NODE_WIDTH = 250 -- Wider nodes for horizontal text legibility? Or standard 180? Diagram shows wide boxes.
local NODE_HEIGHT_BASE = 60 -- Min height
local COL_GAP = 50 -- Horizontal Gap between Parent and Child
local ROW_GAP = 15 -- Vertical Gap between siblings

-- --- METRICS & CONFIG ---
-- Adjust these to tune the look
Layout.Config = {
    NodeWidth = 220,
    NodeHeight = 42, -- Default if not specified
    DepthGap = 50, -- Space between columns
    SiblingGap = 5, -- Tight vertical spacing to reduce parent gaps
}

-- Check if a node should display its children as a grid (many leaves)
function Layout:IsGridNode(node)
    -- For Horizontal layout, "Grid" implies a block of small boxes?
    -- The user diagram shows "Sous haut fait" -> "Objectif".
    -- "Objectif" boxes seem stacked vertically.
    -- Let's stick to pure tree first. If we need grid later (e.g. 4x4 icons), we can add it.
    -- For now, disable special Grid logic to match the clean diagram.
    return false
end

-- 1. Calculate Subtree Heights (Vertical Size)
function Layout:CalculateMetrics(node)
    local cfg = self.Config
    local myHeight = node.height or 42 -- This is the node's individual display height (Accordion)
    
    -- If collapsed or no children, size is just me
    if not node.children or #node.children == 0 or node.collapsed then
        node._treeHeight = myHeight
        node._treeWidth = cfg.NodeWidth
        return
    end
    
    -- Calculate Children Total Height
    local childrenHeight = 0
    for i, child in ipairs(node.children) do
        self:CalculateMetrics(child)
        childrenHeight = childrenHeight + child._treeHeight
    end
    
    -- Add Gaps
    if #node.children > 1 then
        childrenHeight = childrenHeight + ((#node.children - 1) * cfg.SiblingGap)
    end
    
    -- The subtree height is the MAX of (My Height) vs (Children Block Height)
    -- Usually Children Block is taller.
    node._treeHeight = math.max(myHeight, childrenHeight)
    node._treeWidth = cfg.NodeWidth -- We only track specific width, total width is separate
end

-- 2. Assign Positions (Recursive)
-- x: Current column X
-- y: Top Y of the available space for this subtree
function Layout:AssignPositions(node, x, y)
    local cfg = self.Config
    
    -- My Position depends on my children's positions? 
    -- Standard Reingold-Tilford: Parent Y is mean of Children Y.
    
    node._x = x
    
    local myDisplayHeight = node.height or 42
    
    if not node.children or #node.children == 0 or node.collapsed then
        -- No children: I'm just at Y.
        -- But wait, Y passed in is the "Top" of the slot.
        -- Center me in my slot? 
        -- If I am a leaf, my _treeHeight is my display height.
        node._y = y -- Top alignment of slot
        return
    end
    
    -- Position Children
    local currentY = y
    
    -- If my subtree is taller than my children (rare, e.g. huge accordion parent, tiny child),
    -- we might need to center children? standard is usually children drive the height.
    
    -- If (Children Block) > (My Height), I should be centered relative to the block.
    -- If (My Height) > (Children Block), Children should be centered relative to me?
    -- Let's assume Children Block defines the span.
    
    local childX = x + cfg.NodeWidth + cfg.DepthGap
    
    for _, child in ipairs(node.children) do
        self:AssignPositions(child, childX, currentY)
        currentY = currentY - (child._treeHeight + cfg.SiblingGap) -- Move Down
    end
    
    -- Top-Aligned Layout (Compact)
    -- Align Parent with the First Child (Top of the block)
    -- This removes the void above the parent.
    
    -- node._y should be the start Y passed to us.
    -- However, we passed 'currentY=y' to the first child.
    -- So 'firstChild._y' should be 'y'.
    -- Let's just use the calculated top of the first child to be safe, or just 'y'.
    
    local firstChild = nil
    if node.children and #node.children > 0 then
        firstChild = node.children[1]
    end
    
    if firstChild then
         node._y = firstChild._y
    else
         -- No children, just use the passed Y (Top of available space)
         node._y = y
    end
    
    -- Center logic REMOVED to satisfy "Avoid widening empty zone"
    -- local botY = lastChild._y - (lastChild.height or 42)
    -- local blockCenterY = (topY + botY) / 2
    -- node._y = blockCenterY + (myDisplayHeight / 2)
    
    -- Correction: "AssignPositions" usually receives the "Bounding Box Top".
    -- But since we calculate Y based on children, we might drift from the 'y' passed in?
    -- No, 'y' passed sets the start of the stack.
    -- If we move Parent Y, we don't change the stack.
end

function Layout:Process(rootNode)
    -- 1. Metrics
    self:CalculateMetrics(rootNode)
    
    -- 2. Positions (Start at 0, 0)
    -- We pass Y=0 as Top. Code goes downwards (negative Y) usually in WoW.
    -- Or we use Positive Y and flip later. Let's use standard: Y decreases downwards.
    
    -- Initial call:
    -- To keep Root at Top-Left (User diagram), we might want Root._y = 0.
    -- If we use the "Center Parent" logic, Root Y will drop down to middle of huge tree.
    -- User Diagram: "Haut fait suivie" is Top Left? Or Middle Left?
    -- Diagram shows it roughly middle of the 3 sub-items.
    -- So "Centered Parent" is correct.
    
    self:AssignPositions(rootNode, 10, -10) -- Padding
    
    -- 3. Return total size
    -- Max X is easy (Depth * (Width+Gap))
    -- Max Height is Root._treeHeight
    
    local function GetMaxX(node)
        local max = node._x + (node.height and self.Config.NodeWidth or 0)
        if node.children and not node.collapsed then
            for _, c in ipairs(node.children) do
                local m = GetMaxX(c)
                if m > max then max = m end
            end
        end
        return max
    end
    
    local totalW = GetMaxX(rootNode) + 100
    local totalH = rootNode._treeHeight + 100
    
    return totalW, totalH
end
