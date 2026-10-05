local viewMode = "folders"
local selectedFolderIndex = 1
local displayedFolderIndex = 1
local allFolders = {}
local activeFolder = nil

local selectedIndex = 1
local displayedIndex = 1
local allWallpapers = {}
local currentWallpaper = ""

local favorites = {}
local isScanning = false
local isOpen = false

-- Add collection state
local addFolderPath = ""
local addPaletteType = "builtin"
local addPaletteName = ""
local addPaletteSearch = ""
local addErrorMessage = ""

math.randomseed(math.floor((os.clock() * 1000000) % 2147483647) + os.time())

local function tr(key, args)
  return noctalia.tr(key, args)
end

local function shellQuote(s)
  return "'" .. s:gsub("'", "'\''") .. "'"
end

local function makeSortKey(s)
  return s:lower()
end

local function normalizeName(s)
  return s:lower():gsub("[%s_%-]", "")
end

local function getCornerRadius(base)
  local scale = noctalia.getSetting("shell.corner_radius_scale")
  if scale == nil then scale = 1.0 end
  return math.floor(base * scale)
end

local home = noctalia.getenv("HOME") or "~"
local xdgCache = noctalia.getenv("XDG_CACHE_HOME")
local cacheDir = (xdgCache and xdgCache ~= "" and xdgCache or (home .. "/.cache")) .. "/noctalia/wallpaper-widget/thumbnails"
local xdgConfig = noctalia.getenv("XDG_CONFIG_HOME")
local configBaseDir = (xdgConfig and xdgConfig ~= "" and xdgConfig or (home .. "/.config")) .. "/noctalia"
local xdgState = noctalia.getenv("XDG_STATE_HOME")
local stateBaseDir = (xdgState and xdgState ~= "" and xdgState or (home .. "/.local/state")) .. "/noctalia"

local favoritesPath = configBaseDir .. "/wallpaper-widget-favorites.json"
local collectionsPath = configBaseDir .. "/wallpaper-collections.json"
local statePath = stateBaseDir .. "/wallpaper-widget-state.json"
local indexPath = stateBaseDir .. "/wallpaper-widget-index.json"

if not noctalia.fileExists(cacheDir) then
  noctalia.runAsync("mkdir -p " .. shellQuote(cacheDir))
end

local BUILTIN_PALETTES = {
  "Nord", "Gruvbox", "Catppuccin", "Tokyo-Night", "Everforest",
  "Kanagawa", "Rosé Pine", "Dracula", "Eldritch", "Ayu"
}

local WALLPAPER_PALETTES = {
  "soft", "faithful", "vibrant", "muted", "m3-tonal-spot", "m3-fruit-salad", "m3-rainbow", "m3-monochrome", "content"
}

local widgetState = { last_folder_path = "" }
local indexCache = { version = 3, folders = {} }

local function pcallDecode(content)
  local ok, data = pcall(function() return noctalia.json.decode(content) end)
  if ok and type(data) == "table" then return data end
  return nil
end

local function loadStateAndIndex()
  if noctalia.fileExists(statePath) then
    local data = pcallDecode(noctalia.readFile(statePath))
    if data and data.last_folder_path then widgetState.last_folder_path = data.last_folder_path end
  end
  if noctalia.fileExists(indexPath) then
    local data = pcallDecode(noctalia.readFile(indexPath))
    if data and data.version == 3 and type(data.folders) == "table" then
      indexCache = data
    end
  end
end

local function saveState()
  local ok, enc = pcall(function() return noctalia.json.encode(widgetState) end)
  if ok then noctalia.writeFile(statePath, enc) end
end

local function saveIndex()
  local ok, enc = pcall(function() return noctalia.json.encode(indexCache) end)
  if ok then noctalia.writeFile(indexPath, enc) end
end

-- PALETTES
local memoizedCustom = nil
local memoizedCommunity = nil
local normalizedPalettes = nil

local function getCustomPalettes()
  if memoizedCustom then return memoizedCustom end
  local list = {}
  local pDir = configBaseDir .. "/palettes"
  local files = noctalia.listDir(pDir)
  if files then
    for _, f in ipairs(files) do
      if f:match("%.json$") and f ~= "registry.json" and f ~= "_live_preview.json" then
        local name = f:match("^(.-)%.json$")
        if name and name ~= "" then table.insert(list, name) end
      end
    end
  end
  table.sort(list)
  memoizedCustom = list
  return list
end

local function getCommunityPalettes()
  if memoizedCommunity then return memoizedCommunity end
  local list = {}
  local catalogPath = stateBaseDir .. "/community-palettes/.catalog/palettes.json"
  if noctalia.fileExists(catalogPath) then
    local content = noctalia.readFile(catalogPath)
    if content and content ~= "" then
      local data = pcallDecode(content)
      if data then
        for _, entry in ipairs(data) do
          if entry.name and type(entry.name) == "string" then
            table.insert(list, entry.name)
          end
        end
      end
    end
  end
  if #list == 0 then
    local commDir = stateBaseDir .. "/community-palettes"
    local files = noctalia.listDir(commDir)
    if files then
      for _, f in ipairs(files) do
        if f:match("%.json$") and f ~= "palettes.json" then
          local name = f:match("^(.-)%.json$")
          if name and name ~= "" then
            table.insert(list, name:gsub("%%20", " "))
          end
        end
      end
    end
  end
  table.sort(list)
  memoizedCommunity = list
  return list
end

local function getNormalizedPalettes()
  if normalizedPalettes then return normalizedPalettes end
  normalizedPalettes = { builtin = {}, custom = {}, community = {} }
  for _, p in ipairs(BUILTIN_PALETTES) do normalizedPalettes.builtin[normalizeName(p)] = p end
  for _, p in ipairs(getCustomPalettes()) do normalizedPalettes.custom[normalizeName(p)] = p end
  for _, p in ipairs(getCommunityPalettes()) do normalizedPalettes.community[normalizeName(p)] = p end
  return normalizedPalettes
