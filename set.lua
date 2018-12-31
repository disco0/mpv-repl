-- set.lua -- Because I can't fucking forward define this due to both lua
--            and I being retarded
-- 
-- Creates structure that should already fuckign exist so searching a table of
-- single values (instead of keypairs) takes less than 4 lines of code

function Set (t)
    local set = {}
    for _, l in pairs(t) do set[l] = true end
    return set
end

return { Set = Set }