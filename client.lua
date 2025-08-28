local npc
local hasBag = false
local lastBagCheck = 0
local statusChecker
local isInitialized = false

-- Logging function
local function debugLog(message)
    if Config.Performance.debugMode then
        print(('[PATROLBAG-CLIENT] %s'):format(message))
    end
end

-- Optimized bag status refresh with caching
local function refreshHasBag(force)
    local now = GetGameTimer()
    if not force and (now - lastBagCheck) < Config.Performance.bagStatusInterval then
        return
    end
    
    lastBagCheck = now
    
    -- Use synchronous callback to ensure we get the result
    local result = lib.callback.await('cmd_patrolbag:hasBag', false)
    if result ~= hasBag then
        hasBag = result
        debugLog(('Bag status changed to: %s'):format(tostring(hasBag)))
        
        -- Force NPC target refresh when status changes
        if npc and DoesEntityExist(npc) then
            debugLog('Refreshing NPC targets due to bag status change')
            exports.ox_target:removeLocalEntity(npc)
            Wait(100)
            addNpcTargets()
        end
    end
end

-- Separate function for adding NPC targets (for refresh capability)
local function addNpcTargets()
    if not npc or not DoesEntityExist(npc) then return end
    
    exports.ox_target:addLocalEntity(npc, {
        {
            name = 'patrolbag_take',
            icon = 'fa-solid fa-briefcase',
            label = Config.Text.npcTake,
            distance = Config.NPC.distance,
            canInteract = function()
                return not hasBag
            end,
            onSelect = function()
                TriggerServerEvent('cmd_patrolbag:issue')
            end
        },
        {
            name = 'patrolbag_open',
            icon = 'fa-solid fa-folder-open',
            label = Config.Text.npcOpen,
            distance = Config.NPC.distance,
            canInteract = function()
                return hasBag and Config.NPC.showOpenOption
            end,
            onSelect = function()
                TriggerServerEvent('cmd_patrolbag:openMy')
            end
        },
        {
            name = 'patrolbag_return',
            icon = 'fa-solid fa-rotate-left',
            label = Config.Text.npcReturn,
            distance = Config.NPC.distance,
            canInteract = function()
                return hasBag
            end,
            onSelect = function()
                TriggerServerEvent('cmd_patrolbag:return')
            end
        }
    })
    
    debugLog('NPC targets added/refreshed')
end

-- Enhanced NPC spawning with better error handling
local function spawnNpc()
    if npc and DoesEntityExist(npc) then 
        debugLog('NPC already exists, skipping spawn')
        return 
    end
    
    debugLog('Spawning NPC...')
    
    -- Request model with timeout
    local modelRequested = lib.requestModel(Config.NPC.model, Config.Performance.modelRequestTimeout)
    if not modelRequested then
        debugLog('Failed to load NPC model')
        return
    end
    
    local c = Config.NPC.coords
    npc = CreatePed(4, Config.NPC.model, c.x, c.y, c.z - 1.0, c.w, false, true)
    
    if not DoesEntityExist(npc) then
        debugLog('Failed to create NPC entity')
        return
    end
    
    -- Configure NPC
    SetEntityInvincible(npc, true)
    FreezeEntityPosition(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    
    -- Add interaction options using separate function
    addNpcTargets()
    
    debugLog('NPC spawned successfully')
end

-- Clean NPC cleanup
local function cleanupNpc()
    if npc and DoesEntityExist(npc) then
        DeleteEntity(npc)
        npc = nil
        debugLog('NPC cleaned up')
    end
end

-- Optimized status checker - only runs when needed
local function startStatusChecker()
    if statusChecker then return end
    
    statusChecker = CreateThread(function()
        debugLog('Status checker started')
        while isInitialized do
            Wait(Config.Performance.bagStatusInterval)
            if isInitialized then
                refreshHasBag()
            end
        end
        debugLog('Status checker stopped')
    end)
end

local function stopStatusChecker()
    if statusChecker then
        isInitialized = false
        statusChecker = nil
        debugLog('Status checker stopping...')
    end
end

-- Initialize everything
local function initialize()
    if isInitialized then return end
    
    debugLog('Initializing client...')
    isInitialized = true
    
    -- Force initial bag status check and wait for result
    refreshHasBag(true)
    
    -- Small delay to ensure bag status is properly set
    Wait(500)
    
    spawnNpc()
    startStatusChecker()
    
    debugLog('Client initialized with bag status: %s', tostring(hasBag))
end

-- Main initialization thread
CreateThread(function()
    -- Wait for network and essential systems
    while not NetworkIsSessionStarted() do 
        Wait(100) 
    end
    
    -- Wait a bit more to ensure everything is loaded
    Wait(1000)
    
    initialize()
end)

-- Resource start handler
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        debugLog('Resource started, reinitializing...')
        Wait(1000) -- Small delay to ensure everything is ready
        initialize()
    end
end)

-- Resource stop handler with cleanup
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    
    debugLog('Resource stopping, cleaning up...')
    stopStatusChecker()
    cleanupNpc()
end)

-- Network events
RegisterNetEvent('cmd_patrolbag:openClient', function(invId)
    if not invId or type(invId) ~= 'string' then 
        debugLog('Invalid inventory ID received')
        return 
    end
    
    debugLog(('Opening inventory: %s'):format(invId))
    exports.ox_inventory:openInventory('stash', invId)
end)

RegisterNetEvent('cmd_patrolbag:notify', function(title, description, type)
    if not title or not description then return end
    
    lib.notify({ 
        title = title, 
        description = description, 
        type = type or Config.Notify.type, 
        position = Config.Notify.pos, 
        duration = Config.Notify.ms 
    })
end)

RegisterNetEvent('cmd_patrolbag:clientUse', function(slot)
    local slotToUse
    
    if type(slot) == 'table' and slot.slot then
        slotToUse = slot.slot
    elseif type(slot) == 'number' then
        slotToUse = slot
    else
        debugLog('Invalid slot data received')
        return
    end
    
    debugLog(('Using bag in slot: %s'):format(slotToUse))
    TriggerServerEvent('cmd_patrolbag:onUse', slotToUse)
end)

-- Optimized state update - only refresh when state actually changes
RegisterNetEvent('cmd_patrolbag:state', function(state)
    local newState = state and true or false
    if newState ~= hasBag then
        local oldState = hasBag
        hasBag = newState
        debugLog('Bag state updated from %s to %s', tostring(oldState), tostring(hasBag))
        
        -- Force immediate refresh to sync with server
        lastBagCheck = 0
        
        -- Refresh NPC targets immediately when state changes
        if npc and DoesEntityExist(npc) then
            exports.ox_target:removeLocalEntity(npc)
            Wait(100)
            addNpcTargets()
        end
    end
end)

-- Add manual refresh command for debugging
RegisterCommand('refreshbag', function()
    if Config.Performance.debugMode then
        local oldStatus = hasBag
        refreshHasBag(true)
        Wait(100)
        print(('Bag status: %s -> %s'):format(tostring(oldStatus), tostring(hasBag)))
        
        if npc and DoesEntityExist(npc) then
            exports.ox_target:removeLocalEntity(npc)
            Wait(100)
            addNpcTargets()
        end
    end
end, false)