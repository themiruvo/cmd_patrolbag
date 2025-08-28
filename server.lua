local resourceName = GetCurrentResourceName()
if resourceName ~= 'cmd_patrolbag' then
    print('^1[SECURITY] The resource must be named "cmd_patrolbag"! Current: ' .. resourceName .. '^0')
    StopResource(resourceName)
    return
end


local ESX = exports.es_extended:getSharedObject()
local ox = exports.ox_inventory
local registered = {}
local jobCache = {}
local playerCooldowns = {}
local playerActionCounts = {}

-- Logging function
local function debugLog(message, ...)
    if Config.Performance.debugMode then
        print(('[PATROLBAG-SERVER] ' .. message):format(...))
    end
end

-- Enhanced notification with validation
local function notify(src, title, desc, kind)
    if not src or not title or not desc then
        debugLog('Invalid notification parameters')
        return
    end
    
    TriggerClientEvent('cmd_patrolbag:notify', src, title, desc, kind or 'inform')
end

-- Rate limiting system
local function isRateLimited(src)
    local now = GetGameTimer()
    local cooldown = playerCooldowns[src]
    
    -- Check cooldown
    if cooldown and (now - cooldown) < Config.Security.actionCooldown then
        return true
    end
    
    -- Check rate limit (actions per minute)
    local minute = math.floor(now / 60000)
    local key = src .. '_' .. minute
    local count = playerActionCounts[key] or 0
    
    if count >= Config.Security.maxAttemptsPerMinute then
        return true
    end
    
    -- Update counters
    playerCooldowns[src] = now
    playerActionCounts[key] = count + 1
    
    return false
end

-- Optimized job checking with caching
local function hasJob(src)
    local now = GetGameTimer()
    local cached = jobCache[src]
    
    -- Return cached result if still valid
    if cached and (now - cached.timestamp) < Config.Performance.cacheExpiry then
        return cached.hasJob
    end
    
    -- Get fresh data
    local player = ESX.GetPlayerFromId(src)
    if not player then
        debugLog('Player %d not found', src)
        return false
    end
    
    local job = player.getJob()
    if not job then
        debugLog('Job not found for player %d', src)
        return false
    end
    
    local hasValidJob = false
    for _, jobName in ipairs(Config.JobWhitelist) do
        if jobName == job.name then
            hasValidJob = true
            break
        end
    end
    
    -- Cache the result
    jobCache[src] = {
        hasJob = hasValidJob,
        timestamp = now
    }
    
    debugLog('Job check for player %d: %s (job: %s)', src, tostring(hasValidJob), job.name)
    return hasValidJob
end

-- Enhanced stash management with memory limits
local function ensureStash(invId, label, owner)
    if registered[invId] then return true end
    
    -- Check memory limits
    local stashCount = 0
    for _ in pairs(registered) do stashCount = stashCount + 1 end
    
    if stashCount >= Config.Performance.maxStashes then
        debugLog('Maximum stash limit reached (%d)', Config.Performance.maxStashes)
        return false
    end
    
    local success, err = pcall(function()
        ox:RegisterStash(invId, label, Config.BagStash.slots, Config.BagStash.weight, owner or false)
    end)
    
    if success then
        registered[invId] = {
            label = label,
            owner = owner,
            created = os.time()
        }
        debugLog('Stash registered: %s', invId)
        return true
    else
        debugLog('Failed to register stash %s: %s', invId, tostring(err))
        return false
    end
end

-- Enhanced seeding with error handling
local function seed(invId)
    if not Config.SeedOnFirstOpen then return true end
    
    local success, err = pcall(function()
        for _, item in ipairs(Config.SeedItems) do
            local count = item.count or 1
            if count > 0 then
                ox:AddItem(invId, item.name, count)
                debugLog('Added %d x %s to %s', count, item.name, invId)
            end
        end
    end)
    
    if not success then
        debugLog('Seeding failed for %s: %s', invId, tostring(err))
        return false
    end
    
    return true
