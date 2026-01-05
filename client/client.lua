local RSGCore = exports['rsg-core']:GetCoreObject()

-- ============================================
-- ПЕРЕМЕННЫЕ
-- ============================================
local CancelPrompt = nil
local isInScenario = false
local currentScenarioName = ""

-- ============================================
-- ФУНКЦИЯ УВЕДОМЛЕНИЙ
-- ============================================
local function Notify(text, notifyType)
    local iconType = "info"
    
    if notifyType == "error" then
        iconType = "warning"
    elseif notifyType == "success" then
        iconType = "check"
    end
    
    TriggerEvent("bln_notify:send", {
        title = Config.Texts["NotifyTitle"] or "Сценарии",
        description = text,
        icon = iconType,
        placement = "middle-left"
    })
end

-- Вспомогательная функция для создания строк
function CreateVarString(p0, p1, variadic)
    return Citizen.InvokeNative(0xFA925AC00EB830B9, p0, p1, variadic, Citizen.ResultAsLong())
end

-- ============================================
-- СОЗДАНИЕ ПРОМПТА (ПРАВИЛЬНЫЙ СПОСОБ)
-- ============================================
local function CreateCancelPrompt()
    if CancelPrompt then return end
    
    CancelPrompt = PromptRegisterBegin()
    PromptSetControlAction(CancelPrompt, 0xF3830D8E) -- J key
    PromptSetText(CancelPrompt, CreateVarString(10, 'LITERAL_STRING', 'Остановить'))
    PromptSetEnabled(CancelPrompt, false)
    PromptSetVisible(CancelPrompt, false)
    PromptSetHoldMode(CancelPrompt, false)
    PromptSetStandardMode(CancelPrompt, true) -- ВАЖНО для RedM
    PromptRegisterEnd(CancelPrompt)
    
    print("^2[Scenarios] Cancel prompt создан^7")
end

-- Инициализация промпта при старте
Citizen.CreateThread(function()
    Citizen.Wait(1000)
    CreateCancelPrompt()
end)

-- ============================================
-- ИНИЦИАЛИЗАЦИЯ MENUDATA
-- ============================================
MenuData = {}

TriggerEvent('rsg-menubase:getData', function(data)
    MenuData = data
end)

local menuLoaded = false
Citizen.CreateThread(function()
    local timeout = 0
    while not menuLoaded and timeout < 100 do
        Citizen.Wait(100)
        timeout = timeout + 1
        
        if MenuData and MenuData.Open then
            menuLoaded = true
            print("^2[Scenarios] MenuData загружен успешно^7")
        end
    end
    
    if not menuLoaded then
        print("^1[Scenarios] КРИТИЧЕСКАЯ ОШИБКА: MenuData не загружен!^7")
        Notify("Ошибка загрузки меню", "error")
    end
end)

-- ============================================
-- DATAVIEW FUNCTIONS
-- ============================================

local _strblob = string.blob or function(length)
    return string.rep("\0", math.max(40 + 1, length))
end

DataView = {
    EndBig = ">",
    EndLittle = "<",
    Types = {
        Int8 = { code = "i1", size = 1 },
        Uint8 = { code = "I1", size = 1 },
        Int16 = { code = "i2", size = 2 },
        Uint16 = { code = "I2", size = 2 },
        Int32 = { code = "i4", size = 4 },
        Uint32 = { code = "I4", size = 4 },
        Int64 = { code = "i8", size = 8 },
        Uint64 = { code = "I8", size = 8 },
        LuaInt = { code = "j", size = 8 }, 
        UluaInt = { code = "J", size = 8 }, 
        LuaNum = { code = "n", size = 8}, 
        Float32 = { code = "f", size = 4 },
        Float64 = { code = "d", size = 8 }, 
        String = { code = "z", size = -1, }, 
    },
    FixedTypes = {
        String = { code = "c", size = -1, },
        Int = { code = "i", size = -1, },
        Uint = { code = "I", size = -1, },
    },
}
DataView.__index = DataView
local function _ib(o, l, t) return ((t.size < 0 and true) or (o + (t.size - 1) <= l)) end
local function _ef(big) return (big and DataView.EndBig) or DataView.EndLittle end
local SetFixed = nil

function DataView.ArrayBuffer(length)
    return setmetatable({
        offset = 1, length = length, blob = _strblob(length)
    }, DataView)
end

function DataView.Wrap(blob)
    return setmetatable({
        offset = 1, blob = blob, length = blob:len(),
    }, DataView)
end

function DataView:Buffer() return self.blob end
function DataView:ByteLength() return self.length end
function DataView:ByteOffset() return self.offset end

function DataView:SubView(offset)
    return setmetatable({
        offset = offset, blob = self.blob, length = self.length,
    }, DataView)
end

