-- ADD THIS TO YOUR ITEMS.LUA FROM OX INVENTORY

['patrolbag'] = {
    label = 'Patrol Bag',
    weight = 2500,
    stack = false,
    close = true,
    consume = 0,
    allowArmed = true,
    client = { event = 'cmd_patrolbag:clientUse' }
},
