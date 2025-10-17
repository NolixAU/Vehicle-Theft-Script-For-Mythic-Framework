local wheelBones = {
    { name = 'wheel_lf', fallbackIndex = 0 },
    { name = 'wheel_rf', fallbackIndex = 1 },
    { name = 'wheel_lr', fallbackIndex = 2 },
    { name = 'wheel_rr', fallbackIndex = 3 },
}

local Callbacks, Minigame, Notification, Targeting
local activeAttempt = false
local heldWheelProp

local SET_VEHICLE_WHEEL_HAS_TIRE = 0x6E13FC662B882D1D

local function vehicleWheelHasTire(vehicle, index)
    if GetVehicleWheelHasTire then
        return GetVehicleWheelHasTire(vehicle, index)
    end
    return not IsVehicleTyreBurst(vehicle, index, true)
end

local function setVehicleWheelHasTire(entity, index, hasTire)
    if SetVehicleWheelHasTire then
        SetVehicleWheelHasTire(entity, index, hasTire)
        return
    end
    if Citizen and Citizen.InvokeNative then
        Citizen.InvokeNative(SET_VEHICLE_WHEEL_HAS_TIRE, entity, index, hasTire)
    end
end

local function removeVehicleWheel(entity, index)
    if not DoesEntityExist(entity) then return end

    FreezeEntityPosition(entity, true)
    setVehicleWheelHasTire(entity, index, false)
    SetVehicleTyreBurst(entity, index, true, 1000.0)

    BreakOffVehicleWheel(entity, index, true, true, true, false)

    Wait(1000)
    FreezeEntityPosition(entity, false)
end

WheelTheft = WheelTheft or {}
WheelTheft._lastWheel = nil

local function getPlayerPed()
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.ped then
        return LocalPlayer.state.ped
    end
    return PlayerPedId()
end

local function RetrieveComponents()
    Callbacks = exports['mythic-base']:FetchComponent('Callbacks')
    Minigame = exports['mythic-base']:FetchComponent('Minigame')
    Notification = exports['mythic-base']:FetchComponent('Notification')
    Targeting = exports['mythic-base']:FetchComponent('Targeting')
end

AddEventHandler('WheelTheft:Shared:DependencyUpdate', RetrieveComponents)

AddEventHandler('Core:Shared:Ready', function()
    exports['mythic-base']:RequestDependencies('WheelTheft', {
        'Callbacks',
        'Minigame',
        'Notification',
        'Targeting',
    }, function(error)
        if #error > 0 then return end
        RetrieveComponents()
    end)
end)

local function getWheelFromEntity(entity, hitCoords)
    if not entity or not DoesEntityExist(entity) then
        WheelTheft._lastWheel = nil
        return nil
    end

    if hitCoords and type(hitCoords) == 'table' and hitCoords.x then
        hitCoords = vector3(hitCoords.x, hitCoords.y, hitCoords.z)
    elseif hitCoords and type(hitCoords) ~= 'vector3' then
        hitCoords = nil
    end

    local pedCoords = GetEntityCoords(getPlayerPed())
    local closest, closestDist = nil, 999.0

    for _, bone in ipairs(wheelBones) do
        local boneIndex = GetEntityBoneIndexByName(entity, bone.name)
        if boneIndex ~= -1 then
            local boneCoords = GetWorldPositionOfEntityBone(entity, boneIndex)
            local wheelIndex = bone.fallbackIndex
            if GetVehicleWheelIndexFromBoneIndex then
                local resolved = GetVehicleWheelIndexFromBoneIndex(entity, boneIndex)
                if resolved ~= -1 then wheelIndex = resolved end
            end
            local dist = #(boneCoords - pedCoords)
            if dist < closestDist then
                closest = { entity = entity, coords = boneCoords, bone = bone.name, wheelIndex = wheelIndex }
                closestDist = dist
            end
        end
    end

    WheelTheft._lastWheel = closest
    return closest
