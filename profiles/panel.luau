--!nonstrict
local lib = require("./lib.luau")

local inputName = ""

local function render()
    local profiles = lib.listProfiles()
    
    local profileRows = {}
    for _, p in ipairs(profiles) do
        table.insert(profileRows, ui.row({ align = "center", justify = "space_between", gap = 8 }, {
            ui.label({ text = p.name, flexGrow = 1 }),
            ui.button({ text = "Load", onClick = function() lib.loadProfile(p.name) end }),
            ui.button({
                text = "Delete",
                onClick = function()
                    lib.deleteProfile(p.name)
                    render()
                end
            })
        }))
    end

    local listFallback = {}
    if #profiles == 0 then
        table.insert(listFallback, ui.label({ text = "No profiles saved yet.", color = "on_surface_variant" }))
    end

    panel.render(ui.column({ flexGrow = 1, gap = 16 }, {
        ui.row({ align = "center", justify = "space_between", gap = 8 }, {
            ui.label({ text = "Profiles Manager", fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
            ui.button({ glyph = "close", onClick = function() panel.close() end })
        }),
        
        ui.row({ gap = 8, align = "center" }, {
            ui.input({
                key = "name_input",
                placeholder = "New profile name",
                flexGrow = 1,
                onChange = function(val) inputName = val end,
                onSubmit = function(val)
                    if val and val ~= "" then
                        lib.saveProfile(val)
                        inputName = ""
                        render()
                    end
                end
            }),
            ui.button({
                text = "Save",
                onClick = function()
                    if inputName and inputName ~= "" then
                        lib.saveProfile(inputName)
                        inputName = ""
                        render()
                    end
                end
            })
        }),
        
        ui.scroll({ flexGrow = 1, gap = 8 }, #profiles > 0 and profileRows or listFallback)
    }))
end

function onOpen(_context)
    inputName = ""
    render()
end
