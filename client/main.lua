local UseTarget = GetConvar('UseTarget', 'false') == 'true'
local InApartment = false
local ClosestHouse = nil
local CurrentApartment = nil
local IsOwned = false
local CurrentDoorBell = 0
local CurrentOffset = 0
local HouseObj = {}
local POIOffsets = nil
local RangDoorbell = nil

-- target variables
local InApartmentTargets = {}

local function RegisterInApartmentTarget(targetKey, coords, heading, options)
    if not InApartment then
        return
    end

    if InApartmentTargets[targetKey] and InApartmentTargets[targetKey].created then
        return
    end

    local boxName = 'inApartmentTarget_' .. targetKey
    if UseTarget then
         exports['qb-target']:AddBoxZone(boxName, coords, 1.5, 1.5, {
             name = boxName,
             heading = heading,
             minZ = coords.z - 1.0,
             maxZ = coords.z + 5.0,
             debugPoly = false,
         }, {
             options = options,
             distance = 1
         })
    else
        exports['qb-interact']:addInteractZone({
            name = boxName,
            coords = vector3(coords.x, coords.y, coords.z + 1),
            length = 1.5,
            width = 1.5,
            heading = heading or 180.0,
            height = 3.0,
            debugPoly = false,
            options = options
        })
    end
    InApartmentTargets[targetKey] = InApartmentTargets[targetKey] or {}
    InApartmentTargets[targetKey].created = true
end

local function openHouseAnim()
    exports['qb-core']:RequestAnimDict('anim@heists@keycard@')
    TaskPlayAnim(PlayerPedId(), 'anim@heists@keycard@', 'exit', 5.0, 1.0, -1, 16, 0, 0, 0, 0)
    Wait(400)
    ClearPedTasks(PlayerPedId())
end

local function DeleteApartmentsEntranceTargets()
    if Apartments.Locations and next(Apartments.Locations) then
        for id, apartment in pairs(Apartments.Locations) do
            if UseTarget then
                exports['qb-target']:RemoveZone('apartmentEntrance_' .. id)
            else
                exports['qb-interact']:removeInteractZones('apartmentEntrance_' .. id)
            end
            apartment.polyzoneBoxData.created = false
        end
    end
end

local function DeleteInApartmentTargets()
    if InApartmentTargets and next(InApartmentTargets) then
        for id, apartmentTarget in pairs(InApartmentTargets) do
            if UseTarget then
                exports['qb-target']:RemoveZone('inApartmentTarget_' .. id)
            else
                exports['qb-interact']:removeInteractZones('inApartmentTarget_' .. id)
            end
        end
    end
    InApartmentTargets = {}
end


local function LeaveApartment(house)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'houses_door_open', 0.1)
    openHouseAnim()
    TriggerServerEvent('qb-apartments:returnBucket')
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(10) end
    exports['qb-interior']:DespawnInterior(HouseObj, function()
        TriggerEvent('qb-weathersync:client:EnableSync')
        SetEntityCoords(PlayerPedId(), Apartments.Locations[house].coords.enter.x, Apartments.Locations[house].coords.enter.y, Apartments.Locations[house].coords.enter.z)
        SetEntityHeading(PlayerPedId(), Apartments.Locations[house].coords.enter.w)
        Wait(1000)
        TriggerServerEvent('apartments:server:RemoveObject', CurrentApartment, house)
        TriggerServerEvent('qb-apartments:server:SetInsideMeta', CurrentApartment, false)
        CurrentApartment = nil
        InApartment = false
        CurrentOffset = 0
        DoScreenFadeIn(1000)
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'houses_door_close', 0.1)
        TriggerServerEvent('apartments:server:setCurrentApartment', nil)
        DeleteInApartmentTargets()
    end)
end