end

function WheelTheft:IsNearWheel(entityData)
    if not entityData or not entityData.entity then return false end
    local wheel = getWheelFromEntity(entityData.entity, entityData.endCoords)
    if not wheel then return false end
    return #(GetEntityCoords(getPlayerPed()) - wheel.coords) <= 2.0
end

function WheelTheft:GetLastWheel()
    if self._lastWheel and self._lastWheel.entity and DoesEntityExist(self._lastWheel.entity) then
        return self._lastWheel
    end
    return nil
end

local function cleanupHeldWheel()
    if DoesEntityExist(heldWheelProp) then
        DeleteEntity(heldWheelProp)
    end
    heldWheelProp = nil
    ClearPedSecondaryTask(getPlayerPed())
end

local function holdwheel()
    local playerPed = getPlayerPed()
    if not IsEntityPlayingAnim(playerPed, "anim@heists@box_carry@", "idle", 3) then
        local animDict = "anim@heists@box_carry@"
        local animName = "idle"
        RequestAnimDict(animDict)
        while not HasAnimDictLoaded(animDict) do
            Wait(0)
        end
        TaskPlayAnim(playerPed, animDict, animName, 8.0, 1.0, -1, 49, 0, false, false, false)
    end
end

local function attachHeldWheel()
    cleanupHeldWheel()
    local ped = getPlayerPed()

    RequestModel(`prop_wheel_01`)
    while not HasModelLoaded(`prop_wheel_01`) do Wait(0) end

    RequestAnimDict("anim@heists@box_carry@")
    while not HasAnimDictLoaded("anim@heists@box_carry@") do Wait(0) end

    TaskPlayAnim(ped, "anim@heists@box_carry@", "idle", 8.0, -8.0, -1, 49, 0.0, false, false, false)

    heldWheelProp = CreateObject(`prop_wheel_01`, 0.0, 0.0, 0.0, true, true, false)

    AttachEntityToEntity(
        heldWheelProp,
        ped,
        GetPedBoneIndex(ped, 28422), 
        0.0,
        0.0,   
        0.10, 
        0.0,   
        90.0,  
        0.0,  
        true, true, false, true, 1, true
    )

    SetModelAsNoLongerNeeded(`prop_wheel_01`)
end

RegisterNetEvent('WheelTheft:Client:DetachWheel', cleanupHeldWheel)
RegisterNetEvent('WheelTheft:Client:ToggleWheelCarry', function()
    if DoesEntityExist(heldWheelProp) then
        cleanupHeldWheel()
        return
    end
    attachHeldWheel()
end)
RegisterNetEvent('WheelTheft:Client:UseWheelItem', function()
    TriggerEvent('WheelTheft:Client:ToggleWheelCarry')
end)

local function applyRemovedWheels(entity, removedWheels)
    if not DoesEntityExist(entity) or type(removedWheels) ~= 'table' then return end
    for wheelIndex, removed in pairs(removedWheels) do
        if removed then
            local index = tonumber(wheelIndex) or wheelIndex
            removeVehicleWheel(entity, index)
        end
    end
end

local function handleWheelStateChange(bagName, key, value)
    if key ~= 'wheelTheftRemoved' then return end
    local idString = bagName:match('entity:(%d+)')
    if not idString then return end
    local netId = tonumber(idString)
    if not netId then return end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and entity ~= 0 then
        applyRemovedWheels(entity, value)
        return
    end
    CreateThread(function()
        for _ = 1, 50 do
            Wait(100)
            entity = NetworkGetEntityFromNetworkId(netId)
            if entity and entity ~= 0 then
                applyRemovedWheels(entity, value)
                break
            end
        end
    end)
end

AddStateBagChangeHandler('wheelTheftRemoved', nil, handleWheelStateChange)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupHeldWheel()
end)

