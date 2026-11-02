--[[
    HorseSettings.lua -- the "make this annoying" options, on the real ESC -> Settings -> General page (the pattern of FS25_ImmersiveWeathering's IWSettingsUI, UIHelper vendored with it). Fun once, annoying later:
    each can be switched off. Saved in modSettings/FS25_HorseDynamics/config.xml, applied to the HorseHitch flags at load and on every change.
      gallopLimit  HorseHitch.GALLOP_LIMIT   a horse that pulls never gallops
      playerCap    HorseHitch.PLAYER_CAP     the load slows you down (walk and run), and the string with you
      pullLimit    HorseHitch.SPEED_LIMITS   a horse is no tractor: its pull is limited (a heavy load hardly gets going), and the same three limits are on
]]
HorseSettings = {}
HorseSettings.DEFAULTS = { gallopLimit = true, playerCap = true, pullLimit = false }
HorseSettings.ORDER = { "gallopLimit", "playerCap", "pullLimit" }
HorseSettings.FLAGS = { gallopLimit = "GALLOP_LIMIT", playerCap = "PLAYER_CAP", pullLimit = "SPEED_LIMITS" }
HorseSettings.config = {}
for name, value in pairs(HorseSettings.DEFAULTS) do
    HorseSettings.config[name] = value
end

-- The HorseHitch flags follow the settings.
function HorseSettings.apply()
    if HorseHitch == nil then
        return
    end
    for name, flag in pairs(HorseSettings.FLAGS) do
        HorseHitch[flag] = HorseSettings.config[name] == true
    end
end

local SCHEMA
local function schema()
    if SCHEMA == nil and XMLSchema ~= nil and XMLValueType ~= nil then
        SCHEMA = XMLSchema.new("FS25_HorseDynamicsConfig")
        for _, name in ipairs(HorseSettings.ORDER) do
            SCHEMA:register(XMLValueType.BOOL, "config#" .. name)
        end
    end
    return SCHEMA
end

function HorseSettings.filePath()
    if getUserProfileAppPath == nil then
        return nil
    end
    local folder = getUserProfileAppPath() .. "modSettings/FS25_HorseDynamics/"
    if createFolder ~= nil then
        createFolder(folder)
    end
    return folder .. "config.xml"
end

function HorseSettings.load()
    local path, s = HorseSettings.filePath(), schema()
    if path == nil or s == nil or XMLFile == nil then
        return
    end
    local xmlFile = XMLFile.loadIfExists("HorseDynamicsConfig", path, s)
    if xmlFile == nil then
        return
    end
    for _, name in ipairs(HorseSettings.ORDER) do
        HorseSettings.config[name] = xmlFile:getValue("config#" .. name, HorseSettings.config[name])
    end
    xmlFile:delete()
end

function HorseSettings.save()
    local path, s = HorseSettings.filePath(), schema()
    if path == nil or s == nil or XMLFile == nil then
        return
    end
    local xmlFile = XMLFile.create("HorseDynamicsConfig", path, "config", s)
    if xmlFile == nil then
        return
    end
    for _, name in ipairs(HorseSettings.ORDER) do
        xmlFile:setValue("config#" .. name, HorseSettings.config[name])
    end
    xmlFile:save()
    xmlFile:delete()
end

-- The page: a section header and one switch each, bound to HorseSettings.config by name (UIHelper autoBind); a change is applied and saved.
HorseSettings.ui = { controls = {}, isInitialized = false }

function HorseSettings.ui:injectUiSettings()
    if g_dedicatedServer ~= nil or self.isInitialized then
        return
    end
    local screen = g_gui ~= nil and g_gui.screenControllers ~= nil and InGameMenu ~= nil and g_gui.screenControllers[InGameMenu] or nil
    local page = screen ~= nil and screen.pageSettings or nil
    if page == nil or UIHelper == nil or UIHelper.createControlsDynamically == nil then
        return
    end
    self.isInitialized = true
    local properties = {}
    for _, name in ipairs(HorseSettings.ORDER) do
        properties[#properties + 1] = { name = name, autoBind = true }
    end
    UIHelper.createControlsDynamically(page, "hd_setting_title", self, properties, "hd_")
    UIHelper.setupAutoBindControls(self, HorseSettings.config, HorseSettings.ui.onSettingsChange)
    self.populateAutoBindControls()
    page.gameSettingsLayout:invalidateLayout()
end

function HorseSettings.ui.onSettingsChange()
    HorseSettings.apply()
    HorseSettings.save()
end

HorseSettings.load()
HorseSettings.apply()

if InGameMenu ~= nil and InGameMenu.onMenuOpened ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil and not HorseSettings.hooked then
    HorseSettings.hooked = true
    InGameMenu.onMenuOpened = Utils.appendedFunction(InGameMenu.onMenuOpened, function()
        HorseSettings.ui:injectUiSettings()
    end)
end