end

local function getPalettesForType(pType)
  if pType == "builtin" then return BUILTIN_PALETTES
  elseif pType == "wallpaper" then return WALLPAPER_PALETTES
  elseif pType == "custom" then return getCustomPalettes()
  elseif pType == "community" then return getCommunityPalettes()
  elseif pType == "none" then return {}
  end
  return {}
end

local function resolveFolderPalette(folderName)
  local norm = normalizeName(folderName)
  local sets = getNormalizedPalettes()
  if sets.builtin[norm] then return { source = "builtin", name = sets.builtin[norm] } end
  if sets.custom[norm] then return { source = "custom", name = sets.custom[norm] } end
  if sets.community[norm] then return { source = "community", name = sets.community[norm] } end
  return { source = "wallpaper", name = "soft" }
end

local function loadFavorites()
  favorites = {}
  if noctalia.fileExists(favoritesPath) then
    local content = noctalia.readFile(favoritesPath)
    if content and content ~= "" then
      local data = pcallDecode(content)
      if data then favorites = data end
    end
  end
end

local function saveFavorites()
  local ok, encoded = pcall(function() return noctalia.json.encode(favorites) end)
  if ok and encoded then
    noctalia.writeFile(favoritesPath, encoded)
  end
end

local function isFavorite(path)
  return favorites[path] == true
end

local render

local function toggleFavorite(path)
  if not path or path == "" then return end
  if favorites[path] then
    favorites[path] = nil
    if noctalia.getConfig("notify_on_change") ~= false then noctalia.notify(tr("panel.title"), tr("notify.favorite_removed")) end
  else
    favorites[path] = true
    if noctalia.getConfig("notify_on_change") ~= false then noctalia.notify(tr("panel.title"), tr("notify.favorite_added")) end
  end
  saveFavorites()
  if render then render() end
end

local function loadCollectionsFile()
  if not noctalia.fileExists(collectionsPath) then return {} end
  local content = noctalia.readFile(collectionsPath)
  local data = pcallDecode(content)
  return data or {}
end

local function saveCollectionsFile(list)
  local ok, encoded = pcall(function() return noctalia.json.encode(list) end)
  if ok and encoded then noctalia.writeFile(collectionsPath, encoded) end
end

local function getThumbPath(wallpaperPath)
  local h = 2166136261
  for i = 1, #wallpaperPath do
    h = bit32.bxor(h, string.byte(wallpaperPath, i))
    local lo = bit32.band(h, 0xFFFF) * 16777619
    local hi = bit32.band(bit32.rshift(h, 16), 0xFFFF) * 16777619
    h = bit32.band(lo + bit32.lshift(hi, 16), 0xFFFFFFFF)
  end
  local base = wallpaperPath:match("([^/]+)%.[^.]+$") or "wp"
  local safeBase = base:gsub("[^%w_%-]", "_"):sub(1, 24)
  return cacheDir .. "/" .. safeBase .. "_" .. string.format("%08x", h) .. ".jpg"
end

local thumbReady = {}

local function triggerBatchThumbnails(items)
  if #items == 0 then return end
  local needed = {}
  for _, item in ipairs(items) do
    local path = item.path or item.coverPath
    if path and path ~= "" and not path:match("^favorites://") then
      local thumb = getThumbPath(path)
      if noctalia.fileExists(thumb) then
        thumbReady[path] = thumb
      else
        table.insert(needed, { original = path, thumb = thumb })
      end
    end
  end

  if #needed == 0 then
    if isOpen and render then render() end
    return
  end

  local tmpFile = cacheDir .. "/batch_" .. tostring(os.time()) .. ".txt"
  local lines = {}
  for _, job in ipairs(needed) do
    table.insert(lines, shellQuote(job.original) .. " " .. shellQuote(job.thumb))
  end
  noctalia.writeFile(tmpFile, table.concat(lines, "\n"))
  
  local script = string.format([[
    #!/bin/bash
    TOOL=""
    if command -v vipsthumbnail >/dev/null; then TOOL="vips"
    elif command -v magick >/dev/null; then TOOL="magick"
    elif command -v convert >/dev/null; then TOOL="convert"
    elif command -v ffmpeg >/dev/null; then TOOL="ffmpeg"
    fi
    if [ -z "$TOOL" ]; then exit 1; fi
    generate_thumb() {
      case "$TOOL" in
        vips) nice -n 19 vipsthumbnail -s 460x259 -o "$2" "$1" >/dev/null 2>&1 ;;
        magick) nice -n 19 magick "$1" -thumbnail '460x259^' -gravity center -extent 460x259 -strip "$2" >/dev/null 2>&1 ;;
        convert) nice -n 19 convert "$1" -thumbnail '460x259^' -gravity center -extent 460x259 -strip "$2" >/dev/null 2>&1 ;;
        ffmpeg) nice -n 19 ffmpeg -y -i "$1" -vf 'scale=460:259:force_original_aspect_ratio=increase,crop=460:259' -vframes 1 "$2" >/dev/null 2>&1 ;;
      esac
    }
    export -f generate_thumb
    export TOOL
    cat %s | xargs -n 2 -P $(nproc) bash -c 'generate_thumb "$1" "$2"' _
    rm -f %s
  ]], shellQuote(tmpFile), shellQuote(tmpFile))
  
  local scriptFile = cacheDir .. "/run_batch.sh"
  noctalia.writeFile(scriptFile, script)
  noctalia.runAsync("bash " .. shellQuote(scriptFile), function()
    for _, job in ipairs(needed) do
      if noctalia.fileExists(job.thumb) then thumbReady[job.original] = job.thumb end
    end
    if isOpen and render then render() end
  end)