end

-- Enhanced bag slot finding with validation
local function findBagSlot(src)
    local success, slots = pcall(function()
        return ox:Search(src, 'slots', Config.BagItem)
    end)
    
    if not success or not slots then
        debugLog('Failed to search for bag slots for player %d', src)
        return nil
    end
    
    -- Return first valid slot
    if type(slots) == 'table' then
        for _, slot in pairs(slots) do
            if slot and slot.name == Config.BagItem then
                return slot
            end
        end
    end
    
    return nil
end

-- Generate unique identifier
local function generateIdentifier()
    local min, max = Config.Security.maxIdentifierRange.min, Config.Security.maxIdentifierRange.max
    return ('PBG-%d'):format(math.random(min, max))
end

-- Callback for bag status with automatic state sync
lib.callback.register('cmd_patrolbag:hasBag', function(src)
    local success, count = pcall(function()
        return ox:GetItem(src, Config.BagItem, nil, true) or 0
    end)
    
    if not success then
        debugLog('Failed to check bag for player %d', src)
        return false
    end
    
    local hasBag = count > 0
    
    -- Auto-sync state to client if it differs
    TriggerClientEvent('cmd_patrolbag:state', src, hasBag)
    
    debugLog('Bag status check for player %d: %s (count: %d)', src, tostring(hasBag), count)
    return hasBag
end)

-- Issue bag event
RegisterNetEvent('cmd_patrolbag:issue', function()
    local src = source
    
    -- Rate limiting
    if isRateLimited(src) then
        notify(src, 'Patrolbag', Config.Text.rateLimited, 'error')
        return
    end
    
    -- Job validation
    if not hasJob(src) then
        notify(src, 'Patrolbag', Config.Text.noAccess, 'error')
        return
    end
    
    -- Check if player already has a bag
    if Config.OneBagInInventory then
        local success, count = pcall(function()
            return ox:GetItem(src, Config.BagItem, nil, true) or 0
        end)
        
        if not success then
            debugLog('Failed to check existing bags for player %d', src)
            notify(src, 'Patrolbag', 'Fehler beim Prüfen der Taschen', 'error')
            return
        end
        
        if count >= 1 then
            notify(src, 'Patrolbag', Config.Text.alreadyHave, 'error')
            return
        end
    end
    
    -- Add bag to inventory
    local success, result = pcall(function()
        return ox:AddItem(src, Config.BagItem, 1, {})
    end)
    
    if not success or not result then
        notify(src, 'Patrolbag', Config.Text.noSpace, 'error')
        return
    end
    
    TriggerClientEvent('cmd_patrolbag:state', src, true)
    notify(src, 'Patrolbag', Config.Text.issued, 'success')
    debugLog('Bag issued to player %d', src)
end)

-- Use bag event
RegisterNetEvent('cmd_patrolbag:onUse', function(slot)
    local src = source
    
    -- Rate limiting
    if isRateLimited(src) then
        notify(src, 'Patrolbag', Config.Text.rateLimited, 'error')
        return
    end
    
    -- Validate slot
    if type(slot) ~= 'number' or slot < 1 then
        debugLog('Invalid slot %s from player %d', tostring(slot), src)
        return
    end
    
    local success, slotData = pcall(function()
        return ox:GetSlot(src, slot)
    end)
    
    if not success or not slotData or slotData.name ~= Config.BagItem then
        debugLog('Invalid bag slot data for player %d', src)
        return
    end
    
    local meta = slotData.metadata or {}
    
    -- Generate identifier if needed
    if not meta.identifier then
        meta.identifier = generateIdentifier()
        debugLog('Generated new identifier: %s', meta.identifier)
    end
    
    local invId = meta.invId or ('patrolbag:' .. meta.identifier)
    local label = ('Patrol-Tasche [%s]'):format(meta.identifier)
    local player = ESX.GetPlayerFromId(src)
    local owner = player and player.getIdentifier() or true
    
    -- Ensure stash exists
    if not ensureStash(invId, label, owner) then
        notify(src, 'Patrolbag', 'Fehler beim Erstellen der Tasche', 'error')
        return
    end
    
    -- Seed if needed
    if not meta.seeded then
        if seed(invId) then
            meta.seeded = true
        else
            notify(src, 'Patrolbag', 'Fehler beim Füllen der Tasche', 'error')
            return
        end
    end
    
    meta.invId = invId
    meta.lastUsed = os.time()
    
    -- Update metadata
    local updateSuccess, updateResult = pcall(function()
        return ox:SetMetadata(src, slotData.slot, meta)
    end)
    
    if not updateSuccess then
        debugLog('Failed to update metadata for player %d', src)
        notify(src, 'Patrolbag', 'Fehler beim Aktualisieren', 'error')
        return
    end
    
    TriggerClientEvent('cmd_patrolbag:openClient', src, invId)
    debugLog('Bag opened by player %d: %s', src, invId)
end)

