--[[
    HorsePreview.lua -- EXPERIMENT: the vehicle shop's 3D preview screen (ShopConfigScreen) showing a horse, in a horse hall instead of the machine workshop, with the horse wearing a random look.
    Three things nobody knew, each logged ("[HorsePreview] ..."):
      1. does the screen take a store item that is hidden from the shop (xml/horseAdult.xml has showInStore false)?
      2. does the horse's Rideable specialization load without an animal (cluster)?
      3. can the coat shader parameters be set when the preview vehicle appears?
    Console: hdPreview [seed | nohall]   opens the preview on a horse (a random look, or the one of the seed; nohall keeps the game's workshop); Esc / Back closes it.
    The hall (models/hall, tools/make_horse_hall.py): a box of wood panels, a straw floor, a spot light and four warm lights, put where the workshop is (self.workshopWorldPosition) while the horse is shown.
    Later (not built): a Preview button in the animal dealer.
]]
HorsePreview = {}
HorsePreview.active = false
HorsePreview.useHall = true
HorsePreview.dir = g_currentModDirectory

local function say(format, ...)
    print(string.format("[HorsePreview] " .. format, ...))
end

function HorsePreview.noop() end

function HorsePreview.console(_, arg)
    if g_shopConfigScreen == nil or g_storeManager == nil or g_gui == nil then
        return "no shop screen (start a game first)"
    end
    local item = g_storeManager:getItemByXMLFilename(HorsePreview.dir .. "xml/horseAdult.xml")
    if item == nil then
        say("1. NO: the horse is not a store item the shop knows (xml/horseAdult.xml)")
        return "the horse is not a store item"
    end
    HorsePreview.useHall = arg ~= "nohall"
    HorsePreview.seed = tonumber(arg) or math.random(1, HorseCoat.MAX_SEED)
    HorsePreview.active = true
    say("opening the preview screen for %s (seed %d, hall: %s)", tostring(item.xmlFilename), HorsePreview.seed, tostring(HorsePreview.useHall))
    g_gui:showGui("ShopConfigScreen")
    local ok, err = pcall(g_shopConfigScreen.setStoreItem, g_shopConfigScreen, item, nil, nil, nil, nil)
    if not ok then
        say("1. the screen did not take the store item: %s", tostring(err))
        HorsePreview.active = false
        return "failed, see the log"
    end
    g_shopConfigScreen:setCallbacks(HorsePreview.noop, HorsePreview)
    say("1. the screen took the store item (the vehicle loads next)")
    return string.format("preview opened (seed %d); Esc closes it", HorsePreview.seed)
end

-- the hall: loaded once, shown where the workshop is while the preview is ours
function HorsePreview.enter(screen)
    if not HorsePreview.useHall then
        return
    end
    if HorsePreview.hall == nil then
        local ok, root = pcall(function() return g_i3DManager:loadSharedI3DFile(HorsePreview.dir .. "models/hall/horseHall.i3d", false, false) end)
        if ok and root ~= nil and root ~= 0 then
            local hall = getChildAt(root, 0)
            link(getRootNode(), hall)
            delete(root)
            HorsePreview.hall = hall
            say("the hall is loaded")
        else
            say("the hall did not load: %s", tostring(root))
            return
        end
    end
    local p = screen.workshopWorldPosition or { 0, -100, 0 }
    setTranslation(HorsePreview.hall, p[1], p[2], p[3])
    setVisibility(HorsePreview.hall, true)
    if screen.workshopRootNode ~= nil then
        setVisibility(screen.workshopRootNode, false)
    end
end

function HorsePreview.leave(_)
    if HorsePreview.hall ~= nil then
        setVisibility(HorsePreview.hall, false)
    end
    HorsePreview.active = false
end

-- the preview vehicle has appeared
function HorsePreview.onVehiclesLoaded(screen)
    if not HorsePreview.active then
        return
    end
    for _, vehicle in ipairs(screen.previewVehicles or {}) do
        local spec = vehicle.spec_rideable
        local okCluster, cluster = pcall(function() return vehicle.getCluster ~= nil and vehicle:getCluster() or nil end)
        say("2. the preview vehicle loaded: %s; Rideable spec: %s; mesh node: %s; cluster: %s", tostring(vehicle.configFileName), spec ~= nil and "yes" or "NO", tostring(spec ~= nil and spec.meshNode or nil), okCluster and tostring(cluster) or "error")
        if spec ~= nil and spec.meshNode ~= nil then
            local c, text = HorseCoat.fromSeed(HorsePreview.seed)
            local ok, err = pcall(HorseFoal.applyCoat, spec.meshNode, c)
            say("3. the coat parameters %s: %s (seed %d)", ok and "were set" or "FAILED " .. tostring(err), text, HorsePreview.seed)
        end
    end
end

if ShopConfigScreen ~= nil and Utils ~= nil and not HorsePreview.hooked then
    HorsePreview.hooked = true
    ShopConfigScreen.onOpen = Utils.appendedFunction(ShopConfigScreen.onOpen, function(self) if HorsePreview.active then HorsePreview.enter(self) end end)
    ShopConfigScreen.onClose = Utils.appendedFunction(ShopConfigScreen.onClose, function(self) HorsePreview.leave(self) end)
    ShopConfigScreen.onVehiclesLoaded = Utils.appendedFunction(ShopConfigScreen.onVehiclesLoaded, function(self) HorsePreview.onVehiclesLoaded(self) end)
    ShopConfigScreen.onClickBack = Utils.overwrittenFunction(ShopConfigScreen.onClickBack, function(self, superFunc, ...)
        if HorsePreview.active then
            g_gui:showGui("")                      -- (no shop menu to go back to: back to the game)
            return false
        end
        return superFunc(self, ...)
    end)
end
-- Development: after a deploy, load what changed without a restart, with the game's own commands: drop the cached i3d files, reload the vehicles near you (a horse taken out of a pasture, a ball, the sulky are
-- vehicles; a horse standing in a pasture is not: lead it out first). hdReload [radius m, default 50] [store]. "store" adds gsStoreItemsReload (a changed price, name or picture): it re-reads the store items of EVERY
-- mod (slow, and it repeats their warnings), a changed model or xml does not need it. Not for the shop screens (the game refuses there).
function HorsePreview.reload(_, ...)
    local radius, withStore = 50, false
    for _, a in ipairs({ ... }) do
        if a == "store" then withStore = true elseif tonumber(a) ~= nil then radius = tonumber(a) end
    end
    local steps = { { "gsI3DCacheClean" } }
    if withStore then steps[#steps + 1] = { "gsStoreItemsReload" } end
    steps[#steps + 1] = { "gsVehicleReload", "0 " .. tostring(radius) }
    local out = {}
    for _, step in ipairs(steps) do
        local ok, result = pcall(executeConsoleCommand, step[1] .. (step[2] and (" " .. step[2]) or ""))
        out[#out + 1] = string.format("%s: %s", step[1], ok and tostring(result or "done") or ("not available: " .. tostring(result)))
        print("[HorsePreview] reload: " .. out[#out])
    end
    return table.concat(out, " | ")
end

if addConsoleCommand ~= nil then
    addConsoleCommand("hdReload", "HorseDynamics development: after a deploy load what changed without a restart (gsI3DCacheClean, gsVehicleReload 0 <radius>; with store also gsStoreItemsReload): hdReload [radius] [store]", "reload", HorsePreview)
    addConsoleCommand("hdPreview", "HorseDynamics experiment: the shop's 3D preview on a horse in a horse hall: hdPreview [seed | nohall]", "console", HorsePreview)
end
