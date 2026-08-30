--!nonstrict
local lib = {}

function lib.getProfilesDir()
    local path = noctalia.expandPath("~/.local/state/noctalia/profiles")
    noctalia.mkdirAll(path)
    return path
end

function lib.getSettingsPath()
    return noctalia.expandPath("~/.local/state/noctalia/settings.toml")
end

function lib.getActiveProfilePath()
    return lib.getProfilesDir() .. "/active.json"
end

function lib.getBackupPath()
    return lib.getProfilesDir() .. "/_backup.toml"
end

function lib.getActiveProfile()
    local content, err = noctalia.readFile(lib.getActiveProfilePath())
    if not content then return nil end
    local parsed, e = noctalia.json.decode(content)
    if parsed and parsed.name and parsed.name ~= "" then
        return parsed.name
    end
    return nil
end

function lib.setActiveProfile(name)
    name = name or ""
    local encoded, err = noctalia.json.encode({ name = name })
    if encoded then
        noctalia.writeFile(lib.getActiveProfilePath(), encoded)
        noctalia.state.set("active_profile", name)
    end
end

function lib.listProfiles()
    local dir = lib.getProfilesDir()
    local files, err = noctalia.listDir(dir)
    if not files then return {} end
    
    local profiles = {}
    for _, file in ipairs(files) do
        if file:match("%.toml$") and not file:match("^_backup") then
            local name = file:gsub("%.toml$", "")
            local info = noctalia.fileInfo(dir .. "/" .. file)
            local mtime = info and info.mtime or 0
            table.insert(profiles, { name = name, mtime = mtime })
        end
    end
    table.sort(profiles, function(a, b) return a.name < b.name end)
    return profiles
end

function lib.saveProfile(name)
    local content, err = noctalia.readFile(lib.getSettingsPath())
    if not content then
        noctalia.notifyError("Save Profile Failed", "Could not read settings: " .. tostring(err))
        return false
    end
    
    local ok, werr = noctalia.writeFile(lib.getProfilesDir() .. "/" .. name .. ".toml", content)
    if not ok then
        noctalia.notifyError("Save Profile Failed", "Could not write profile: " .. tostring(werr))
        return false
    end
    
    lib.setActiveProfile(name)
    return true
end

function lib.loadProfile(name)
    local profilePath = lib.getProfilesDir() .. "/" .. name .. ".toml"
    local profileContent, err = noctalia.readFile(profilePath)
    if not profileContent then
        noctalia.notifyError("Load Profile Failed", "Could not read profile: " .. tostring(err))
        return false
    end
    
    local currentSettings, rerr = noctalia.readFile(lib.getSettingsPath())
    if currentSettings then
        noctalia.writeFile(lib.getBackupPath(), currentSettings)
    end
    
    local ok, werr = noctalia.writeFile(lib.getSettingsPath(), profileContent)
    if not ok then
        noctalia.notifyError("Load Profile Failed", "Could not write to settings: " .. tostring(werr))
        return false
    end
    
    noctalia.runAsync("noctalia msg config-reload")
    lib.setActiveProfile(name)
    return true
end

function lib.deleteProfile(name)
    local ok, err = noctalia.removeFile(lib.getProfilesDir() .. "/" .. name .. ".toml")
    if not ok then
        noctalia.notifyError("Delete Profile Failed", "Could not delete profile: " .. tostring(err))
        return false
    end
    if lib.getActiveProfile() == name then
        lib.setActiveProfile(nil)
    end
    return true
end

function lib.cycleProfile()
    local profiles = lib.listProfiles()
    if #profiles == 0 then return end
    
    local active = lib.getActiveProfile()
    local nextIndex = 1
    if active then
        for i, p in ipairs(profiles) do
            if p.name == active then
                nextIndex = i + 1
                if nextIndex > #profiles then nextIndex = 1 end
                break
            end
        end
    end
    lib.loadProfile(profiles[nextIndex].name)
end

return lib
