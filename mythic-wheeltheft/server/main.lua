local Callbacks, Fetch, Inventory

local function RetrieveComponents()
    Callbacks = exports['mythic-base']:FetchComponent('Callbacks')
    Fetch = exports['mythic-base']:FetchComponent('Fetch')
    Inventory = exports['mythic-base']:FetchComponent('Inventory')
end

AddEventHandler('WheelTheft:Shared:DependencyUpdate', RetrieveComponents)

local function RegisterCallbacks()
    Callbacks:RegisterServerCallback('WheelTheft:RemoveWheel', function(source, data, cb)
        if type(data) ~= 'table' or not data.vehicle or not data.wheel then
            cb(false, 'Invalid wheel information')
            return
        end

        local veh = NetworkGetEntityFromNetworkId(data.vehicle)
        if not veh or not DoesEntityExist(veh) then
            cb(false, 'Vehicle not found')
            return
        end

        local player = Fetch:Source(source)
        if not player then
            cb(false, 'Player unavailable')
            return
        end

        local char = player:GetData('Character')
        if not char then
            cb(false, 'Character unavailable')
            return
        end

        local charId = char:GetData('SID')
        if not charId then
            cb(false, 'Unable to identify character')
            return
        end

        if not Inventory.Items:Has(charId, 1, 'torque_wrench', 1) then
            cb(false, 'You need a torque wrench to do that')
            return
        end

        local wheelIndex = tonumber(data.wheelIndex)
        if not wheelIndex then
            cb(false, 'Invalid wheel information')
            return
        end

        local entityWrapper = Entity(veh)
        if not entityWrapper or not entityWrapper.state then
            cb(false, 'Vehicle unavailable')
            return
        end

        local currentRemoved = entityWrapper.state.wheelTheftRemoved or {}
        local removedCopy = {}
        for k, v in pairs(currentRemoved) do
            removedCopy[k] = v
        end

        local stateKey = tostring(wheelIndex)

        if removedCopy[wheelIndex] or removedCopy[stateKey] then
            cb(false, 'That wheel is already missing')
            return
        end

        local success = Inventory:AddItem(charId, 'wheel', 1, {}, 1)
        if not success then
            cb(false, 'Not enough space to hold the wheel')
            return
        end

        removedCopy[stateKey] = true
        entityWrapper.state:set('wheelTheftRemoved', removedCopy, true)

        TriggerClientEvent('WheelTheft:Client:WheelRemoved', -1, data.vehicle, wheelIndex)

        cb(true, 'You removed the wheel')
    end)
end

local function clearRemovedWheelState(entityWrapper, wheelIndex)
    if not entityWrapper or not entityWrapper.state or not wheelIndex then return end

    local currentRemoved = entityWrapper.state.wheelTheftRemoved
    if type(currentRemoved) ~= 'table' then return end

    local targetKey = tostring(wheelIndex)
    local updated = {}

    for key, removed in pairs(currentRemoved) do
        if removed then
            local numericKey = tonumber(key)
            if key ~= targetKey and numericKey ~= wheelIndex then
                updated[key] = true
            end
        end
    end

    if next(updated) then
        entityWrapper.state:set('wheelTheftRemoved', updated, true)
    else
        entityWrapper.state:set('wheelTheftRemoved', nil, true)
    end
end

local function RegisterItems()
    Inventory.Items:RegisterUse('torque_wrench', 'WheelTheft', function(source, item)
        TriggerClientEvent('WheelTheft:Client:UseTorqueWrench', source)
    end)

    Inventory.Items:RegisterUse('wheel', 'WheelTheft', function(source, item)
        TriggerClientEvent('WheelTheft:Client:UseWheelItem', source)
    end)
end

RegisterNetEvent('WheelTheft:Server:RestoreWheel', function(netId, wheelIndex)
    local src = source
    local targetIndex = tonumber(wheelIndex)
    if not netId or not targetIndex then return end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or not DoesEntityExist(veh) then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local pedCoords = GetEntityCoords(ped)
    local vehCoords = GetEntityCoords(veh)

    if #(pedCoords - vehCoords) > 30.0 then return end

    local entityWrapper = Entity(veh)
    if not entityWrapper or not entityWrapper.state then return end

    local currentRemoved = entityWrapper.state.wheelTheftRemoved
    if type(currentRemoved) ~= 'table' then return end

    local stateKey = tostring(targetIndex)
    if not currentRemoved[stateKey] and not currentRemoved[targetIndex] then return end

    clearRemovedWheelState(entityWrapper, targetIndex)
end)

AddEventHandler('Core:Shared:Ready', function()
    exports['mythic-base']:RequestDependencies('WheelTheft', {
        'Callbacks',
        'Fetch',
        'Inventory',
    }, function(error)
        if #error > 0 then
            return
        end

        RetrieveComponents()
        RegisterCallbacks()
        RegisterItems()
    end)
end)