for label,datatype in pairs(DataView.Types) do
    DataView["Get" .. label] = function(self, offset, endian)
        local o = self.offset + offset
        if _ib(o, self.length, datatype) then
            local v,_ = string.unpack(_ef(endian) .. datatype.code, self.blob, o)
            return v
        end
        return nil
    end

    DataView["Set" .. label] = function(self, offset, value, endian)
        local o = self.offset + offset
        if _ib(o, self.length, datatype) then
            return SetFixed(self, o, value, _ef(endian) .. datatype.code)
        end
        return self
    end
    if datatype.size >= 0 and string.packsize(datatype.code) ~= datatype.size then
        local msg = "Pack size of %s (%d) does not match cached length: (%d)"
        error(msg:format(label, string.packsize(fmt[#fmt]), datatype.size))
        return nil
    end
end

for label,datatype in pairs(DataView.FixedTypes) do
    DataView["GetFixed" .. label] = function(self, offset, typelen, endian)
        local o = self.offset + offset
        if o + (typelen - 1) <= self.length then
            local code = _ef(endian) .. "c" .. tostring(typelen)
            local v,_ = string.unpack(code, self.blob, o)
            return v
        end
        return nil
    end
    DataView["SetFixed" .. label] = function(self, offset, typelen, value, endian)
        local o = self.offset + offset
        if o + (typelen - 1) <= self.length then
            local code = _ef(endian) .. "c" .. tostring(typelen)
            return SetFixed(self, o, value, code)
        end
        return self
    end
end

SetFixed = function(self, offset, value, code)
    local fmt = { }
    local values = { }
    if self.offset < offset then
        local size = offset - self.offset
        fmt[#fmt + 1] = "c" .. tostring(size)
        values[#values + 1] = self.blob:sub(self.offset, size)
    end
    fmt[#fmt + 1] = code
    values[#values + 1] = value
    local ps = string.packsize(fmt[#fmt])
    if (offset + ps) <= self.length then
        local newoff = offset + ps
        local size = self.length - newoff + 1
        fmt[#fmt + 1] = "c" .. tostring(size)
        values[#values + 1] = self.blob:sub(newoff, self.length)
    end
    self.blob = string.pack(table.concat(fmt, ""), table.unpack(values))
    self.length = self.blob:len()
    return self
end

DataStream = { }
DataStream.__index = DataStream

function DataStream.New(view)
    return setmetatable({ view = view, offset = 0, }, DataStream)
end

for label,datatype in pairs(DataView.Types) do
    DataStream[label] = function(self, endian, align)
        local o = self.offset + self.view.offset
        if not _ib(o, self.view.length, datatype) then
            return nil
        end
        local v,no = string.unpack(_ef(endian) .. datatype.code, self.view:Buffer(), o)
        if align then
            self.offset = self.offset + math.max(no - o, align)
        else
            self.offset = no - self.view.offset
        end
        return v
    end
end

-- ============================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================
function TaskStartScenarioInPlaceHash(ped, hash, p1, p2, p3, p4, p5)
    return Citizen.InvokeNative(0x524B54361229154F, ped, hash, p1, p2, p3, p4, p5)
end

function GetScenarioPointCoords(id, p1)
    return Citizen.InvokeNative(0xA8452DD321607029, id, p1)
end

function GetScenarioPointType(id)
    return Citizen.InvokeNative(0xA92450B5AE687AAF, id)
end

-- ============================================
-- ФУНКЦИИ УПРАВЛЕНИЯ ПРОМПТОМ
-- ============================================
local function ShowCancelPrompt()
    if CancelPrompt then
        PromptSetEnabled(CancelPrompt, true)
        PromptSetVisible(CancelPrompt, true)
    end
end

local function HideCancelPrompt()
    if CancelPrompt then
        PromptSetEnabled(CancelPrompt, false)
        PromptSetVisible(CancelPrompt, false)
    end
end

-- ============================================
-- ПЛАВНАЯ ОСТАНОВКА СЦЕНАРИЯ
-- ============================================
local function StopScenarioSmooth()
    if not isInScenario then return end
    
    isInScenario = false
    currentScenarioName = ""
    
    -- Плавный выход из сценария
    ClearPedTasks(PlayerPedId())
    
    -- Скрываем промпт
    HideCancelPrompt()
    
    Notify("Сценарий остановлен", "info")
end

-- ============================================
-- ОСНОВНОЕ СОБЫТИЕ ОТКРЫТИЯ МЕНЮ
-- ============================================
RegisterNetEvent('xakra_scenarios:open_menu')
AddEventHandler('xakra_scenarios:open_menu', function()
    -- Проверка что MenuData загружен
    if not MenuData or not MenuData.Open then
        print("^1[Scenarios] Ошибка: MenuData не загружен!^7")
        Notify("Ошибка загрузки меню", "error")
        return
    end
    
    MenuData.CloseAll()
    local scenario_elements = {}
    local player = PlayerPedId()

    local DataStruct = DataView.ArrayBuffer(256 * 4)
    local is_data_exists = Citizen.InvokeNative(0x345EC3B7EBDE1CB5, GetEntityCoords(PlayerPedId()), 2.0, DataStruct:Buffer(), 10)
    
    print("^3[Scenarios] Найдено точек сценариев: " .. tostring(is_data_exists) .. "^7")
    
    if is_data_exists ~= false and is_data_exists > 0 then
        for i = 1, is_data_exists, 1 do
            local scenario = DataStruct:GetInt32(8 * i)
            local scenario_hash = GetScenarioPointType(scenario)
            
            for _, v in pairs(Config.Scenarios) do
                if GetHashKey(v[1]) == scenario_hash then
                    print("^2[Scenarios] Найдено совпадение: " .. v[1] .. "^7")
                    scenario_elements[#scenario_elements + 1] = {
                        label = v[2] or v[1],
                        value = scenario,
                        hash = scenario
                    }
                end
            end
        end
        
        Citizen.Wait(200)
        
        if #scenario_elements > 0 then
            print("^2[Scenarios] Открываем меню с " .. #scenario_elements .. " элементами^7")
            
            MenuData.Open('default', GetCurrentResourceName(), 'scenarios_menu', {
                title = Config.Texts["titleMenu"],
                subtext = Config.Texts["subtitleMenu"],
                align = "top-left",
                elements = scenario_elements,
            }, 
            function(data, menu)
                -- При выборе элемента
                if data.current then
                    menu.close() -- Закрытие меню
                    
                    local ped = PlayerPedId()
                    local scenarioHash = data.current.hash
                    local scenarioLabel = data.current.label
                    
                    -- Очищаем текущие задачи
                    ClearPedTasks(ped)
                    Citizen.Wait(100)
                    
                    -- Запускаем сценарий с duration = -1.0 (бесконечный цикл)
                    -- Параметры: ped, scenarioPoint, "", duration, playEnterAnim, playExitAnim, p6, p7, p8, skipStartAnim
                    TaskUseScenarioPoint(ped, scenarioHash, "", -1.0, true, false, 0, false, -1.0, true)
                    
                    isInScenario = true
                    currentScenarioName = scenarioLabel
                    
                    -- Показываем промпт для остановки
                    Citizen.Wait(500)
                    ShowCancelPrompt()
                    
                    Notify("Выполняется: " .. scenarioLabel, "success")
                    print("^2[Scenarios] Запущен сценарий: " .. scenarioLabel .. "^7")
                end
            end, 
            function(data, menu)
                -- При закрытии меню через ESC
                menu.close()
            end)
        else
            Notify("Нет доступных сценариев рядом", "error")
        end
    else
        Notify(Config.Texts["NotifySubtitle"], "error")
    end
end)

-- ============================================
-- ОБРАБОТКА ПРОМПТА И КНОПКИ J
-- ============================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        if isInScenario and CancelPrompt then
            -- Проверяем нажатие через промпт
            if PromptHasStandardModeCompleted(CancelPrompt, 0) then
                print("^3[Scenarios] Промпт нажат, останавливаем сценарий...^7")
                StopScenarioSmooth()
                Citizen.Wait(1000)
            end
        end
    end
end)

-- ============================================
-- ОЧИСТКА ПРИ ОСТАНОВКЕ РЕСУРСА
-- ============================================
AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    
    if MenuData and MenuData.CloseAll then
        MenuData.CloseAll()
    end
    
    if isInScenario then
        ClearPedTasks(PlayerPedId())
    end
    
    -- Удаление промпта
    if CancelPrompt then
        PromptDelete(CancelPrompt)
        CancelPrompt = nil
    end
end)

-- ============================================
-- ПРИВЯЗКА КЛАВИШИ F6 
-- ============================================
local menuCooldown = false

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        -- F6 для открытия меню
        if IsControlJustPressed(0, 0x3C0A40F2) and not menuCooldown and not isInScenario then
            menuCooldown = true
            print("^3[Scenarios] F6 нажата, открываем меню...^7")
            TriggerEvent('xakra_scenarios:open_menu')
            
            Citizen.SetTimeout(500, function()
                menuCooldown = false
            end)
        end
        
        -- J для остановки (резервный способ если промпт не работает)
        if isInScenario and IsControlJustPressed(0, 0xF3830D8E) then
            print("^3[Scenarios] J нажата, останавливаем сценарий...^7")
            StopScenarioSmooth()
            Citizen.Wait(1000)
        end
    end
end)

-- ============================================
-- КОМАНДЫ
-- ============================================
RegisterCommand('scenariosmenu', function()
    if not isInScenario then
        TriggerEvent('xakra_scenarios:open_menu')
    else
        Notify("Сначала остановите текущий сценарий (J)", "error")
    end
end, false)

RegisterCommand('stopscenario', function()
    StopScenarioSmooth()
end, false)