-- Open my bag event
RegisterNetEvent('cmd_patrolbag:openMy', function()
    local src = source
    
    -- Rate limiting
    if isRateLimited(src) then
        notify(src, 'Patrolbag', Config.Text.rateLimited, 'error')
        return
    end
    
    -- Job validation
    if not hasJob(src) then
        notify(src, 'Patrolbag', Config.Text.noAccess, 'error')
        return
    end
    
    local slot = findBagSlot(src)
    if not slot then
        notify(src, 'Patrolbag', Config.Text.notFound, 'error')
        return
    end
    
    local meta = slot.metadata or {}
    
    if not meta.identifier then
        meta.identifier = generateIdentifier()
    end
    
    local invId = meta.invId or ('patrolbag:' .. meta.identifier)
    local label = ('Patrol-Tasche [%s]'):format(meta.identifier)
    local player = ESX.GetPlayerFromId(src)
    local owner = player and player.getIdentifier() or true
    
    if not ensureStash(invId, label, owner) then
        notify(src, 'Patrolbag', 'Fehler beim Öffnen', 'error')
        return
    end
    
    meta.invId = invId
    meta.lastUsed = os.time()
    
    local success = pcall(function()
        ox:SetMetadata(src, slot.slot, meta)
    end)
    
    if not success then
        notify(src, 'Patrolbag', 'Fehler beim Aktualisieren', 'error')
        return
    end
    
    TriggerClientEvent('cmd_patrolbag:openClient', src, invId)
    debugLog('My bag opened by player %d: %s', src, invId)
end)

-- Return bag event
RegisterNetEvent('cmd_patrolbag:return', function()
    local src = source
    
    -- Rate limiting
    if isRateLimited(src) then
        notify(src, 'Patrolbag', Config.Text.rateLimited, 'error')
        return
    end
    
    local slot = findBagSlot(src)
    if not slot then
        notify(src, 'Patrolbag', Config.Text.notFound, 'error')
        return
    end
    
    local meta = slot.metadata or {}
    
    -- Clear inventory if exists
    if meta.invId then
        local success = pcall(function()
            ox:ClearInventory(meta.invId)
        end)
        
        if success then
            debugLog('Inventory cleared: %s', meta.invId)
        else
            debugLog('Failed to clear inventory: %s', meta.invId)
        end
    end
    
    -- Remove item
    local removeSuccess = pcall(function()
        return ox:RemoveItem(src, slot.name, 1, slot.metadata, slot.slot)
    end)
    
    if not removeSuccess then
        -- Try without metadata
        removeSuccess = pcall(function()
            return ox:RemoveItem(src, slot.name, 1, nil, slot.slot)
        end)
    end
    
    if removeSuccess then
        TriggerClientEvent('cmd_patrolbag:state', src, false)
        notify(src, 'Patrolbag', Config.Text.returned, 'success')
        debugLog('Bag returned by player %d', src)
    else
        notify(src, 'Patrolbag', Config.Text.removeFailed, 'error')
    end
end)

