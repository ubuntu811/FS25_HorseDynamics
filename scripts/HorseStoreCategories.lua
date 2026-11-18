-- Two shop categories of our own. The game reads <storeCategories> of a modDesc for DLCs only (the log said: Invalid category 'horses'), so they are added here, right after the game has loaded its own (the pattern of the addStoreCategories reference mod).
HorseStoreCategories = {}
local modDir = g_currentModDirectory
local modName = g_currentModName

function HorseStoreCategories.loadMapData(self, superFunc, ...)
    superFunc(self, ...)
    local function add(name, l10n, image, type)
        if self:getCategoryByName(name) == nil then
            self:addCategory(name, g_i18n:convertText(l10n, modName), image, type, modDir)
        end
    end
    add("horses", "$l10n_category_horses", "vehicles/horseSulky/store_horseSulky.dds", "ANIMALS")   -- vehicles: the sulky
    add("animalGear", "$l10n_category_animalGear", "store/ball_v2.dds", "OBJECTS")                     -- objects: ball, jumps, harness
end

StoreManager.loadMapData = Utils.overwrittenFunction(StoreManager.loadMapData, HorseStoreCategories.loadMapData)