local function SetInApartmentTargets()
    if not POIOffsets then
        -- do nothing
        return
    end
    local entrancePos = vector3(Apartments.Locations[ClosestHouse].coords.enter.x + POIOffsets.exit.x, Apartments.Locations[ClosestHouse].coords.enter.y + POIOffsets.exit.y, Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset + POIOffsets.exit.z)
    local stashPos = vector3(Apartments.Locations[ClosestHouse].coords.enter.x - POIOffsets.stash.x, Apartments.Locations[ClosestHouse].coords.enter.y - POIOffsets.stash.y, Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset + POIOffsets.stash.z)
    local outfitsPos = vector3(Apartments.Locations[ClosestHouse].coords.enter.x - POIOffsets.clothes.x, Apartments.Locations[ClosestHouse].coords.enter.y - POIOffsets.clothes.y, Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset + POIOffsets.clothes.z)
    local logoutPos = vector3(Apartments.Locations[ClosestHouse].coords.enter.x - POIOffsets.logout.x, Apartments.Locations[ClosestHouse].coords.enter.y + POIOffsets.logout.y, Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset + POIOffsets.logout.z)
    RegisterInApartmentTarget('entrancePos', entrancePos, 0, {
        {
            type = 'client',
            event = 'apartments:client:OpenDoor',
            icon = 'fas fa-door-open',
            label = Lang:t('text.open_door'),
        },
        {
            icon = 'fas fa-door-open',
            label = Lang:t('text.leave'),
            action = function()
                LeaveApartment(ClosestHouse)
            end,
        },
    })
    RegisterInApartmentTarget('stashPos', stashPos, 0, {
        {
            icon = 'fas fa-box-open',
            label = Lang:t('text.open_stash'),
            action = function()
                TriggerServerEvent('apartments:server:openStash', CurrentApartment)
            end,
        },
    })
    RegisterInApartmentTarget('outfitsPos', outfitsPos, 0, {
        {
            icon = 'fas fa-tshirt',
            label = Lang:t('text.change_outfit'),
            action = function()
                TriggerServerEvent('InteractSound_SV:PlayOnSource', 'Clothes1', 0.4)
                TriggerEvent('qb-clothing:client:openOutfitMenu')
            end,
        },
    })
    RegisterInApartmentTarget('logoutPos', logoutPos, 0, {
        {
            type = 'server',
            event = 'qb-houses:server:LogoutLocation',
            icon = 'fas fa-sign-out-alt',
            label = Lang:t('text.logout'),
        },
    })
end

-- utility functions

local function EnterApartment(house, apartmentId, new)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'houses_door_open', 0.1)
    openHouseAnim()
    Wait(250)
    exports['qb-core']:TriggerCallback('apartments:GetApartmentOffset', function(offset)
        if offset == nil or offset == 0 then
            exports['qb-core']:TriggerCallback('apartments:GetApartmentOffsetNewOffset', function(newoffset)
                if newoffset > 230 then
                    newoffset = 210
                end
                CurrentOffset = newoffset
                TriggerServerEvent('apartments:server:AddObject', apartmentId, house, CurrentOffset)
                local coords = { x = Apartments.Locations[house].coords.enter.x, y = Apartments.Locations[house].coords.enter.y, z = Apartments.Locations[house].coords.enter.z - CurrentOffset }
                local data = exports['qb-interior']:CreateApartmentFurnished(coords)
                Wait(100)
                HouseObj = data[1]
                POIOffsets = data[2]
                InApartment = true
                CurrentApartment = apartmentId
                ClosestHouse = house
                RangDoorbell = nil
                Wait(500)
                TriggerEvent('qb-weathersync:client:DisableSync')
                Wait(100)
                TriggerServerEvent('qb-apartments:server:SetInsideMeta', house, apartmentId, true, false)
                TriggerServerEvent('InteractSound_SV:PlayOnSource', 'houses_door_close', 0.1)
                TriggerServerEvent('apartments:server:setCurrentApartment', CurrentApartment)
            end, house)
        else
            if offset > 230 then
                offset = 210
            end
            CurrentOffset = offset
            TriggerServerEvent('InteractSound_SV:PlayOnSource', 'houses_door_open', 0.1)
            TriggerServerEvent('apartments:server:AddObject', apartmentId, house, CurrentOffset)
            local coords = { x = Apartments.Locations[ClosestHouse].coords.enter.x, y = Apartments.Locations[ClosestHouse].coords.enter.y, z = Apartments.Locations[ClosestHouse].coords.enter.z - CurrentOffset }
            local data = exports['qb-interior']:CreateApartmentFurnished(coords)
            Wait(100)
            HouseObj = data[1]
            POIOffsets = data[2]
            InApartment = true
            CurrentApartment = apartmentId
            Wait(500)
            TriggerEvent('qb-weathersync:client:DisableSync')
            Wait(100)
            TriggerServerEvent('qb-apartments:server:SetInsideMeta', house, apartmentId, true, true)
            TriggerServerEvent('InteractSound_SV:PlayOnSource', 'houses_door_close', 0.1)
            TriggerServerEvent('apartments:server:setCurrentApartment', CurrentApartment)
        end

        if new ~= nil then
            if new then
                TriggerEvent('qb-interior:client:SetNewState', true)
            else
                TriggerEvent('qb-interior:client:SetNewState', false)
            end
        else
            TriggerEvent('qb-interior:client:SetNewState', false)
        end
    end, apartmentId)
    repeat Wait(100) until InApartment == true
    SetInApartmentTargets()
end