local function canAttempt(entityData)
    if activeAttempt then return false, 'Already removing a wheel' end
    if not LocalPlayer or not LocalPlayer.state or not LocalPlayer.state.loggedIn or LocalPlayer.state.isDead then
        return false, 'Cannot do that right now'
    end
    if IsPedInAnyVehicle(getPlayerPed(), false) then
        return false, 'Exit the vehicle first'
    end

    local wheel = WheelTheft:GetLastWheel() or (entityData and getWheelFromEntity(entityData.entity, entityData.endCoords))
    if not wheel then return false, 'Need to focus on a wheel' end
    if #(GetEntityCoords(getPlayerPed()) - wheel.coords) > 2.0 then
        return false, 'Move closer to the wheel'
    end
    if GetVehiclePedIsIn(getPlayerPed(), true) == entityData.entity then
        return false, 'Cannot remove while inside vehicle'
    end
    if not vehicleWheelHasTire(entityData.entity, wheel.wheelIndex) then
        return false, 'That wheel is already missing'
    end
    return true, wheel
end

AddEventHandler('WheelTheft:Client:Attempt', function(entityData)
    local canDo, wheelDataOrReason = canAttempt(entityData)
    if not canDo then
        Notification:Error(wheelDataOrReason or 'Cannot do that right now', 4000, 'wrench')
        return
    end

    local wheelData = wheelDataOrReason
    activeAttempt = true

    Minigame.Play:RoundSkillbar(1.1, 6, {
        onSuccess = function()
            local ped = getPlayerPed()
            if #(GetEntityCoords(ped) - wheelData.coords) > 2.0 then
                Notification:Error('You moved too far away', 4000, 'wrench')
                activeAttempt = false
                return
            end

            local netId = VehToNet(wheelData.entity)
            if not netId or netId == 0 then
                Notification:Error('Vehicle is no longer available', 4000, 'wrench')
                activeAttempt = false
                return
            end

            Callbacks:ServerCallback('WheelTheft:RemoveWheel', {
                vehicle = netId,
                wheel = wheelData.bone,
                wheelIndex = wheelData.wheelIndex,
            }, function(success, message)
                if success then
                    Notification:Success(message or 'You removed a wheel', 4000, 'wrench')
                    removeVehicleWheel(wheelData.entity, wheelData.wheelIndex)
                else
                    Notification:Error(message or 'Failed to remove wheel', 4000, 'wrench')
                end
                activeAttempt = false
                Wait(500)
            end)
        end,
        onFail = function()
            Notification:Error('Failed to remove wheel', 4000, 'wrench')
            activeAttempt = false
            Wait(500)
        end,
    }, {
        useWhileDead = false,
        vehicle = false,
        controlDisables = {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        },
        animation = {
            animDict = 'mp_car_bomb',
            anim = 'car_bomb_mechanic',
            flags = 49,
        },
    })
end)

RegisterNetEvent('WheelTheft:Client:UseTorqueWrench', function()
    if activeAttempt then Notification:Error('Already removing a wheel', 4000, 'wrench') return end
    if not Targeting then Notification:Error('Cannot do that right now', 4000, 'wrench') return end

    local entityData = Targeting:GetEntityPlayerIsLookingAt()
    if not entityData or not entityData.entity or GetEntityType(entityData.entity) ~= 2 then
        Notification:Error('Focus on a vehicle wheel first', 4000, 'wrench')
        return
    end
    if not WheelTheft:IsNearWheel(entityData) then
        Notification:Error('Focus on a vehicle wheel first', 4000, 'wrench')
        return
    end
    TriggerEvent('WheelTheft:Client:Attempt', entityData)
end)

RegisterNetEvent('WheelTheft:Client:WheelRemoved', function(netId, wheelIndex)
    local index = tonumber(wheelIndex)
    if not netId or not index then return end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and entity ~= 0 then
        removeVehicleWheel(entity, index)
    end
end)
