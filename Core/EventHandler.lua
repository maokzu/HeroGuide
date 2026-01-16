-- Gestion des événements et logique principale
print("HeroGuide: EventHandler.lua Reloaded.")

local f = CreateFrame("Frame")
-- On écoute plus large pour être sûr de ne rien rater
f:RegisterEvent("TRACKED_ACHIEVEMENT_UPDATE")
f:RegisterEvent("TRACKED_ACHIEVEMENT_LIST_CHANGED") 
f:RegisterEvent("PLAYER_ENTERING_WORLD") 
f:RegisterEvent("CRITERIA_UPDATE") -- Se déclenche quand on progresse
f:RegisterEvent("CONTENT_TRACKING_UPDATE")
f:RegisterEvent("CONTENT_TRACKING_LIST_UPDATE")

-- Fonction de mise à jour globale
-- Fonction de mise à jour globale
-- forceOpen: Si true, force l'affichage de la fenêtre même si elle était cachée
function HeroGuide:ScanTracked(forceOpen)
    if forceOpen then
        print("--- HeroGuide Diagnostic ---")
        if C_ContentTracking then
            local type = Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement or 2
            local t = C_ContentTracking.GetTrackedIDs(type)
            print("API C_ContentTracking: " .. (t and #t or "nil") .. " items.")
        else
            print("API C_ContentTracking: Not Available")
        end
        
        if GetTrackedAchievements then
             print("API GetTrackedAchievements: " .. select("#", GetTrackedAchievements()) .. " items.")
        else
             print("API GetTrackedAchievements: Not Available")
        end
        print("--- End Diagnostic ---")
    end

    local trackedIDs = {}

    -- Tenter l'API Moderne (The War Within / Dragonflight)
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        local trackingType = Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement or 2
        trackedIDs = C_ContentTracking.GetTrackedIDs(trackingType) or {}
    elseif GetTrackedAchievements then
        -- Fallback Legacy
        trackedIDs = { GetTrackedAchievements() }
    else
        return
    end
    
    if not trackedIDs or #trackedIDs == 0 then
        -- Rien de suivi : On cache la fenêtre
        if HeroGuide.UI and HeroGuide.UI.MainFrame then
            HeroGuide.UI.MainFrame:Hide()
        end
        return
    end
    
    -- Smart Selection Loop: Try candidates until one works
    local found = false
    
    -- Function to try building a guide
    local function TryID(rawID)
        local id = (type(rawID) == "table") and rawID.id or rawID
        if not id then return false end
        
        -- if forceOpen then print("  [Scan] Testing ID: " .. tostring(id)) end
        
        if forceOpen then HeroGuide.ForceOpen = true end
        
        local success, valid = pcall(function() return HeroGuide:BuildGuide(id) end)
        
        if not success then
             print("|cffff0000[HeroGuide] CRITICAL RENDER ERROR:|r " .. tostring(valid))
             return false
        end

        if success and valid then
            -- if forceOpen then HeroGuide.ForceOpen = true end -- Too late here
            activeID = id
            return true
        end
        return false
    end
    
    -- 1. Try Last Interacted First
    if lastInteractedID then
        for _, id in ipairs(trackedIDs) do
            local cleanID = (type(id) == "table") and id.id or id
            if cleanID == lastInteractedID then
                if TryID(id) then found = true; break end
            end
        end
    end
    
    -- 2. If not found, scan ALL others (Reverse order: Newest first)
    if not found then
        for i = #trackedIDs, 1, -1 do
            local id = trackedIDs[i]
            local cleanID = (type(id) == "table") and id.id or id
            
            -- Skip if we already tried it above
            if cleanID ~= lastInteractedID then
                if TryID(id) then found = true; break end
            end
        end
    end
    
    if not found then
        -- We have tracked items (Quests etc) but NO valid Achievements.
        -- Hide window to avoid confusion.
        if HeroGuide.UI and HeroGuide.UI.MainFrame then
            HeroGuide.UI.MainFrame:Hide()
        end
        
        if forceOpen then
             print("|cffff0000[HeroGuide]|r No valid Achievement found in tracking list. (Quests are ignored)")
        end
    end
end

-- Variable pour stocker le dernier HF manipulé
local lastInteractedID = nil

f:SetScript("OnEvent", function(self, event, ...)
    -- print("HeroGuide Event: " .. event)
    
    if event == "TRACKED_ACHIEVEMENT_UPDATE" then
        local achievementID, added = ...
        if added then
            lastInteractedID = achievementID
            HeroGuide.ForceOpen = true -- Force open on new track
        end
    elseif event == "CONTENT_TRACKING_UPDATE" then
         -- (trackableType, trackableID, added)
         local trackableType, trackableID, added = ...
         if added and (trackableType == Enum.ContentTrackingType.Achievement) then
             lastInteractedID = trackableID
             HeroGuide.ForceOpen = true -- Force open on new track
         end
    elseif event == "PLAYER_ENTERING_WORLD" then
        HeroGuide.ForceOpen = true -- Open/Restore on Login
    end
    
    -- Debounce: Cancel previous timer if still pending
    -- Debounce: Cancel previous timer if still pending
    if self.updateTimer then self.updateTimer:Cancel() end
    self.updateTimer = C_Timer.NewTimer(0.5, function() HeroGuide:ScanTracked() end)
end)

SLASH_HEROGUIDE_SCAN1 = "/hg_scan"
SlashCmdList["HEROGUIDE_SCAN"] = function()
    print("HeroGuide: Manually scanning for tracked achievements...")
    HeroGuide:ScanTracked()
end

-- Fonction récursive pour récupérer les enfants d'un HF ou d'un Méta
-- Fonction récursive pour récupérer les enfants d'un HF ou d'un Méta
function HeroGuide:FetchCriteria(achievementID)
    local nodes = {}
    local numCriteria = GetAchievementNumCriteria(achievementID)

    
    -- OPTIMISATION: On récupère le noeud ATT parent UNE SEULE FOIS
    local attParentNode = nil
    if HeroGuide.Bridge and HeroGuide.Bridge.GetATTNode then
        attParentNode = HeroGuide.Bridge:GetATTNode(achievementID)
    end
    
    if numCriteria > 0 then
        for i=1, numCriteria do
            local criteriaString, criteriaType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString, criteriaID = GetAchievementCriteriaInfo(achievementID, i)

            
             -- FILTRE: On ne garde que ce qui n'est PAS fini, SAUF si le HF père est fini (cas de l'historique)
            local queryID = assetID
            if not queryID or queryID == 0 then queryID = criteriaID end 
            
            -- RECHERCHE OPTIMISÉE: On cherche dans le noeud parent direct
            local attInfo = nil
            if attParentNode then
                attInfo = HeroGuide.Bridge:GetInfoFromNode(attParentNode, queryID, criteriaString)
            end
            
            -- FALLBACK: Si l'optimisation échoue OU ne donne pas de coords, on tente une recherche globale
            if (not attInfo or not attInfo.coords) and HeroGuide.Bridge.GetInfoByID then
                 local globalInfo = HeroGuide.Bridge:GetInfoByID(queryID, nil, criteriaString)
                 
                 -- On ne remplace que si on a trouvé mieux (des coords)
                 if globalInfo and globalInfo.coords then
                     attInfo = globalInfo
                 end
            end
            
            -- Détection Meta-Succès (Type 8) ou Quête Importante (Type 27)
            local isMeta = (criteriaType == 8)
            local isQuest = (criteriaType == 27)
            local renderAsNode = isMeta or isQuest
            
            -- Revert: Use criteriaString as it is the trusted in-game name. 
            -- attInfo.name can be erratic (e.g. NPC name vs Criteria name).
            
            local node = {
                name = criteriaString,
                id = queryID,
                completed = completed,
                isMeta = isMeta,
                renderAsNode = renderAsNode,
                childAchievementID = isMeta and assetID or nil, -- Only traverse achievements
                criteriaIndex = i, 
                parentAchievementID = achievementID,
                icon = (attInfo and attInfo.icon) or nil, 
                coords = nil,
                
                -- Tree View Properties
                expanded = false,
                depth = 0,
                children = {}
            }
            
            if isMeta and not node.icon then
                    local _, _, _, _, _, _, _, _, _, metaIcon = GetAchievementInfo(assetID)
                    if metaIcon then node.icon = metaIcon end
            elseif isQuest and not node.icon then
                    -- Default Quest Icon if none found
                    node.icon = 134414 -- Interface\Icons\dungeon_skull or similar? Or just QuestionMark.
                    -- Better: "Quest" icon
                    node.icon = 132048 -- Quest Icon
            end

            if attInfo and attInfo.coords then
                node.coords = attInfo.coords
                node.hasGPS = true
            else
                node.hasGPS = false
            end
            
            -- [NEW] Prerequisite Injection (Source Quests)
            -- Logic: Only inject if this is a Leaf Node or a Layout-less criteria.
            -- If it is a "Meta/Container" (Type 8 with children), we assume prerequisites are handled by its children.
            local isContainer = isMeta and (assetID and GetAchievementNumCriteria(assetID) > 0)
            
            if attInfo and attInfo.sourceQuests and not isContainer then
                for _, sqID in ipairs(attInfo.sourceQuests) do
                    local sqInfo = HeroGuide.Bridge:GetQuestInfo(sqID)
                    local isDone = C_QuestLog.IsQuestFlaggedCompleted(sqID)
                    
                    if sqInfo and not isDone then -- Only show unconnected prerequisites? Or all? User wants to see progress.
                        -- Actually, if it's done, we might hide it or show it checked.
                        -- Let's show all for now, but maybe sorted?
                        local sqNode = {
                            name = "[Quest] " .. (sqInfo.name or "Quest " .. sqID),
                            id = sqID,
                            completed = isDone,
                            isMeta = false,
                            renderAsNode = false, -- Leaf logic usually
                            childAchievementID = nil,
                            icon = 4620677, -- Quest Bang (Check this ID, fallback 132048)
                            coords = sqInfo.coords,
                            hasGPS = (sqInfo.coords ~= nil),
                            depth = 1, -- TreeRenderer might recalculate this
                            children = {}
                        }
                        
                        -- Force parent to be expandable
                        node.renderAsNode = true
                        node.collapsed = true -- Start collapsed by default
                        
                        table.insert(node.children, sqNode)
                    end
                end
            end
            
            table.insert(nodes, node)
        end
    end
    
    return nodes
end

function HeroGuide:BuildGuide(achievementID)
    local id, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild, wasEarnedByMe, earnedBy = GetAchievementInfo(achievementID)
    
    if not id then 
        -- Silent failure or debug usage
        -- print("|cffff0000[HeroGuide]|r GetAchievementInfo failed for ID: " .. tostring(achievementID))
        return false 
    end
    
    local guideData = {
        id = id,
        title = name,
        icon = icon,
        nodes = self:FetchCriteria(id)
    }
    
    if #guideData.nodes == 0 then
        table.insert(guideData.nodes, { 
            name = "Tous les critères terminés !", 
            completed = true, 
            icon = 132049,
            depth = 0 
        })
    end
    
    if HeroGuide.UI and HeroGuide.UI.RenderTree then
        HeroGuide.UI:RenderTree(guideData)
        return true
    end
    return false
end

SLASH_HEROGUIDE_BUILD1 = "/hg_build"
SlashCmdList["HEROGUIDE_BUILD"] = function(msg)
    local id = tonumber(msg)
    if id then HeroGuide:BuildGuide(id) end
end

HeroGuide.EventHandler = f