-- Cleanup and maintenance thread
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        
        local now = GetGameTimer()
        local cleaned = 0
        
        -- Clean job cache
        for src, data in pairs(jobCache) do
            if (now - data.timestamp) > Config.Performance.cacheExpiry * 2 then
                jobCache[src] = nil
                cleaned = cleaned + 1
            end
        end
        
        -- Clean old action counts
        local currentMinute = math.floor(now / 60000)
        for key in pairs(playerActionCounts) do
            local minute = tonumber(key:match('_(%d+)$'))
            if minute and (currentMinute - minute) > 5 then -- Keep 5 minutes of history
                playerActionCounts[key] = nil
            end
        end
        
        -- Clean old cooldowns
        for src, timestamp in pairs(playerCooldowns) do
            if (now - timestamp) > 60000 then -- 1 minute
                playerCooldowns[src] = nil
            end
        end
        
        debugLog('Maintenance: cleaned %d cache entries', cleaned)
    end
end)

-- Initialize hooks after ox_inventory is ready
CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do 
        Wait(250) 
    end
    
    debugLog('ox_inventory ready, registering hooks...')
    
    -- Prevent bag in bag
    if Config.PreventBagInBag then
        ox:registerHook('swapItems', function(payload)
            local dest = payload.toInventory
            if type(dest) == 'string' and dest:find('patrolbag:') then
                notify(payload.source, 'Patrolbag', Config.Text.bagInBag, 'error')
                return false
            end
            return true
        end, { print = false, itemFilter = { [Config.BagItem] = true } })
        
        debugLog('Bag-in-bag prevention hook registered')
    end
    
    -- Enforce one bag limit
    if Config.OneBagInInventory then
        ox:registerHook('createItem', function(payload)
            local success, count = pcall(function()
                return ox:GetItem(payload.inventoryId, Config.BagItem, nil, true) or 0
            end)
            
            if success and count > 1 then
                CreateThread(function() -- Async cleanup
                    Wait(100)
                    local items = ox:GetInventoryItems(payload.inventoryId) or {}
                    for _, item in pairs(items) do
                        if item.name == payload.name and item.slot == payload.slot then
                            ox:RemoveItem(payload.inventoryId, item.name, 1, nil, item.slot)
                            notify(payload.inventoryId, 'Patrolbag', Config.Text.onlyOneBag, 'error')
                            debugLog('Removed excess bag from player %s', payload.inventoryId)
                            break
                        end
                    end
                end)
            end
        end, { print = false, itemFilter = { [Config.BagItem] = true } })
        
        debugLog('One bag limit hook registered')
    end
    
    debugLog('All hooks registered successfully')
end)

-- Player join handler - sync bag status
AddEventHandler('esx:playerLoaded', function(src)
    debugLog('Player %d loaded, checking bag status...', src)
    
    -- Small delay to ensure inventory is ready
    CreateThread(function()
        Wait(2000)
        
        local success, count = pcall(function()
            return ox:GetItem(src, Config.BagItem, nil, true) or 0
        end)
        
        if success then
            local hasBag = count > 0
            TriggerClientEvent('cmd_patrolbag:state', src, hasBag)
            debugLog('Player %d bag status synced: %s', src, tostring(hasBag))
        end
    end)
end)

-- Alternative join handler for servers that use different events
AddEventHandler('playerJoining', function(src)
    debugLog('Player %d joining, will sync bag status after delay...', src)
    
    CreateThread(function()
        -- Wait longer for full join
        Wait(5000)
        
        local success, count = pcall(function()
            return ox:GetItem(src, Config.BagItem, nil, true) or 0
        end)
        
        if success then
            local hasBag = count > 0
            TriggerClientEvent('cmd_patrolbag:state', src, hasBag)
            debugLog('Late sync for player %d: %s', src, tostring(hasBag))
        end
    end)

end)
