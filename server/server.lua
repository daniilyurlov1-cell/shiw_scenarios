local RSGCore = exports['rsg-core']:GetCoreObject()

RegisterCommand('scenarios', function(source)
    local _source = source
    TriggerClientEvent("xakra_scenarios:open_menu", _source)
end, false)

-- Опционально: можно добавить проверку прав
-- RegisterCommand('scenarios', function(source)
--     local _source = source
--     local Player = RSGCore.Functions.GetPlayer(_source)
--     if Player then
--         TriggerClientEvent("xakra_scenarios:open_menu", _source)
--     end
-- end, false)