function MenuOwners()
    exports['qb-core']:TriggerCallback('apartments:GetAvailableApartments', function(apartments)
        if next(apartments) == nil then
            exports['qb-core']:Notify(Lang:t('error.nobody_home'), 'error', 3500)
            CloseMenuFull()
        else
            local apartmentMenu = {
                {
                    header = Lang:t('text.tennants'),
                    isMenuHeader = true
                }
            }

            for k, v in pairs(apartments) do
                apartmentMenu[#apartmentMenu + 1] = {
                    header = v,
                    txt = '',
                    params = {
                        event = 'apartments:client:RingMenu',
                        args = {
                            apartmentId = k
                        }
                    }

                }
            end

            apartmentMenu[#apartmentMenu + 1] = {
                header = Lang:t('text.close_menu'),
                txt = '',
                params = {
                    event = 'qb-menu:client:closeMenu'
                }

            }
            exports['qb-menu']:openMenu(apartmentMenu)
        end
    end, ClosestHouse)
end

function CloseMenuFull()
    exports['qb-menu']:closeMenu()
end

-- Event Handlers

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if HouseObj ~= nil then
            exports['qb-interior']:DespawnInterior(HouseObj, function()
                CurrentApartment = nil
                TriggerEvent('qb-weathersync:client:EnableSync')
                DoScreenFadeIn(500)
                while not IsScreenFadedOut() do
                    Wait(10)
                end
                SetEntityCoords(PlayerPedId(), Apartments.Locations[ClosestHouse].coords.enter.x, Apartments.Locations[ClosestHouse].coords.enter.y, Apartments.Locations[ClosestHouse].coords.enter.z)
                SetEntityHeading(PlayerPedId(), Apartments.Locations[ClosestHouse].coords.enter.w)
                Wait(1000)
                InApartment = false
                DoScreenFadeIn(1000)
            end)
        end

        DeleteApartmentsEntranceTargets()
        DeleteInApartmentTargets()
    end
end)
-- Events

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    CurrentApartment = nil
    InApartment = false
    CurrentOffset = 0

    DeleteApartmentsEntranceTargets()
    DeleteInApartmentTargets()
end)

RegisterNetEvent('apartments:client:setupSpawnUI', function(cData)
    exports['qb-core']:TriggerCallback('apartments:GetOwnedApartment', function(result)
        if result then
            TriggerEvent('qb-spawn:client:setupSpawns', cData, false, nil)
            TriggerEvent('qb-spawn:client:openUI', true)
            TriggerEvent('apartments:client:SetHomeBlip', result.type)
        else
            if Apartments.Starting then
                TriggerEvent('qb-spawn:client:setupSpawns', cData, true, Apartments.Locations)
                TriggerEvent('qb-spawn:client:openUI', true)
            else
                TriggerEvent('qb-spawn:client:setupSpawns', cData, false, nil)
                TriggerEvent('qb-spawn:client:openUI', true)
                TriggerEvent('apartments:client:SetHomeBlip', nil)
            end
        end
    end, cData.citizenid)
end)

RegisterNetEvent('apartments:client:SpawnInApartment', function(apartmentId, apartment)
    local pos = GetEntityCoords(PlayerPedId())
    if RangDoorbell ~= nil then
        local doorbelldist = #(pos - vector3(Apartments.Locations[RangDoorbell].coords.enter.x, Apartments.Locations[RangDoorbell].coords.enter.y, Apartments.Locations[RangDoorbell].coords.enter.z))
        if doorbelldist > 5 then
            exports['qb-core']:Notify(Lang:t('error.to_far_from_door'))
            return
        end
    end
    ClosestHouse = apartment
    EnterApartment(apartment, apartmentId, true)
    IsOwned = apartment
end)

RegisterNetEvent('qb-apartments:client:LastLocationHouse', function(apartmentType, apartmentId)
    ClosestHouse = apartmentType
    EnterApartment(apartmentType, apartmentId, false)
end)

local blip = {}
local function createHomeBlip(home)
    if blip[1] ~= nil then
        RemoveBlip(blip[1])
    end
    blip[1] = AddBlipForCoord(Apartments.Locations[home].coords.enter.x, Apartments.Locations[home].coords.enter.y, Apartments.Locations[home].coords.enter.z)
    if (home == home) then
        SetBlipSprite(blip[1], 475)
        SetBlipCategory(blip[1], 11)
    else
        SetBlipSprite(blip[1], 476)
        SetBlipCategory(blip[1], 10)
    end
    SetBlipDisplay(blip[1], 4)
    SetBlipScale(blip[1], 0.65)
    SetBlipAsShortRange(blip[1], true)
    SetBlipColour(blip[1], 3)
    BeginTextCommandSetBlipName("STRING")
	AddTextComponentString(Apartments.Locations[home].label)
	EndTextCommandSetBlipName(blip[1])