end

local function resolveDisplayPath(path)
  if not path or path == "" then return nil end
  if path:match("^favorites://") then return nil end
  if thumbReady[path] then return thumbReady[path] end
  local thumb = getThumbPath(path)
  if noctalia.fileExists(thumb) then
    thumbReady[path] = thumb
    return thumb
  end
  return nil
end

local function renderCardImage(key, path, width, height, radius, borderWidth, border)
  local displayPath = resolveDisplayPath(path)
  if displayPath then
    return ui.image({
      key = key,
      path = displayPath,
      width = width,
      height = height,
      fit = "cover",
      radius = radius,
      borderWidth = borderWidth,
      border = border,
    })
  else
    return ui.column({
      key = key .. "_placeholder",
      width = width,
      height = height,
      align = "center",
      justify = "center",
      radius = radius,
      fill = "surface_variant/0.3",
      borderWidth = borderWidth,
      border = border,
    }, {
      ui.glyph({ name = "photo", size = 24, color = "on_surface_variant/0.5" })
    })
  end
end

local function getCurrentWallpaper()
  if noctalia.wallpaperPath then
    local out = noctalia.focusedOutputName and noctalia.focusedOutputName()
    if out then
      local path = noctalia.wallpaperPath(out)
      if path and path ~= "" then return path end
    end
    if noctalia.outputs then
      for _, o in ipairs(noctalia.outputs()) do
        if o.name then
          local path = noctalia.wallpaperPath(o.name)
          if path and path ~= "" then return path end
        end
      end
    end
  end
  return nil
end

