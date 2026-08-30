--!nonstrict
local lib = require("./lib.luau")

local function update(active_name)
    if active_name and active_name ~= "" then
        shortcut.setLabel(active_name)
    else
        shortcut.setLabel("Profiles")
    end
end

update(lib.getActiveProfile())
noctalia.state.watch("active_profile", function(val)
    update(val)
end)

function onClick()
    noctalia.togglePanel("ezequielgk/profiles:manager")
end