end


RegisterNetEvent('apartments:client:RingMenu', function(data)
    RangDoorbell = ClosestHouse
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'doorbell', 0.1)
    TriggerServerEvent('apartments:server:RingDoor', data.apartmentId, ClosestHouse)
end)

RegisterNetEvent('apartments:client:RingDoor', function(player, _)
    CurrentDoorBell = player
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'doorbell', 0.1)
    exports['qb-core']:Notify(Lang:t('info.at_the_door'))
end)

RegisterNetEvent('apartments:client:DoorbellMenu', function()
    MenuOwners()
end)

RegisterNetEvent('apartments:client:EnterApartment', function()
    exports['qb-core']:TriggerCallback('apartments:GetOwnedApartment', function(result)
        if result ~= nil then
            EnterApartment(ClosestHouse, result.name)
        end
    end)
end)

RegisterNetEvent('apartments:client:UpdateApartment', function()
    local apartmentType = ClosestHouse
    local apartmentLabel = Apartments.Locations[ClosestHouse].label
    local result = exports['qb-core']:TriggerCallback('apartments:GetOwnedApartment')
    if not result then
        TriggerServerEvent("apartments:server:CreateApartment", apartmentType, apartmentLabel, false)
        IsOwned = ClosestHouse
        return
    end
    TriggerServerEvent('apartments:server:UpdateApartment', apartmentType, apartmentLabel)
    IsOwned = ClosestHouse
    createHomeBlip(IsOwned)
end)

RegisterNetEvent('apartments:client:OpenDoor', function()
    if CurrentDoorBell == 0 then
        exports['qb-core']:Notify(Lang:t('error.nobody_at_door'))
        return
    end
    TriggerServerEvent('apartments:server:OpenDoor', CurrentDoorBell, CurrentApartment, ClosestHouse)
    CurrentDoorBell = 0
end)

RegisterNetEvent('apartments:client:LeaveApartment', function()
    LeaveApartment(ClosestHouse)
end)

RegisterNetEvent('apartments:client:OpenStash', function()
    if CurrentApartment then
        TriggerServerEvent('InteractSound_SV:PlayOnSource', 'StashOpen', 0.4)
        TriggerServerEvent('apartments:server:openStash', CurrentApartment, ClosestHouse)
    end
end)

local function init()
    IsOwned = exports['qb-core']:TriggerCallback('apartments:IsOwner')
    if not IsOwned then
        repeat
            Wait(2000)
            IsOwned = exports['qb-core']:TriggerCallback('apartments:IsOwner')
        until IsOwned
    end
    createHomeBlip(IsOwned)
    for k, v in pairs (Apartments.Locations) do
        local options = {
            {
                label = Lang:t('text.enter'),
                action = function()
                    ClosestHouse = k
                    TriggerEvent('apartments:client:EnterApartment')
                end,
                canInteract = function()
                    if IsOwned == k then
                        return true
                    end
                    return false
                end
            },
            {
                icon = 'fas fa-hotel',
                label = Lang:t('text.move_here'),
                action = function()
                    ClosestHouse = k
                    TriggerEvent('apartments:client:UpdateApartment')
                end,
                canInteract = function()
                    if IsOwned == k then
                        return false
                    end
                    return true
                end
            },
            {
                icon = 'fas fa-concierge-bell',
                label = Lang:t('text.ring_doorbell'),
                action = function()
                    ClosestHouse = k
                    TriggerEvent('apartments:client:DoorbellMenu')
                end,
            }
        }
        if UseTarget then
            exports['qb-target']:AddBoxZone('apartmentEntrance_' .. k, v.coords.enter, v.polyzoneBoxData.length, v.polyzoneBoxData.width, {
                name = 'apartmentEntrance_' .. k,
                heading = v.polyzoneBoxData.heading,
                debugPoly = v.polyzoneBoxData.debug,
                minZ = v.polyzoneBoxData.minZ,
                maxZ = v.polyzoneBoxData.maxZ,
            }, {
                options = options,
                distance = v.polyzoneBoxData.distance
            })
        else
            exports['qb-interact']:addInteractZone({
                name = 'apartmentEntrance_' .. k,
                coords = v.coords.enter,
                length = 2,
                width = 2,
                heading = v.polyzoneBoxData.heading,
                debugPoly = v.polyzoneBoxData.debug,
                height = 5.0,
                options = options,
            })
        end
    end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() init() end)
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if PlayerPedId() then
            init()
        end
    end
end)