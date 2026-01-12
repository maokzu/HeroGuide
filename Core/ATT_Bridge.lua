-- Interface propre avec AllTheThings
-- Basée sur-- ATT Bridge: Connects HeroGuide to AllTheThings Data
HeroGuide.Bridge = {}

-- Local reference to Debug Logger
local function dprint(msg)
    if HeroGuide.Debug and HeroGuide.Debug.Log then
        HeroGuide.Debug:Log(msg)
    else
        print(msg) 
    end
end


-- Dedicated Quest Lookup
function HeroGuide.Bridge:GetQuestInfo(questID)
    local att = _G["AllTheThings"]
    
    -- 1. Try Cache (Global cache? No, we don't have one here. Should we add it? No, keeping it simple.)
    
    -- 2. Try ATT Strict Match
    if att and att.SearchForField then
        local results = att.SearchForField("questID", questID)
        if results then
            for _, res in ipairs(results) do
                if res.questID == questID then
                    local info = self:ParseData(res)
                    -- Verify Name is not Unknown
                    if info.name == "Unknown" or info.name == nil then
                         local WoWName = C_QuestLog.GetTitleForQuestID(questID)
                         if WoWName then info.name = WoWName end
                    end
                    return info
                end
            end
            -- Fallback: Use first result but be careful
            -- if results[1] then return self:ParseData(results[1]) end
        end
    end
    
    -- 3. Fallback: WoW API Only
    local name = C_QuestLog.GetTitleForQuestID(questID)
    if name then
         return { name = name, icon = 4620677, coords=nil }
    end

    return { name = "Quest " .. questID, icon = 4620677, coords=nil }
end

function HeroGuide.Bridge:GetInfoByID(id, parentAchievementID, nameFallback)
    local att = _G["AllTheThings"]
    
    -- Check dependencies
    if not att or not att.SearchForField then 
         return nil 
    end

    -- Strategy 0: SCOPED SEARCH (if parentAchievementID is provided)
    if parentAchievementID then
        local parentNodes = att.SearchForField("achievementID", parentAchievementID)
        if parentNodes then
            -- dprint("HeroGuide DIAGNOSTIC: Dumping Structure for Achievement " .. parentAchievementID)
            local function RecurseDump(nodes, depth)
                if not nodes or depth > 3 then return end
                for _, node in ipairs(nodes) do
                    local prefix = string.rep("  ", depth)
                    local info = (node.text or node.name or "???")
                    local extra = " [ID="..(node.id or "?").." cID="..(node.criteriaID or "?").."]"
                    if node.g then extra = extra .. " (Has Children)" end
                    if node.coords then extra = extra .. " (Has Coords!)" end
                    -- print(prefix .. "- " .. info .. extra)
                    if node.g then RecurseDump(node.g, depth + 1) end
                end
            end
            -- Dump the FIRST parent node found (usually the main one)
            -- RecurseDump({parentNodes[1]}, 0)
            -- print("HeroGuide DIAGNOSTIC: End Dump")

            for _, parentNode in ipairs(parentNodes) do
                -- Search specifically within this parent's children
                local match = self:FindInGroup(parentNode, id, nameFallback)
                if match then
                    -- ENHANCED RETURN LOGIC
                    local info = self:ParseData(match)
                    if info and info.coords and next(info.coords) then 
                        return info, match.text or nameFallback 
                    end
                    
                    -- 1. Entity Search fallback
                    local entityTypes = {"creatureID", "objectID", "npcID", "itemID", "questID"}
                    for _, typeID in ipairs(entityTypes) do
                        local entityID = match[typeID]
                        if entityID then
                            local entities = att.SearchForField(typeID, entityID)
                            if entities then
                                for _, entity in ipairs(entities) do
                                    info = self:ParseData(entity)
                                    if info and info.coords and next(info.coords) then
                                        return info, match.text or entity.text or nameFallback
                                    end
                                end
                            end
                        end
                    end
                    
                    -- 2. Parent Fallback
                    local current = match.parent
                    while current do
                        info = self:ParseData(current)
                        if info and info.coords and next(info.coords) then
                            return info, match.text or nameFallback
                        end
                        current = current.parent
                    end
                    
                    return nil, match.text or nameFallback
                end
            end
        end
    end

    -- Helper: Recursive Scan for Coords
    local function FindCoordsRecursive(node, depth)
        if not node or depth > 3 then return nil end
        -- Check current node
        if node.coords or node.coord then return node end
        -- Check children
        if node.g or node.groups then
            for _, child in ipairs(node.g or node.groups) do
                local res = FindCoordsRecursive(child, depth + 1)
                if res then return res end
            end
        end
        return nil
    end

    -- Helper: Evaluate Node Relevance
    -- Returns: NodeWithCoords (Golden), NodeStructure (Silver), Original (Bronze), nil (Trash)
    local function EvaluateNode(node)
        if not node then return nil end
        
        -- 1. GOLD: Direct Coords or Deep Coords
        local deepParams = FindCoordsRecursive(node, 1)
        if deepParams then return deepParams, 3 end
        
        -- 2. SILVER+: Has Parent with Coords (Inheritance)
        if node.parent and (node.parent.coords or node.parent.coord) then 
             -- We return the node itself, but we will ParseData to look at parent later?
             -- Actually ParseData doesn't check parent automatically.
             -- We should construct a synthetic node or handle it in ParseData.
             -- For now, let's tag it.
             return node, 2
        end
        
        -- 3. SILVER: Has Structure (Children) but no coords found yet
        if node.g or node.groups then return node, 1 end
        
        -- 4. BRONZE: Just a node (References)
        return node, 0
    end

    -- Priority Search List
    local searchFields = {"criteriaID", "creatureID", "objectID", "itemID", "questID", "achievementID"}
    local bestMatch = nil
    local bestScore = -1
    
    -- Execute Search Loop
    for _, field in ipairs(searchFields) do
        local results = att.SearchForField(field, id)
        if results then
            for _, node in ipairs(results) do
                local payload, score = EvaluateNode(node)
                if score == 3 then
                     -- FOUND GOLD! Return immediately
                     return self:ParseData(payload)
                end
                
                -- Keep best fallback
                if score > bestScore then
                    bestMatch = payload
                    bestScore = score
                end
            end
        end
    end
    
    -- Name Fallback (Global)
    if nameFallback and nameFallback ~= "" then 
        local results = att.SearchForField("name", nameFallback)
        if results then
            for _, node in ipairs(results) do
                local payload, score = EvaluateNode(node)
                if score == 2 then return self:ParseData(payload) end -- Gold Name Match
                
                if score > bestScore then
                     bestMatch = payload
                     bestScore = score
                end
            end
        end
    end

    -- Return best result found (or nil)
    if bestMatch then
        return self:ParseData(bestMatch)
    end
    
    return nil
end

-- NEW: Récupérer le Noeud ATT brut (pour le cacher)
function HeroGuide.Bridge:GetATTNode(achievementID)
    local att = _G["AllTheThings"]
    if not att or not att.SearchForField then return nil end
    
    -- On cherche le HF parent
    local nodes = att.SearchForField("achievementID", achievementID)
    if nodes and #nodes > 0 then
        -- dprint("HeroGuide DIAGNOSTIC: Found " .. #nodes .. " nodes. Wrapping in Virtual Group.")
        
        local achNode = nil
        for _, n in ipairs(nodes) do
            -- On cherche le noeud qui correspond à l'ID (parfois SearchForField retourne des objets liés)
            if n.achievementID == achievementID then
                achNode = n
                break
            end
        end
        
        -- Fallback: If no strict match found, take the first one
        if not achNode then achNode = nodes[1] end

        if achNode then
             -- dprint("HeroGuide DIAGNOSTIC: DEEP DUMP of Achievement Node ID="..achievementID)
             local function DeepDump(n, depth)
                if not n or depth > 3 then return end
                for k, v in pairs(n.g or n.groups or {}) do
                    if type(v) == "table" then
                        local name = v.text or v.name or "???"
                        local ids = ""
                        if v.objectID then ids = ids.." obj="..v.objectID end
                        if v.creatureID then ids = ids.." cre="..v.creatureID end
                        if v.itemID then ids = ids.." itm="..v.itemID end
                        if v.coord or v.coords then ids = ids.." COORDS!" end
                        -- dprint(string.rep("  ", depth) .. "- " .. name .. ids)
                        DeepDump(v, depth+1)
                    end
                end
             end
             DeepDump(achNode, 0)
        else
             -- dprint("HeroGuide DIAGNOSTIC: Could not identify Main Achievement Node with children.")
        end

        -- Return a Virtual Group containing ALL these nodes as children
        return { g = nodes, text = "Virtual Root for " .. achievementID }
    end
    return nil
end

-- NEW: Chercher DANS un noeud spécifique (Rapide)
function HeroGuide.Bridge:GetInfoFromNode(parentNode, id, nameFallback)
    if not parentNode then return nil, nil end
    local match = self:FindInGroup(parentNode, id, nameFallback)
    if match then
        local info = self:ParseData(match)
        local text = match.text or nameFallback
        
        if not (info.coords and next(info.coords)) then
             -- dprint("HeroGuide GPS: Match found logic...")
             
             -- DEBUG: Dump keys to see what we have
             local keys = ""
             for k, _ in pairs(match) do keys = keys .. k .. ", " end
              -- dprint("HeroGuide GPS: Node keys: " .. keys)
             
             -- Check NMR (Mystery Field)
             if match.nmr then
                -- dprint("HeroGuide GPS: Inspection 'nmr' field...")
                if type(match.nmr) == "table" then
                    local nmrInfo = "  nmr keys: "
                    for k,v in pairs(match.nmr) do nmrInfo = nmrInfo .. k .. "="..tostring(v)..", " end
                    -- dprint(nmrInfo)
                    
                    -- Check inside nmr for coords
                    local nInfo = self:ParseData(match.nmr)
                    if nInfo and nInfo.coords and next(nInfo.coords) then
                        -- dprint("HeroGuide GPS: Coords found inside 'nmr'!")
                        return nInfo, text
                    end
                else
                    -- dprint("HeroGuide GPS: 'nmr' is value: " .. tostring(match.nmr))
                end
             end

             -- 0. Children Search Fallback (NEW - DEEP SCAN)
            if match.g or match.groups then -- Check groups alias too?
                -- dprint("HeroGuide GPS: Checking children (g/groups)...")
                local children = match.g or match.groups
                for _, child in ipairs(children) do
                    -- 1. Check direct coords on child
                    local cInfo = self:ParseData(child)
                    if cInfo and cInfo.coords and next(cInfo.coords) then
                        -- dprint("HeroGuide GPS: Coords found in child directly!")
                        return cInfo, text
                    end
                    
                    -- 2. Check Entity Logic on child (Deep Link)
                    local childEntityTypes = {"creatureID", "objectID", "npcID", "itemID", "questID"}
                    if _G["AllTheThings"] and _G["AllTheThings"].SearchForField then
                        local att = _G["AllTheThings"]
                        for _, typeID in ipairs(childEntityTypes) do
                            local entityID = child[typeID]
                            if entityID then
                                local entities = att.SearchForField(typeID, entityID)
                                if entities then
                                    for _, entity in ipairs(entities) do
                                        local eInfo = self:ParseData(entity)
                                        if eInfo and eInfo.coords and next(eInfo.coords) then
                                            -- dprint("HeroGuide GPS: Coords found via Child Deep Link ("..typeID..")!")
                                            return eInfo, text
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- 0.5. Providers Fallback (NEW)
            if match.providers then
                  -- dprint("HeroGuide GPS: Checking providers...")
                 local att = _G["AllTheThings"]
                 for _, provider in ipairs(match.providers) do
                     local pType, pID = provider[1], provider[2]
                     local typeMap = { ["n"] = "npcID", ["i"] = "itemID", ["o"] = "objectID" }
                     local searchField = typeMap[pType]
                     
                     if searchField and pID and att and att.SearchForField then
                          -- dprint("HeroGuide GPS: Searching provider " .. searchField .. ": " .. tostring(pID))
                         local results = att.SearchForField(searchField, pID)
                         if results then
                             for _, res in ipairs(results) do
                                 local pInfo = self:ParseData(res)
                                 if pInfo and pInfo.coords and next(pInfo.coords) then
                                      -- dprint("HeroGuide GPS: Coords found via PROVIDER!")
                                     return pInfo, text
                                 end
                             end
                         end
                     end
                 end
            end

             -- 1. Entity Search fallback
            local entityTypes = {"creatureID", "objectID", "npcID", "itemID", "questID"}
            local att = _G["AllTheThings"]
            
            for _, typeID in ipairs(entityTypes) do
                local entityID = match[typeID]
                if entityID and att and att.SearchForField then
                    local entities = att.SearchForField(typeID, entityID)
                    if entities then
                        for _, entity in ipairs(entities) do
                            local eInfo = self:ParseData(entity)
                            if eInfo and eInfo.coords and next(eInfo.coords) then
                                -- dprint("HeroGuide GPS: Coords found via Entity Fallback (" .. typeID .. ")")
                                return eInfo, text
                            end
                        end
                    end
                end
            end
            
            -- 2. Criteria ID Search Fallback (Global)
            local cID = match.criteriaID
            if cID and att and att.SearchForField then
                  -- dprint("HeroGuide GPS: Searching global criteriaID: " .. tostring(cID))
                 local results = att.SearchForField("criteriaID", cID)
                 if results then
                    -- dprint("HeroGuide GPS: Found " .. #results .. " nodes with this criteriaID.")
                    for i, res in ipairs(results) do
                        local rInfo = self:ParseData(res)
                         if rInfo and rInfo.coords and next(rInfo.coords) then
                             -- dprint("HeroGuide GPS: Coords found via CriteriaID match #" .. i)
                             return rInfo, text
                         end
                    end
                 else
                    -- dprint("HeroGuide GPS: No results for criteriaID " .. tostring(cID))
                 end
            end

            -- 3. Name Search Fallback (Global)
            if nameFallback and nameFallback ~= "" and att and att.SearchForField then
                  -- dprint("HeroGuide GPS: Searching global Name: " .. tostring(nameFallback))
                 local results = att.SearchForField("name", nameFallback)
                 if results then
                    -- dprint("HeroGuide GPS: Found " .. #results .. " nodes with this Name.")
                    for i, res in ipairs(results) do
                        local rInfo = self:ParseData(res)
                         if rInfo and rInfo.coords and next(rInfo.coords) then
                             -- print("HeroGuide GPS: Coords found via Name match #" .. i)
                             return rInfo, text
                         end
                    end
                 end
            end

            -- 4. Deep Cache Scan (Manual Iteration as last resort)
            -- OPTIMIZATION: Check internal cache first to avoid lag spikes
            self.DeepScanResultCache = self.DeepScanResultCache or {}
            
            -- Find expected MapID from parent hierarchy (Start from match, not parentNode!)
            local expectedMapID = nil
            local pCurr = match
            while pCurr do
                if pCurr.mapID then 
                    expectedMapID = pCurr.mapID
                    break 
                end
                pCurr = pCurr.parent
            end
            
            -- if expectedMapID then print("[HeroGuide Debug] Expected MapID found for '"..(text or "?").."': " .. tostring(expectedMapID)) end

            -- Cache key must include the expected scope (MapID) to avoid wrong results for identical names in different zones
            local cacheKey = (nameFallback or "") .. (criteriaString or "") .. (expectedMapID or "nil")
            if self.DeepScanResultCache[cacheKey] then
                -- Return cached result if valid
                if self.DeepScanResultCache[cacheKey] == "FAILED" then
                    return nil, text
                else
                    return self.DeepScanResultCache[cacheKey], text
                end
            end

            if att and att.GetRawFieldContainer then
                local currentMapID = C_Map.GetBestMapForUnit("player")
                
                local function ScanCache(cacheName, queries)
                    local container = att.GetRawFieldContainer(cacheName)
                    if not container then return nil end
                    
                    local bestMatch = nil
                    -- Priority:
                    -- 0=None
                    -- 1=Match Name
                    -- 2=Match Name + Coords
                    -- 3=Match Name + Coords + CurrentMap
                    -- 4=Match Name + Coords + ExpectedMap (Highest Priority: Enforced by Achievement)
                    local bestPriority = 0 
                    
                    -- We optimize queries to lowercase once
                    local cleanQueries = {}
                    for _, q in ipairs(queries) do
                        if q and q ~= "" then table.insert(cleanQueries, string.lower(strtrim(q))) end
                    end
                    if #cleanQueries == 0 then return nil end

                    for id, groups in pairs(container) do
                        -- ATT stores a specific 'name' field sometimes, but mainly we assume 'groups[1].name' or look up ID? 
                        -- Actually GetRawFieldContainer returns a table of groups keyed by ID.
                        -- We check the FIRST group for name match usually.
                        local firstGroup = groups[1]
                        if firstGroup and firstGroup.name then
                            local name = string.lower(firstGroup.name)
                            
                            for _, q in ipairs(cleanQueries) do
                                if name == q then
                                    -- FOUND A NAME MATCH
                                    local info = self:ParseData(firstGroup)
                                    local priority = 1
                                    
                                    if info and info.coords and next(info.coords) then
                                        priority = 2
                                        
                                        local function matchesMap(checkMap)
                                            -- Check format 1: {x, y, mapID}
                                            if info.coords[1] and type(info.coords[1]) == "table" and info.coords[1][3] == checkMap then
                                                return true
                                            -- Check format 2: {[mapID] = {x,y}}
                                            elseif info.coords[checkMap] then
                                                return true
                                            end
                                            return false
                                        end

                                        -- Check Expected Map (From Achievement) - Highest Priority
                                        if expectedMapID and matchesMap(expectedMapID) then
                                            priority = 4
                                        -- Check Current Map (From Player) - Secondary Priority
                                        elseif currentMapID and matchesMap(currentMapID) then
                                            priority = 3
                                        end
                                    end
                                    
                                    -- Update best match if this one is better or equal (prefer later match? no, first is fine)
                                    if priority > bestPriority then
                                        bestPriority = priority
                                        bestMatch = info
                                    end
                                    
                                    -- If we found a perfect match (expected map), stop scanning immediately!
                                    if bestPriority == 4 then return bestMatch end
                                end
                            end
                        end
                    end
                    return bestMatch
                end

                local queries = { nameFallback, criteriaString }
                if match.parent and (match.parent.name or match.parent.text) then
                    table.insert(queries, match.parent.name or match.parent.text)
                end

                local objResult = ScanCache("objectID", queries)
                if objResult then 
                    self.DeepScanResultCache[cacheKey] = objResult
                    return objResult, text 
                end
                
                local creResult = ScanCache("creatureID", queries)
                if creResult then 
                    self.DeepScanResultCache[cacheKey] = creResult
                    return creResult, text 
                end
                
                -- Mark as failed to avoid re-scanning
                self.DeepScanResultCache[cacheKey] = "FAILED"
            end
        end
        
        return info, text
    end
    return nil, nil
end

function HeroGuide.Bridge:ParseData(attData)
    -- Extrait ce qui nous intéresse pour l'UI
    local info = {
        name = attData.name or "Unknown",
        icon = attData.icon,
        coords = nil
    }
    
    -- Parsing des coords
    -- ATT stocke souvent les coords sous forme { {x, y, mapID}, ... } ou { [mapID] = {x,y} }
    if attData.coords then
        info.coords = attData.coords
    elseif attData.coord then
        -- Convert single coord to list format for consistency
        info.coords = { attData.coord }
    elseif attData.parent and (attData.parent.coords or attData.parent.coord) then
        -- Inheritance Strategy: Use Parent's coordinates if child lacks them
        -- (Common in ATT for "Objectives" nested under "NPCs/Objects")
        local p = attData.parent
        if p.coords then 
            info.coords = p.coords 
        elseif p.coord then 
            info.coords = { p.coord } 
        end
    end
    
    -- Extract Prerequisites (Source Quests)
    if attData.sourceQuests then
        info.sourceQuests = attData.sourceQuests
    elseif attData.sq then
        -- 'sq' is often a single ID or a list in ATT
        if type(attData.sq) == "table" then
            info.sourceQuests = attData.sq
        else
            info.sourceQuests = { attData.sq }
        end
    end

    return info
end

-- Fonction récursive pour chercher un ID ou un Nom dans un node ATT
function HeroGuide.Bridge:FindInGroup(node, searchID, searchName)
    if not node then return nil end
    
    -- Vérifier les IDs (Ajout de questID et spellID qui sont fréquents pour les trésors/critères)
    if (node.criteriaID == searchID) or 
       (node.creatureID == searchID) or 
       (node.objectID == searchID) or 
       (node.itemID == searchID) or
       (node.achievementID == searchID) or
       (node.questID == searchID) or
       (node.spellID == searchID) then
       return node
    end
    
    -- Vérifier le nom (Insensible à la casse + Trim)
    if searchName and node.name then
        local n1 = strtrim(string.lower(node.name))
        local n2 = strtrim(string.lower(searchName))
        if n1 == n2 then return node end
    end
    
    -- Recherche dans les enfants (.g)
    if node.g then
        for _, child in ipairs(node.g) do
            -- print("  > Scanning child: " .. tostring(child.name or child.id))
            local res = self:FindInGroup(child, searchID, searchName)
            if res then return res end
        end
    end
    
    return nil
end

-- Garder la probe pour le debug si besoin
function HeroGuide.Bridge:Probe(id)
    local info = self:GetInfoByID(id)
    if info then
        if info.coords then
             print("HeroGuide: Data found for " .. id .. " with COORDS!")
             -- Dump coords content to verify format
             for k,v in pairs(info.coords) do
                 print("  Coord ["..k.."]: " .. tostring(v))
                 if type(v) == "table" then
                     for k2,v2 in pairs(v) do
                         print("    - "..k2..": "..tostring(v2))
                     end
                 end
             end
        else
             print("HeroGuide: Data found for " .. id .. " but NO coords.")
        end
    else
        print("HeroGuide: No data found in ATT for " .. id)
    end
end
