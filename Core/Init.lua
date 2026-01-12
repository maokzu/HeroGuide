HeroGuide = {}
HeroGuide.Bridge = {}
HeroGuide.UI = {}

-- Commande Slash pour tester l'extraction de données ATT
SLASH_HEROGUIDE1 = "/hg"
SlashCmdList["HEROGUIDE"] = function(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    
    if command == "probe" then
        local id = tonumber(rest)
        -- Si pas d'ID, on lance le probe générique (hardcodé dans Bridge)
        print("HeroGuide: Probing ATT...")
        HeroGuide.Bridge:Probe(id or 0)
    elseif command == "debug" then
        print("[HeroGuide] Debug Info:")
        local tracked = {}
        if GetTrackedAchievements then
            tracked = { GetTrackedAchievements() }
        end
        
        if C_ContentTracking and C_ContentTracking.GetTrackedIDs then
             local tracked2 = C_ContentTracking.GetTrackedIDs(2)
             local count = (tracked2 and #tracked2 or 0)
             print("  - Modern API Tracked Count: " .. count)
             
             if count > 0 then
                 for i, t in ipairs(tracked2) do
                     local tid = (type(t) == "table") and t.id or t
                     print("    ["..i.."] ID: " .. tostring(tid) .. " (Type: " .. type(t) .. ")")
                     
                     -- FORCE BUILD TEST on first item
                     if i == 1 and tid then
                         print("  [Debug] Forcing BuildGuide for ID: " .. tid)
                         if HeroGuide.BuildGuide then
                             HeroGuide:BuildGuide(tid)
                         else
                             print("  [Error] HeroGuide:BuildGuide function missing!")
                         end
                     end
                 end
             end
        end
        print("  - Legacy API Tracked Count: " .. #tracked)
        
        if HeroGuide.UI and HeroGuide.UI.MainFrame then
            print("  - MainFrame shown: " .. tostring(HeroGuide.UI.MainFrame:IsShown()))
        else
            print("  - MainFrame: nil")
        end
    elseif command == "diag" then
        print("|cff00ffff[HeroGuide] Deep Diagnostic:|r")
        local types = {
            [0] = "Quest", -- Enum.ContentTrackingType.Quest
            [1] = "Achievement", -- Enum.ContentTrackingType.Achievement? Need to verify Enum values
            [2] = "Profesion?",
            [3] = "Other?"
        }
        
        -- Check Enum Real Values if possible
        local achType = Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement or 2
        local questType = Enum.ContentTrackingType and Enum.ContentTrackingType.Quest or 1
        
        print("Enum: Quest="..tostring(questType)..", Ach="..tostring(achType))
        
        print("Components Check:")
        print("  UI.RenderTree: " .. (HeroGuide.UI.RenderTree and "OK" or "MISSING"))
        print("  BuildGuide: " .. (HeroGuide.BuildGuide and "OK" or "MISSING"))
        
        if C_ContentTracking then
            for t = 0, 4 do
                local list = C_ContentTracking.GetTrackedIDs(t) or {}
                if #list > 0 then
                    print("Type " .. t .. ": " .. #list .. " items.")
                    for i, v in ipairs(list) do
                        local realID = (type(v)=="table") and v.id or v
                        print("  -> ID: " .. tostring(realID))
                        
                        -- Test as Achievement
                        local id, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(realID)
                        if id then 
                            print("     [IS_ACHIEVEMENT] " .. tostring(name)) 
                        else
                            print("     [NOT_ACHIEVEMENT]")
                        end
                        
                        -- Test as Quest
                        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
                            local qTitle = C_QuestLog.GetTitleForQuestID(realID)
                            if qTitle then print("     [IS_QUEST] " .. tostring(qTitle)) end
                        end
                    end
                end
            end
        else
            print("C_ContentTracking: Not Available")
        end
        
        -- Legacy
        local legacy = { GetTrackedAchievements() }
        print("Legacy GetTrackedAchievements: " .. #legacy .. " items.")
    elseif command == "dump" then
        local id = tonumber(rest)
        
        local nodes = nil
        if id then
             print("[HeroGuide] Dumping ATT Node for ID: " .. id)
             if HeroGuide.Bridge and HeroGuide.Bridge.GetATTNode then
                 nodes = HeroGuide.Bridge:GetATTNode(id)
             end
        else
             -- Text Search logic
             print("[HeroGuide] Dumping ATT Node by Name: " .. rest)
             if HeroGuide.Bridge and HeroGuide.Bridge.SearchGlobal then
                 nodes = HeroGuide.Bridge:SearchGlobal("name", rest)
             end
        end

        if nodes and #nodes > 0 then
             print("Found " .. #nodes .. " nodes.")
             -- Dump up to 3 results to avoid spam
             for nIdx=1, math.min(#nodes, 3) do 
                 local root = nodes[nIdx]
                 print("--- Node #"..nIdx.." ---")
                 print("  Text: " .. (root.text or root.name or "???"))
                 -- Print all IDs
                 local ids = ""
                 for k,v in pairs(root) do
                     if k:match("ID") then ids = ids .. k .. "=" .. tostring(v) .. " " end
                 end
                 print("  IDs: " .. ids)
                 
                 if root.g or root.groups then
                     local children = root.g or root.groups
                     print("  Children (" .. #children .. "):")
                     for i, child in ipairs(children) do
                         local cName = child.text or child.name or "???"
                         local cInfo = ""
                         if child.questID then cInfo = cInfo .. "QID="..child.questID.." " end
                         if child.objectID then cInfo = cInfo .. "OID="..child.objectID.." " end
                         if child.criteriaID then cInfo = cInfo .. "CID="..child.criteriaID.." " end
                         
                         local hasCoords = (child.coords or child.coord) and "YES" or "NO"
                         print("    ["..i.."] " .. cName .. " | " .. cInfo .. "| GPS: " .. hasCoords)
                     end
                 else
                     print("  (No Children)")
                 end
             end
        else
             print("No ATT Node found.")
        end
    elseif command == "check" then
        local id = tonumber(rest)
        if id then 
            print("[HeroGuide] Checking ID: " .. id)
            if HeroGuide.Bridge and HeroGuide.Bridge.GetInfoByID then
                 local data = HeroGuide.Bridge:GetInfoByID(id, nil, "ManualCheck")
                 if data then
                     print("  Result: FOUND!")
                     print("  Name: " .. tostring(data.text))
                     print("  Coords: " .. (data.coords and "YES (Count: "..#data.coords..")" or "NO"))
                     
                     -- DEBUG STRUCTURE
                     print("  -- Node Keys --")
                     local keys = ""
                     for k,v in pairs(data) do keys = keys .. k .. ", " end
                     print("  Keys: " .. keys)
                     
                     if data.sourceQuests then
                         local sqStr = ""
                         for k,v in pairs(data.sourceQuests) do sqStr = sqStr .. tostring(v) .. ", " end
                         print("  SourceQuests: " .. sqStr)
                     end
                     
                     if data.parent then
                         local pName = data.parent.text or data.parent.name or "???"
                         local pIDs = ""
                         if data.parent.questID then pIDs = pIDs.."QID="..data.parent.questID.." " end
                         if data.parent.objectID then pIDs = pIDs.."OID="..data.parent.objectID.." " end
                         if data.parent.npcID then pIDs = pIDs.."NPC="..data.parent.npcID.." " end
                         if data.parent.achievementID then pIDs = pIDs.."AID="..data.parent.achievementID.." " end
                         print("  Parent: " .. pName .. " [" .. pIDs .. "]")
                         print("  Parent Coords: " .. ((data.parent.coords or data.parent.coord) and "YES" or "NO"))
                     else
                         print("  Parent: nil")
                     end
                     
                     if data.g then print("  Children (.g): " .. #data.g) end
                     if data.groups then print("  Children (.groups): " .. #data.groups) end
                     
                     if data.coords and #data.coords > 0 then
                         print("    [1] " .. data.coords[1][1] .. ", " .. data.coords[1][2])
                     end
                 else
                     print("  Result: NIL (Nothing found)")
                 end
            else
                print("  Error: Bridge not ready.")
            end
            
            -- DUMP WOW CRITERIA (Added for Debugging)
            local numCriteria = GetAchievementNumCriteria(id)
            if numCriteria and numCriteria > 0 then
                print("--- WoW Criteria for " .. id .. " ---")
                for i=1, numCriteria do
                    local cName, cType, completed, _, _, _, _, assetID, _, cID = GetAchievementCriteriaInfo(id, i)
                    local note = ""
                    -- Resolve ATT info for this criteria
                    local queryID = (assetID and assetID > 0) and assetID or cID
                    local attInfo = HeroGuide.Bridge:GetInfoByID(queryID, id)
                    
                    if attInfo and attInfo.sourceQuests then 
                         note = note .. " [Has SQ count: " .. #attInfo.sourceQuests .. "]"
                         -- print("   SQ IDs: " .. table.concat(attInfo.sourceQuests, ", "))
                    end
                    
                    print(string.format("  #%d: %s (ID:%s Asset:%s Type:%s) %s", i, cName, tostring(cID), tostring(assetID), tostring(cType), note))
                end
            else
                print("--- No WoW Criteria found for " .. id .. " ---")
            end
        else
            print("Usage: /hg check <ID>")
        end
    else
        print("HeroGuide Commands:")
        print("  /hg probe [ID] - Inspect ATT data structure")
        print("  /hg check [ID] - Test Bridge lookup & Coords")
        print("  /hg diag - Run deep content tracking diagnostic")
    end
end

print("HeroGuide V2.1 Loaded. /hg diag for help.")