local function isPathInFolder(filepath, folderpath)
  if filepath == folderpath then return true end
  if filepath:sub(1, #folderpath + 1) == folderpath .. "/" then return true end
  return false
end

local function getActiveBaseDirs()
  local targets = {}
  local isCollection = {}
  local palettes = {}
  
  local customCollections = loadCollectionsFile()
  for _, entry in ipairs(customCollections) do
    if entry.path and entry.path ~= "" then
      local exp = noctalia.expandPath(entry.path)
      table.insert(targets, exp)
      isCollection[exp] = entry.name or exp:match("([^/]+)$") or "Collection"
      palettes[exp] = { source = entry.palette_type or "builtin", name = entry.palette or "Nord" }
    end
  end
  
  local baseDir = noctalia.getConfig("wallpaper_dir")
  if type(baseDir) == "string" and baseDir ~= "" then baseDir = noctalia.expandPath(baseDir)
  elseif noctalia.wallpaperDirectory then
    local ok, d = pcall(function() return noctalia.wallpaperDirectory() end)
    if ok and type(d) == "string" and d ~= "" then baseDir = d end
  end
  if not baseDir or baseDir == "" or not noctalia.fileExists(baseDir) then
    local candidates = {home.."/Imágenes/Wallpapers", home.."/Pictures/wallpapers", home.."/Imágenes", home.."/Pictures"}
    for _, c in ipairs(candidates) do
      if noctalia.fileExists(c) then baseDir = c; break end
    end
  end

  return targets, baseDir, isCollection, palettes
end

local function buildFolderEntry(dirPath, wps, customName, customPalette)
  if not wps or #wps == 0 then return nil end
  local name = customName or dirPath:match("([^/]+)$") or "Wallpapers"
  
  local pal = customPalette
  if not pal then pal = resolveFolderPalette(name) end

  return {
    path = dirPath,
    name = name,
    wallpapers = wps,
    count = #wps,
    coverPath = wps[1].path,
    palette = pal,
    sortKey = makeSortKey(name)
  }
end

local currentGenToken = 0

local function rebuildFoldersFromCache(targets, baseDir, isCollection, palettes)
  local folderList = {}
  
  local favList = {}
  for favPath, _ in pairs(favorites) do
    if noctalia.fileExists(favPath) then
      local fname = favPath:match("([^/]+)$") or favPath
      local cname = fname:gsub("%.%w+$", "")
      table.insert(favList, { path = favPath, name = cname, filename = fname, sortKey = makeSortKey(cname) })
    end
  end
  if #favList > 0 then
    table.sort(favList, function(a, b) return a.sortKey < b.sortKey end)
    local favEntry = buildFolderEntry("favorites://", favList, "★ " .. tr("panel.favorites"), { source = "wallpaper", name = "soft" })
    if favEntry then
      favEntry.sortKey = " 00000_favorites"
      favEntry.isFavoritesFolder = true
      table.insert(folderList, favEntry)
    end
  end

  local addedDirs = {}
  for _, exp in ipairs(targets) do
    if indexCache.folders[exp] then
      local entry = buildFolderEntry(exp, indexCache.folders[exp], isCollection[exp], palettes[exp])
      if entry then
        table.insert(folderList, entry)
        addedDirs[exp] = true
      end
    end
    -- Also include direct subfolders of the collection if they have wallpapers
    for dir, wps in pairs(indexCache.folders) do
      if not addedDirs[dir] and dir:find(exp .. "/", 1, true) == 1 then
        local subName = dir:match("([^/]+)$") or dir
        local parentColName = isCollection[exp] or exp:match("([^/]+)$") or "Collection"
        local entry = buildFolderEntry(dir, wps, parentColName .. " / " .. subName, palettes[exp])
        if entry then
          table.insert(folderList, entry)
          addedDirs[dir] = true
        end
      end
    end
  end

  if baseDir then
    if indexCache.folders[baseDir] then
      local rootName = baseDir:match("([^/]+)$") or "Wallpapers"
      local entry = buildFolderEntry(baseDir, indexCache.folders[baseDir], rootName, { source = "wallpaper", name = "soft" })
      if entry then table.insert(folderList, entry) end
    end
    for dir, wps in pairs(indexCache.folders) do
      local parentDir = dir:match("^(.*)/[^/]+$")
      if parentDir == baseDir and not isCollection[dir] then
        local entry = buildFolderEntry(dir, wps, nil, nil)
        if entry then table.insert(folderList, entry) end
      end
    end
  end

  table.sort(folderList, function(a, b) return a.sortKey < b.sortKey end)
  allFolders = folderList

  local found = false
  if currentWallpaper ~= "" and #allFolders > 0 then
    for i, f in ipairs(allFolders) do
      if isPathInFolder(currentWallpaper, f.path) then
        selectedFolderIndex = i
        displayedFolderIndex = i
        found = true
        break
      end
    end
  end
  
  if not found and widgetState.last_folder_path then
    for i, f in ipairs(allFolders) do
      if f.path == widgetState.last_folder_path then
        selectedFolderIndex = i
        displayedFolderIndex = i
        found = true
        break
      end
    end
  end
  
  if not found then
    selectedFolderIndex = 1
    displayedFolderIndex = 1
  end

  if allFolders[selectedFolderIndex] then
    activeFolder = allFolders[selectedFolderIndex]
    allWallpapers = activeFolder.wallpapers
    selectedIndex = 1
    displayedIndex = 1
    if currentWallpaper ~= "" then
      for i, wp in ipairs(allWallpapers) do
        if wp.path == currentWallpaper then
          selectedIndex = i
          displayedIndex = i
          break
        end
      end
    end
  else
    activeFolder = nil
    allWallpapers = {}
  end

  local covers = {}
  for _, f in ipairs(allFolders) do table.insert(covers, { coverPath = f.coverPath }) end
  triggerBatchThumbnails(covers)
end

local function refreshIndex()
  currentGenToken = currentGenToken + 1
  local token = currentGenToken
  isScanning = true

  local targets, baseDir, isCollection, palettes = getActiveBaseDirs()
  
  local active = getCurrentWallpaper()
  if active and active ~= "" then currentWallpaper = active end

  rebuildFoldersFromCache(targets, baseDir, isCollection, palettes)
  isScanning = false
  if render and isOpen then render() end

  local dirsToScan = {}
  for _, t in ipairs(targets) do table.insert(dirsToScan, t) end
  if baseDir then table.insert(dirsToScan, baseDir) end
  
  if #dirsToScan > 0 then
    local dirsStr = ""
    for _, d in ipairs(dirsToScan) do dirsStr = dirsStr .. shellQuote(d) .. " " end
    local findCmd = string.format("find %s -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) ! -path '*/.*' 2>/dev/null", dirsStr)
    local cmd = "bash -c " .. shellQuote(findCmd)
    
    noctalia.runAsync(cmd, function(res)
      if token ~= currentGenToken then return end
      if res and res.exitCode == 0 and res.stdout then
        local newFolders = {}
        for path in res.stdout:gmatch("[^\r\n]+") do
          local dir, file = path:match("^(.*)/([^/]+)$")
          if dir and file then
             if not newFolders[dir] then newFolders[dir] = {} end
             local clean = file:gsub("%.%w+$", "")
             table.insert(newFolders[dir], {
               path = path,
               filename = file,
               name = clean,
               sortKey = makeSortKey(clean)
             })
          end
        end
        
        local changed = false
        for dir, wps in pairs(newFolders) do
           if not indexCache.folders[dir] or #indexCache.folders[dir] ~= #wps then
             table.sort(wps, function(a, b) return a.sortKey < b.sortKey end)
             indexCache.folders[dir] = wps
             changed = true
           end
        end
        
        if changed then
          saveIndex()
          rebuildFoldersFromCache(targets, baseDir, isCollection, palettes)
          if render and isOpen then render() end
        end
      end
    end)
  end
end

local function getDisplayedFolderAt(offset)
  local total = #allFolders
  if total == 0 then return nil, 1 end
  local idx = ((displayedFolderIndex - 1 + offset) % total) + 1
  return allFolders[idx], idx
end

local function getDisplayedWallpaperAt(offset)
  local total = #allWallpapers
  if total == 0 then return nil, 1 end
  local idx = ((displayedIndex - 1 + offset) % total) + 1
  return allWallpapers[idx], idx
end

local function stepFolderSelection(delta)
  local total = #allFolders
  if total == 0 then return end
  selectedFolderIndex = ((selectedFolderIndex - 1 + delta) % total) + 1
  displayedFolderIndex = selectedFolderIndex
  
  local f = allFolders[selectedFolderIndex]
  if f then
    widgetState.last_folder_path = f.path
    saveState()
  end
  
  if render and isOpen then render() end
end

local function stepWallpaperSelection(delta)
  local total = #allWallpapers
  if total == 0 then return end
  selectedIndex = ((selectedIndex - 1 + delta) % total) + 1
  displayedIndex = selectedIndex
  if render and isOpen then render() end
end

local function openFolder(folderIdx)
  if #allFolders == 0 then return end
  local f = allFolders[folderIdx]
  if not f or not f.wallpapers or #f.wallpapers == 0 then return end

  activeFolder = f
  allWallpapers = f.wallpapers
  viewMode = "wallpapers"

  selectedIndex = 1
  displayedIndex = 1
  for i, wp in ipairs(allWallpapers) do
    if wp.path == currentWallpaper then
      selectedIndex = i
      displayedIndex = i
      break
    end
  end

  triggerBatchThumbnails(allWallpapers)
  if render and isOpen then render() end
end

local function backToFolders()
  viewMode = "folders"
  if render and isOpen then render() end
end

local function openAddCollection()
  viewMode = "add_collection"
  addFolderPath = ""
  addPaletteType = "builtin"
  addPaletteName = ""
  addPaletteSearch = ""
  addErrorMessage = ""
    if render and isOpen then render() end
end

local function submitAddCollection()
  if addPaletteType ~= "none" and (not addPaletteName or addPaletteName == "") then
    addErrorMessage = tr("panel.select_palette_error") or "Elige una paleta"
    if render and isOpen then render() end
    return
  end
  local trimmedPath = (addFolderPath or ""):match("^%s*(.-)%s*$") or ""
  if trimmedPath == "" then
    addErrorMessage = tr("panel.invalid_folder")
    if render and isOpen then render() end
    return
  end

  local expPath = noctalia.expandPath(trimmedPath):gsub("/+$", "")
  local info = noctalia.fileInfo(expPath)
  if (not info or not info.isDir) and not expPath:match("^/") then
    local altPath = (home .. "/" .. trimmedPath):gsub("/+$", "")
    local altInfo = noctalia.fileInfo(altPath)
    if altInfo and altInfo.isDir then
      expPath = altPath
      info = altInfo
    end
  end

  if not info or not info.isDir then
    addErrorMessage = tr("panel.invalid_folder")
    if render and isOpen then render() end
    return
  end

  local folderBaseName = expPath:match("([^/]+)$") or "Collection"
  local finalPaletteName = addPaletteName
  if addPaletteType == "none" then
    finalPaletteName = "none"
  elseif not finalPaletteName or finalPaletteName == "" then
    finalPaletteName = (addPaletteType == "wallpaper") and "soft" or folderBaseName
  end

  local list = loadCollectionsFile()
  local exists = false
  for _, item in ipairs(list) do
    if item.path == expPath then
      item.name = folderBaseName
      item.palette_type = addPaletteType
      item.palette = finalPaletteName
      exists = true
      break
    end
  end

  if not exists then
    table.insert(list, {
      name = folderBaseName,
      path = expPath,
      palette_type = addPaletteType,
      palette = finalPaletteName,
    })
  end

  saveCollectionsFile(list)

  -- Immediately scan the newly added directory so it's populated without any delay
  local findNew = string.format("find %s -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) ! -path '*/.*' 2>/dev/null", shellQuote(expPath))
  local scanScript = cacheDir .. "/scan_new.sh"
  noctalia.writeFile(scanScript, findNew)
  noctalia.runAsync("bash " .. shellQuote(scanScript), function(res)
    if res and res.exitCode == 0 and res.stdout then
      local changed = false
      for path in res.stdout:gmatch("[^\r\n]+") do
        local dir, file = path:match("^(.*)/([^/]+)$")
        if dir and file then
          if not indexCache.folders[dir] then indexCache.folders[dir] = {} end
          local clean = file:gsub("%.%w+$", "")
          table.insert(indexCache.folders[dir], {
            path = path,
            filename = file,
            name = clean,
            sortKey = makeSortKey(clean)
          })
          changed = true
        end
      end
      if changed then
        for _, wps in pairs(indexCache.folders) do
          table.sort(wps, function(a, b) return a.sortKey < b.sortKey end)
        end
        saveIndex()
        local t, b, ic, p = getActiveBaseDirs()
        rebuildFoldersFromCache(t, b, ic, p)
        -- Select the newly added folder
        for i, f in ipairs(allFolders) do
          if f.path == expPath then
            selectedFolderIndex = i
            displayedFolderIndex = i
            widgetState.last_folder_path = expPath
            saveState()
            break
          end
        end
        if render and isOpen then render() end
      end
    end
  end)

  if noctalia.getConfig("notify_on_change") ~= false then
    noctalia.notify(tr("panel.title"), tr("notify.collection_added") .. ": " .. folderBaseName)
  end

  viewMode = "folders"
  refreshIndex()
end

local function applyFolderPalette(palette)
  if noctalia.getConfig("apply_palette") == false then return end
  if not palette or not palette.source or palette.source == "none" then return end
  local cmd = string.format("noctalia msg color-scheme-set %s %s", shellQuote(palette.source), shellQuote(palette.name or "soft"))
  noctalia.runAsync(cmd)
end

local function applyWallpaper(path)
  currentWallpaper = path
  if render and isOpen then render() end

  if noctalia.setWallpaper then noctalia.setWallpaper(path)
  else noctalia.runAsync("noctalia msg wallpaper-set " .. shellQuote(path))
  end

  if activeFolder and activeFolder.palette and not activeFolder.isFavoritesFolder then
    applyFolderPalette(activeFolder.palette)
  end

  if noctalia.getConfig("notify_on_change") ~= false then
    local fname = path:match("([^/]+)$") or path
    if activeFolder and activeFolder.palette and activeFolder.palette.name ~= "" and not activeFolder.isFavoritesFolder then
      noctalia.notify(tr("panel.title"), string.format("%s: %s\n%s: %s", tr("notify.switched"), fname, tr("panel.palette"), activeFolder.palette.name))
    else
      noctalia.notify(tr("panel.title"), tr("notify.switched") .. ": " .. fname)
    end
  end

  if noctalia.getConfig("close_on_apply") == true then
    panel.close()
  end
end

local function applyRandomWallpaper()
  if #allWallpapers == 0 then return end
  if #allWallpapers == 1 then
    selectedIndex = 1
    displayedIndex = 1
    applyWallpaper(allWallpapers[1].path)
    return
  end
  local curIdx = selectedIndex
  if currentWallpaper ~= "" then
    for i, wp in ipairs(allWallpapers) do
      if wp.path == currentWallpaper then
        curIdx = i
        break
      end
    end
  end
  local offset = math.random(1, #allWallpapers - 1)
  local randIdx = ((curIdx - 1 + offset) % #allWallpapers) + 1
  selectedIndex = randIdx
  displayedIndex = randIdx
  applyWallpaper(allWallpapers[randIdx].path)
end

render = function()
  local ok, err = pcall(function()
    local rCenter = getCornerRadius(16)
    local rSide = getCornerRadius(12)
    local rBadge = getCornerRadius(8)

    if isScanning then
      panel.render(ui.column({
        width = 1160,
        height = 430,
        align = "center",
        justify = "center",
        gap = 12,
        padding = 40,
      }, {
        ui.glyph({ name = "loader-2", size = 36, color = "primary" }),
        ui.label({ text = tr("panel.loading"), fontSize = 14, color = "on_surface_variant" }),
      }))
      return
    end

    if viewMode == "add_collection" then
      local availablePalettes = getPalettesForType(addPaletteType)
      local displayOptions = {}
      local realPalettes = {}
      local seenDisplay = {}
      
      for _, pName in ipairs(availablePalettes) do
        local disp = pName
        if #disp > 38 then
          disp = disp:sub(1, 37) .. "…"
        end
        if seenDisplay[disp] then
          local suffix = 2
          while seenDisplay[disp .. " (" .. suffix .. ")"] do suffix = suffix + 1 end
          disp = disp .. " (" .. suffix .. ")"
        end
        seenDisplay[disp] = true
        table.insert(displayOptions, disp)
        table.insert(realPalettes, pName)
      end

      local selIndex = nil
      if addPaletteName and addPaletteName ~= "" then
        for i, pName in ipairs(realPalettes) do
          if pName == addPaletteName then
            selIndex = i - 1 -- host uses 0-based indices
            break
          end
        end
      end

      local paletteSelectorControl
      if addPaletteType == "none" then
        paletteSelectorControl = ui.row({
          width = 536,
          height = 36,
          paddingH = 12,
          align = "center",
          radius = getCornerRadius and getCornerRadius(8) or 8,
          fill = "surface_variant/0.2",
          borderWidth = 1,
          border = "outline",
        }, {
          ui.glyph({ name = "palette-off", size = 16, color = "on_surface_variant" }),
          ui.label({
            text = " " .. (tr("panel.palette_source_none") or "Ninguna") .. " (conserva tu tema actual)",
            fontSize = 12,
            color = "on_surface_variant",
          }),
        })
      else
        local selectProps = {
          key = "palette_selector_" .. addPaletteType,
          options = displayOptions,
          placeholder = tr("panel.select_placeholder") or "Selecciona una paleta...",
          width = 536,
          onChange = function(idx)
            local n = tonumber(idx)
            if n ~= nil then
              local chosen = realPalettes[math.floor(n) + 1]
              if type(chosen) == "string" and chosen ~= "" then
                addPaletteName = chosen
                addErrorMessage = ""
                if render and isOpen then render() end
              end
            end
          end
        }
        if selIndex ~= nil then
          selectProps.selectedIndex = selIndex
        end
        paletteSelectorControl = ui.select(selectProps)
      end

      local cardItems = {
        ui.row({
          align = "center",
          justify = "space_between",
          width = 536,
        }, {
          ui.row({
            align = "center",
            gap = 8,
            paddingH = 12,
            paddingV = 4,
            radius = getCornerRadius and getCornerRadius(16) or 16,
            fill = "primary/0.2",
          }, {
            ui.glyph({ name = "folder-plus", size = 16, color = "primary" }),
            ui.label({ text = tr("panel.add_collection_title"), fontSize = 13, fontWeight = "bold", color = "primary" }),
          }),
          ui.button({
            glyph = "x",
            variant = "ghost",
            controlSize = "sm",
            onClick = function()
              viewMode = "folders"
              if render and isOpen then render() end
            end,
          }),
        }),

        ui.column({ gap = 5 }, {
          ui.label({ text = tr("panel.folder_path"), fontSize = 12, fontWeight = "bold", color = "on_surface" }),
          ui.input({
            key = "add_folder_input",
            placeholder = tr("panel.folder_path_placeholder"),
            value = addFolderPath,
            width = 536,
            onChange = function(val)
              addFolderPath = val or ""
              addErrorMessage = ""
            end,
            onSubmit = function()
              submitAddCollection()
            end,
          }),
        }),

        ui.column({ gap = 6 }, {
          ui.label({ text = tr("panel.palette_type"), fontSize = 12, fontWeight = "bold", color = "on_surface" }),
          ui.row({ gap = 6, align = "center" }, {
            ui.button({
              text = tr("panel.palette_source_builtin"),
              variant = (addPaletteType == "builtin") and "primary" or "ghost",
              controlSize = "sm",
              onClick = function()
                addPaletteType = "builtin"
                addPaletteName = ""
                if render and isOpen then render() end
              end,
            }),
            ui.button({
              text = tr("panel.palette_source_wallpaper"),
              variant = (addPaletteType == "wallpaper") and "primary" or "ghost",
              controlSize = "sm",
              onClick = function()
                addPaletteType = "wallpaper"
                addPaletteName = ""
                if render and isOpen then render() end
              end,
            }),
            ui.button({
              text = tr("panel.palette_source_custom"),
              variant = (addPaletteType == "custom") and "primary" or "ghost",
              controlSize = "sm",
              onClick = function()
                addPaletteType = "custom"
                addPaletteName = ""
                if render and isOpen then render() end
              end,
            }),
            ui.button({
              text = tr("panel.palette_source_community"),
              variant = (addPaletteType == "community") and "primary" or "ghost",
              controlSize = "sm",
              onClick = function()
                addPaletteType = "community"
                addPaletteName = ""
                if render and isOpen then render() end
              end,
            }),
            ui.button({
              glyph = "x",
              variant = (addPaletteType == "none") and "destructive" or "ghost",
              controlSize = "sm",
              onClick = function()
                addPaletteType = "none"
                addPaletteName = ""
                addErrorMessage = ""
                if render and isOpen then render() end
              end,
            }),
          }),
        }),

        ui.column({ gap = 6 }, {
          ui.label({ text = tr("panel.palette_name"), fontSize = 12, fontWeight = "bold", color = "on_surface" }),
          paletteSelectorControl,
        }),
      }

      if addErrorMessage ~= "" then
        table.insert(cardItems, ui.label({
          text = addErrorMessage,
          fontSize = 12,
          color = "error",
          fontWeight = "bold",
        }))
      end

      table.insert(cardItems, ui.row({
        align = "center",
        justify = "center",
        gap = 10,
        paddingV = 4,
      }, {
        ui.button({
          text = tr("panel.cancel"),
          variant = "ghost",
          controlSize = "md",
          onClick = function()
            viewMode = "folders"
            if render and isOpen then render() end
          end,
        }),
        ui.button({
          text = tr("panel.add_collection"),
          glyph = "check",
          variant = "primary",
          controlSize = "md",
          onClick = function()
            submitAddCollection()
          end,
        }),
      }))

      panel.render(ui.column({
        key = "view_add_collection_root",
        width = 1160,
        height = 430,
        align = "center",
        justify = "center",
      }, {
        ui.column({
          key = "add_collection_card",
          width = 580,
          gap = 16,
          padding = 22,
          radius = getCornerRadius and getCornerRadius(16) or 16,
          fill = "surface_variant/0.3",
          borderWidth = 1,
          border = "outline",
        }, cardItems),
      }))
      return
    end

    if viewMode == "folders" then
      if #allFolders == 0 then
        panel.render(ui.column({
          width = 1160,
          height = 430,
          align = "center",
          justify = "center",
          gap = 12,
          padding = 40,
        }, {
          ui.glyph({ name = "photo-off", size = 48, color = "on_surface_variant" }),
          ui.label({ text = tr("panel.empty_folders"), fontSize = 15, fontWeight = "bold", color = "on_surface" }),
          ui.label({ text = tr("panel.empty_folders_hint"), fontSize = 13, color = "on_surface_variant" }),
        }))
        return
      end

      local fLeft, idxLeft = getDisplayedFolderAt(-1)
      local fCenter = getDisplayedFolderAt(0)
      local fRight, idxRight = getDisplayedFolderAt(1)
      local palDisplayName = fCenter.palette and fCenter.palette.name or fCenter.name

      local carouselRow = ui.row({
        align = "center",
        justify = "center",
        gap = 20,
        flexGrow = 1,
      }, {
        ui.column({
          key = "folder-card-left",
          align = "center",
          width = 280,
          opacity = 0.55,
          onClick = function()
            selectedFolderIndex = idxLeft
            displayedFolderIndex = idxLeft
            if render and isOpen then render() end
          end,
        }, {
          renderCardImage("folder-img-left", fLeft.coverPath, 280, 158, rSide, 0, nil)
        }),

        ui.column({
          key = "folder-card-center",
          align = "center",
          width = 460,
          onClick = function()
            openFolder(selectedFolderIndex)
          end,
        }, {
          renderCardImage("folder-img-center", fCenter.coverPath, 460, 259, rCenter, 3, "primary")
        }),

        ui.column({
          key = "folder-card-right",
          align = "center",
          width = 280,
          opacity = 0.55,
          onClick = function()
            selectedFolderIndex = idxRight
            displayedFolderIndex = idxRight
            if render and isOpen then render() end
          end,
        }, {
          renderCardImage("folder-img-right", fRight.coverPath, 280, 158, rSide, 0, nil)
        }),
      })

      local infoSection = ui.column({
        key = "folders_info_section",
        align = "center",
        gap = 4,
      }, {
        ui.row({
          align = "center",
          justify = "center",
          height = 24,
        }, {
          ui.row({
            align = "center",
            gap = 6,
            paddingH = 10,
            paddingV = 3,
            radius = rBadge,
            fill = "primary/0.2",
          }, {
            ui.glyph({ name = fCenter.isFavoritesFolder and "star" or "palette", size = 13, color = "primary" }),
            ui.label({ text = palDisplayName, fontSize = 11, fontWeight = "bold", color = "primary" }),
          }),
        }),
        ui.label({
          text = tostring(selectedFolderIndex) .. " / " .. tostring(#allFolders),
          fontSize = 12,
          color = "on_surface_variant",
        }),
        ui.label({
          text = tr("panel.folder_hint"),
          fontSize = 11,
          color = "on_surface_variant",
        }),
      })

      panel.render(ui.column({
        key = "view_folders_root",
        width = 1160,
        height = 430,
        padding = 24,
        gap = 14,
        align = "center",
        justify = "center",
      }, {
        carouselRow,
        infoSection,
      }))
      return
    end

    if viewMode == "wallpapers" then
      if #allWallpapers == 0 then
        panel.render(ui.column({
          width = 1160,
          height = 430,
          align = "center",
          justify = "center",
          gap = 12,
          padding = 40,
        }, {
          ui.glyph({ name = "photo-off", size = 48, color = "on_surface_variant" }),
          ui.label({ text = tr("panel.empty"), fontSize = 15, fontWeight = "bold", color = "on_surface" }),
          ui.label({ text = tr("panel.empty_hint"), fontSize = 13, color = "on_surface_variant" }),
        }))
        return
      end

      local wpLeft, idxLeft = getDisplayedWallpaperAt(-1)
      local wpCenter = getDisplayedWallpaperAt(0)
      local wpRight, idxRight = getDisplayedWallpaperAt(1)

      local isSelectedActive = (allWallpapers[selectedIndex].path == currentWallpaper)
      local isCurrentFav = isFavorite(allWallpapers[selectedIndex].path)

      local carouselRow = ui.row({
        align = "center",
        justify = "center",
        gap = 20,
        flexGrow = 1,
      }, {
        ui.column({
          key = "card-left",
          align = "center",
          width = 280,
          opacity = 0.55,
          onClick = function()
            selectedIndex = idxLeft
            displayedIndex = idxLeft
            if render and isOpen then render() end
          end,
        }, {
          renderCardImage("img-left", wpLeft.path, 280, 158, rSide, (wpLeft.path == currentWallpaper) and 2 or 0, (wpLeft.path == currentWallpaper) and "primary" or nil)
        }),

        ui.column({
          key = "card-center",
          align = "center",
          width = 460,
          onClick = function()
            applyWallpaper(wpCenter.path)
          end,
        }, {
          renderCardImage("img-center", wpCenter.path, 460, 259, rCenter, (wpCenter.path == currentWallpaper) and 3 or 1, (wpCenter.path == currentWallpaper) and "primary" or "outline")
        }),

        ui.column({
          key = "card-right",
          align = "center",
          width = 280,
          opacity = 0.55,
          onClick = function()
            selectedIndex = idxRight
            displayedIndex = idxRight
            if render and isOpen then render() end
          end,
        }, {
          renderCardImage("img-right", wpRight.path, 280, 158, rSide, (wpRight.path == currentWallpaper) and 2 or 0, (wpRight.path == currentWallpaper) and "primary" or nil)
        }),
      })

      local badgesRow = ui.row({
        align = "center",
        justify = "center",
        gap = 8,
        height = 22,
      }, {
        isSelectedActive and ui.row({
          align = "center",
          gap = 4,
          paddingH = 8,
          paddingV = 2,
          radius = rBadge,
          fill = "primary/0.2",
        }, {
          ui.glyph({ name = "check", size = 13, color = "primary" }),
          ui.label({ text = tr("panel.active"), fontSize = 10, fontWeight = "bold", color = "primary" }),
        }) or nil,

        ui.row({
          align = "center",
          gap = 4,
          paddingH = 8,
          paddingV = 2,
          radius = rBadge,
          fill = "surface_variant/0.5",
        }, {
          ui.glyph({
            name = isCurrentFav and "star-filled" or "star",
            size = 13,
            color = isCurrentFav and "tertiary" or "on_surface_variant",
          }),
          ui.label({
            text = isCurrentFav and tr("panel.favorite") or tr("panel.palette_source_none"),
            fontSize = 10,
            fontWeight = "bold",
            color = isCurrentFav and "tertiary" or "on_surface_variant",
          }),
        }),
      })

      local infoSection = ui.column({
        align = "center",
        gap = 4,
      }, {
        badgesRow,
        ui.label({
          text = tostring(selectedIndex) .. " / " .. tostring(#allWallpapers),
          fontSize = 12,
          color = "on_surface_variant",
        }),
        ui.label({
          text = tr("panel.hint"),
          fontSize = 11,
          color = "on_surface_variant",
        }),
      })

      panel.render(ui.column({
        key = "view_wallpapers_root",
        width = 1160,
        height = 430,
        padding = 24,
        gap = 14,
        align = "center",
        justify = "center",
      }, {
        carouselRow,
        infoSection,
      }))
    end
  end)
  if not ok then
    if noctalia.log then noctalia.log("ERROR in render: " .. tostring(err)) end
    isScanning = false
  end
end

function onKey(chord, pressed)
  if not pressed then return end
  local c = chord:lower():gsub("shift%+", ""):gsub("ctrl%+", ""):gsub("alt%+", "")
  
  if isScanning then
    if c == "escape" then panel.close() end
    return
  end

  local ok, err = pcall(function()
    if viewMode == "add_collection" then
      if c == "escape" then
        viewMode = "folders"
        if render and isOpen then render() end
      elseif c == "return" or c == "enter" or c == "kp_enter" then
        submitAddCollection()
      end
      return
    end

    if viewMode == "folders" then
      if c == "a" then
        openAddCollection()
      elseif c == "left" or c == "up" then
        stepFolderSelection(-1)
      elseif c == "right" or c == "down" then
        stepFolderSelection(1)
      elseif c == "return" or c == "enter" or c == "kp_enter" then
        openFolder(selectedFolderIndex)
      elseif c == "escape" then
        panel.close()
      end
    elseif viewMode == "wallpapers" then
      if c == "left" or c == "up" then
        stepWallpaperSelection(-1)
      elseif c == "right" or c == "down" then
        stepWallpaperSelection(1)
      elseif c == "return" or c == "enter" or c == "kp_enter" then
        if allWallpapers[selectedIndex] then
          applyWallpaper(allWallpapers[selectedIndex].path)
        end
      elseif c == "f" then
        if allWallpapers[selectedIndex] then
          toggleFavorite(allWallpapers[selectedIndex].path)
        end
      elseif c == "backspace" or c == "delete" then
        backToFolders()
      elseif c == "space" then
        applyRandomWallpaper()
      elseif c == "escape" then
        panel.close()
      end
    end
  end)
  if not ok and noctalia.log then noctalia.log("ERROR in onKey: " .. tostring(err)) end
end

local lastScrollTime = 0
function onScroll(axis, steps, _startsGesture)
  if axis ~= "vertical" then return end
  local now = os.clock()
  if now - lastScrollTime < 0.12 then return end
  lastScrollTime = now

  local ok, err = pcall(function()
    local delta = (steps or 0) > 0 and 1 or -1
    if viewMode == "folders" then
      stepFolderSelection(delta)
    elseif viewMode == "wallpapers" then
      stepWallpaperSelection(delta)
    end
  end)
  if not ok and noctalia.log then noctalia.log("ERROR in onScroll: " .. tostring(err)) end
end

function onOpen(_context)
  isOpen = true
  viewMode = "folders"
  loadStateAndIndex()
  loadFavorites()
  refreshIndex()
end

function onClose()
  isOpen = false
end

-- Initialize state immediately so memory is ready
loadStateAndIndex()
loadFavorites()
refreshIndex()
