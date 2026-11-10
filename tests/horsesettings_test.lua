-- plain Lua with a fake engine: the settings page (HorseSettings): defaults, load, save, the HorseHitch flags, the injection into the settings page
local passed, failed = 0, 0
local realPrint = print
print = function() end
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end

HorseHitch = { GALLOP_LIMIT = true, PLAYER_CAP = true, SPEED_LIMITS = false }
local files = {}                                           -- path -> { name -> value }
local created = {}
getUserProfileAppPath = function() return "profile/" end
createFolder = function(path) created[#created + 1] = path end
XMLValueType = { BOOL = "bool" }
XMLSchema = { new = function() return { register = function() end } end }
XMLFile = {
    loadIfExists = function(name, path) if files[path] == nil then return nil end; local d = files[path]; return { getValue = function(_, key, default) local v = d[key:match("#(.+)")]; if v == nil then return default end; return v end, delete = function() end } end,
    create = function(name, path) local d = {}; return { setValue = function(_, key, v) d[key:match("#(.+)")] = v end, save = function() files[path] = d end, delete = function() end } end,
}
Utils = { appendedFunction = function(old, new) return function(...) if old ~= nil then old(...) end; new(...) end end }
local opened = 0
InGameMenu = { onMenuOpened = function() opened = opened + 1 end }
local page = { gameSettingsLayout = { invalidateLayout = function() end } }
g_gui = { screenControllers = { [InGameMenu] = { pageSettings = page } } }
UIHelper = { calls = {} }
UIHelper.createControlsDynamically = function(settingsPage, title, owner, properties, prefix) UIHelper.calls[#UIHelper.calls + 1] = { settingsPage, title, owner, properties, prefix } end
UIHelper.setupAutoBindControls = function(owner, target, update) UIHelper.bound = { owner, target, update }; owner.populateAutoBindControls = function() UIHelper.populated = true end end

dofile("scripts/HorseSettings.lua")
local S = HorseSettings
check("defaults: no gallop and the load slows you down, the pull limit off (small ploughs are possible)", S.config.gallopLimit == true and S.config.playerCap == true and S.config.pullLimit == false)
check("... applied to the HorseHitch flags at load", HorseHitch.GALLOP_LIMIT == true and HorseHitch.PLAYER_CAP == true and HorseHitch.SPEED_LIMITS == false)
check("the settings folder is made under the profile's modSettings", created[#created] == "profile/modSettings/FS25_HorseDynamics/")

-- a change is applied and saved, and a restart reads it back
S.config.gallopLimit, S.config.pullLimit = false, true
S.ui.onSettingsChange()
check("a change is applied to the flags at once", HorseHitch.GALLOP_LIMIT == false and HorseHitch.SPEED_LIMITS == true and HorseHitch.PLAYER_CAP == true)
local path = "profile/modSettings/FS25_HorseDynamics/config.xml"
check("... and saved", files[path] ~= nil and files[path].gallopLimit == false and files[path].pullLimit == true and files[path].playerCap == true)
for name, value in pairs(S.DEFAULTS) do S.config[name] = value end
S.load()
S.apply()
check("a restart: the saved values come back and are applied", S.config.gallopLimit == false and S.config.pullLimit == true and HorseHitch.GALLOP_LIMIT == false and HorseHitch.SPEED_LIMITS == true)
files[path] = nil
for name, value in pairs(S.DEFAULTS) do S.config[name] = value end
S.load()
check("no file: the defaults stay", S.config.gallopLimit == true and S.config.pullLimit == false)

-- the page
InGameMenu.onMenuOpened()
check("opening the menu injects the section once: one switch per setting, bound by name, prefix hd_", #UIHelper.calls == 1 and UIHelper.calls[1][1] == page and UIHelper.calls[1][2] == "hd_setting_title" and UIHelper.calls[1][5] == "hd_" and #UIHelper.calls[1][4] == 5 and UIHelper.calls[1][4][1].name == "gallopLimit" and UIHelper.calls[1][4][1].autoBind == true and UIHelper.calls[1][4][1].min == nil and UIHelper.calls[1][4][1].values == nil)
check("... bound to the config, a change calls onSettingsChange, and the controls are filled", UIHelper.bound[2] == S.config and UIHelper.bound[3] == S.ui.onSettingsChange and UIHelper.populated == true)
InGameMenu.onMenuOpened()
check("opening it again does not inject a second time", #UIHelper.calls == 1 and opened == 2)

print = realPrint
print(string.format("horsesettings_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
