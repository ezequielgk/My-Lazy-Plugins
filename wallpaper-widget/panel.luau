local viewMode = "folders" -- "folders" | "wallpapers" | "add_collection"
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
local navToken = 0
local generatingPending = {}
local batchRunning = false
local isOpen = false

-- Add collection state
local addFolderPath = ""
local addPaletteType = "builtin" -- "builtin" | "wallpaper" | "custom" | "community"
local addPaletteName = "Nord"
local addPaletteSearch = ""
local addErrorMessage = ""

math.randomseed(math.floor((os.clock() * 1000000) % 2147483647) + os.time())

local function tr(key, args)
  return noctalia.tr(key, args)
end

local function shellQuote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function makeSortKey(s)
  local lower = s:lower()
  return lower:gsub("%d+", function(n)
    return string.format("%08d", tonumber(n) or 0)
  end)
end

local function normalizeName(s)
  return s:lower():gsub("[%s_%-]", "")
end

local function getCornerRadius(base)
  local scale = noctalia.getSetting("shell.corner_radius_scale")
  if scale == nil then
    scale = 1.0
  end
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

local BUILTIN_PALETTES = {
  "Nord", "Gruvbox", "Catppuccin", "Tokyo-Night", "Everforest",
  "Kanagawa", "Rosé Pine", "Dracula", "Eldritch", "Ayu"
}

local WALLPAPER_PALETTES = {
  "soft", "faithful", "vibrant", "muted", "m3-tonal-spot", "m3-fruit-salad", "m3-rainbow", "m3-monochrome", "content"
}

local function getCustomPalettes()
  local list = {}
  local pDir = configBaseDir .. "/palettes"
  local files = noctalia.listDir(pDir)
  if files then
    for _, f in ipairs(files) do
      if f:match("%.json$") and f ~= "registry.json" and f ~= "_live_preview.json" then
        local name = f:match("^(.-)%.json$")
        if name and name ~= "" then
          table.insert(list, name)
        end
      end
    end
  end
  table.sort(list)
  return list
end

local function getCommunityPalettes()
  local list = {}
  local catalogPath = stateBaseDir .. "/community-palettes/.catalog/palettes.json"
  if noctalia.fileExists(catalogPath) then
    local content = noctalia.readFile(catalogPath)
    if content and content ~= "" then
      local ok, data = pcall(function() return noctalia.json.decode(content) end)
      if ok and type(data) == "table" then
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
            name = name:gsub("%%20", " ")
            table.insert(list, name)
          end
        end
      end
    end
  end

  table.sort(list)
  return list
end

local function getPalettesForType(pType)
  if pType == "builtin" then
    return BUILTIN_PALETTES
  elseif pType == "wallpaper" then
    return WALLPAPER_PALETTES
  elseif pType == "custom" then
    return getCustomPalettes()
  elseif pType == "community" then
    return getCommunityPalettes()
  end
  return {}
end

local cacheDirPrepared = false
local function ensureCacheDir()
  if cacheDirPrepared then return end
  cacheDirPrepared = true
  if not noctalia.fileExists(cacheDir) then
    noctalia.runAsync("mkdir -p " .. shellQuote(cacheDir))
  end
end

local function loadFavorites()
  favorites = {}
  if noctalia.fileExists(favoritesPath) then
    local content = noctalia.readFile(favoritesPath)
    if content and content ~= "" then
      local ok, data = pcall(function() return noctalia.json.decode(content) end)
      if ok and type(data) == "table" then
        favorites = data
      end
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
  if not path or path == "" then return false end
  return favorites[path] == true
end

local render

local function toggleFavorite(path)
  if not path or path == "" then return end
  if favorites[path] then
    favorites[path] = nil
    if noctalia.getConfig("notify_on_change") ~= false then
      noctalia.notify(tr("panel.title"), tr("notify.favorite_removed"))
    end
  else
    favorites[path] = true
    if noctalia.getConfig("notify_on_change") ~= false then
      noctalia.notify(tr("panel.title"), tr("notify.favorite_added"))
    end
  end
  saveFavorites()
  if render then
    render()
  end
end

local function resolveFolderPalette(folderName)
  local norm = normalizeName(folderName)
  for _, bName in ipairs(BUILTIN_PALETTES) do
    if norm == normalizeName(bName) then
      return { source = "builtin", name = bName }
    end
  end
  local customs = getCustomPalettes()
  for _, cName in ipairs(customs) do
    if norm == normalizeName(cName) then
      return { source = "custom", name = cName }
    end
  end
  local comms = getCommunityPalettes()
  for _, cName in ipairs(comms) do
    if norm == normalizeName(cName) then
      return { source = "community", name = cName }
    end
  end
  return { source = "wallpaper", name = "soft" }
end

local function loadCollectionsFile()
  if not noctalia.fileExists(collectionsPath) then
    return {}
  end
  local content = noctalia.readFile(collectionsPath)
  if not content or content == "" then
    return {}
  end
  local ok, data = pcall(function() return noctalia.json.decode(content) end)
  if ok and type(data) == "table" then
    return data
  end
  return {}
end

local function saveCollectionsFile(list)
  local ok, encoded = pcall(function() return noctalia.json.encode(list) end)
  if ok and encoded then
    noctalia.writeFile(collectionsPath, encoded)
  end
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
  return string.format("%s/%s_%08x.jpg", cacheDir, safeBase, h)
end

local function makeGenerateCmd(src, dst)
  return string.format(
    "[ -d %s ] || mkdir -p %s; if command -v magick >/dev/null 2>&1; then nice -n 19 magick %s -thumbnail 512x288\\> %s >/dev/null 2>&1; elif command -v convert >/dev/null 2>&1; then nice -n 19 convert %s -thumbnail 512x288\\> %s >/dev/null 2>&1; elif command -v ffmpeg >/dev/null 2>&1; then nice -n 19 ffmpeg -y -i %s -vf \"scale=512:288:force_original_aspect_ratio=decrease\" %s >/dev/null 2>&1; fi",
    shellQuote(cacheDir), shellQuote(cacheDir),
    shellQuote(src), shellQuote(dst),
    shellQuote(src), shellQuote(dst),
    shellQuote(src), shellQuote(dst)
  )
end

local function resolveDisplayPath(originalPath)
  if not originalPath or originalPath == "" then return originalPath end
  ensureCacheDir()
  local thumb = getThumbPath(originalPath)
  if noctalia.fileExists(thumb) then
    return thumb
  end

  if not generatingPending[originalPath] then
    generatingPending[originalPath] = true
    local cmd = makeGenerateCmd(originalPath, thumb)
    noctalia.runAsync(cmd, function()
      generatingPending[originalPath] = nil
      if isOpen and noctalia.fileExists(thumb) and render then
        render()
      end
    end)
  end

  return originalPath
end

local function triggerBatchThumbnails(items)
  local list = items or allWallpapers
  if batchRunning or #list == 0 then return end
  ensureCacheDir()

  local missing = {}
  for _, item in ipairs(list) do
    local p = item.path or item.coverPath
    if p then
      local thumb = getThumbPath(p)
      if not noctalia.fileExists(thumb) then
        table.insert(missing, { src = p, dst = thumb })
      end
    end
  end

  if #missing == 0 then return end
  batchRunning = true

  local chunkSize = 25
  local chunkIndex = 1

  local function processNextChunk()
    if chunkIndex > #missing then
      batchRunning = false
      return
    end

    local scriptParts = {
      "[ -d " .. shellQuote(cacheDir) .. " ] || mkdir -p " .. shellQuote(cacheDir) .. "; ",
      "if command -v magick >/dev/null 2>&1; then GEN=magick; ",
      "elif command -v convert >/dev/null 2>&1; then GEN=convert; ",
      "elif command -v ffmpeg >/dev/null 2>&1; then GEN=ffmpeg; ",
      "else exit 0; fi; ",
      "gen() { if [ ! -f \"$2\" ]; then if [ \"$GEN\" = \"ffmpeg\" ]; then nice -n 19 ffmpeg -y -i \"$1\" -vf \"scale=512:288:force_original_aspect_ratio=decrease\" \"$2\" >/dev/null 2>&1; else nice -n 19 \"$GEN\" \"$1\" -thumbnail 512x288\\> \"$2\" >/dev/null 2>&1; fi; fi; }; ",
    }

    local chunkEnd = math.min(chunkIndex + chunkSize - 1, #missing)
    for i = chunkIndex, chunkEnd do
      local it = missing[i]
      table.insert(scriptParts, string.format("gen %s %s; ", shellQuote(it.src), shellQuote(it.dst)))
    end

    chunkIndex = chunkEnd + 1
    local batchCmd = table.concat(scriptParts)

    noctalia.runAsync(batchCmd, function()
      if isOpen and render then
        render()
      end
      processNextChunk()
    end)
  end

  processNextChunk()
end

local function isImage(name)
  local lower = name:lower()
  return lower:match("%.png$") ~= nil
      or lower:match("%.jpg$") ~= nil
      or lower:match("%.jpeg$") ~= nil
      or lower:match("%.webp$") ~= nil
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

local function scanImagesInDir(dir, list, depth)
  if depth > 2 then return end
  local entries = noctalia.listDir(dir)
  if not entries then return end

  for _, name in ipairs(entries) do
    if name ~= "." and name ~= ".." and not name:match("^%.") then
      local fullPath = dir .. "/" .. name
      if isImage(name) then
        local cleanName = name:gsub("%.%w+$", "")
        table.insert(list, {
          path = fullPath,
          name = cleanName,
          filename = name,
          sortKey = makeSortKey(cleanName),
        })
      else
        local info = noctalia.fileInfo(fullPath)
        if info and info.isDir then
          scanImagesInDir(fullPath, list, depth + 1)
        end
      end
    end
  end
end

local function refreshActiveWallpaper(callback)
  local active = getCurrentWallpaper()
  if active and active ~= "" then
    currentWallpaper = active
    if callback then callback() end
    return
  end

  noctalia.runAsync("noctalia msg wallpaper-get", function(result)
    if result and result.exitCode == 0 and result.stdout then
      currentWallpaper = result.stdout:gsub("%s+$", "")
    end
    if callback then callback() end
  end, 1500)
end

local function loadAllFolders()
  isScanning = true
  loadFavorites()

  local folderList = {}

  -- 1. Load collections from ~/.config/noctalia/wallpaper-collections.json
  local customCollections = loadCollectionsFile()
  if #customCollections > 0 then
    for _, entry in ipairs(customCollections) do
      if entry.path and entry.path ~= "" then
        local expDir = noctalia.expandPath(entry.path)
        local dInfo = noctalia.fileInfo(expDir)
        if dInfo and dInfo.isDir then
          local wps = {}
          scanImagesInDir(expDir, wps, 0)
          if #wps > 0 then
            table.sort(wps, function(a, b) return a.sortKey < b.sortKey end)
            local fName = entry.name or expDir:match("([^/]+)$") or "Collection"
            local palType = entry.palette_type or "builtin"
            local palName = (entry.palette and entry.palette ~= "") and entry.palette or fName
            table.insert(folderList, {
              name = fName,
              path = expDir,
              coverPath = wps[1].path,
              count = #wps,
              wallpapers = wps,
              palette = { source = palType, name = palName },
              sortKey = makeSortKey(fName),
            })
          end
        end
      end
    end
  end

  local knownPaths = {}
  for _, f in ipairs(folderList) do
    knownPaths[f.path] = true
  end

  -- 2. Scan subfolders of wallpaper_dir (avoiding duplicates already configured)
  local baseDir = noctalia.getConfig("wallpaper_dir")
  if type(baseDir) == "string" and baseDir ~= "" then
    baseDir = noctalia.expandPath(baseDir)
  elseif noctalia.wallpaperDirectory then
    local ok, d = pcall(function() return noctalia.wallpaperDirectory() end)
    if ok and type(d) == "string" and d ~= "" then
      baseDir = d
    end
  end
  if not baseDir or baseDir == "" or not noctalia.fileExists(baseDir) then
    if noctalia.fileExists(home .. "/Imágenes/Wallpapers") then
      baseDir = home .. "/Imágenes/Wallpapers"
    elseif noctalia.fileExists(home .. "/Pictures/wallpapers") then
      baseDir = home .. "/Pictures/wallpapers"
    elseif noctalia.fileExists(home .. "/Imágenes") then
      baseDir = home .. "/Imágenes"
    elseif noctalia.fileExists(home .. "/Pictures") then
      baseDir = home .. "/Pictures"
    end
  end

  if baseDir and noctalia.fileExists(baseDir) then
    local entries = noctalia.listDir(baseDir)
    local rootImages = {}

    if entries then
      for _, name in ipairs(entries) do
        if name ~= "." and name ~= ".." and not name:match("^%.") then
          local fullPath = baseDir .. "/" .. name
          local info = noctalia.fileInfo(fullPath)
          if info and info.isDir then
            if not knownPaths[fullPath] then
              local wps = {}
              scanImagesInDir(fullPath, wps, 0)
              if #wps > 0 then
                table.sort(wps, function(a, b) return a.sortKey < b.sortKey end)
                local pal = resolveFolderPalette(name)
                table.insert(folderList, {
                  name = name,
                  path = fullPath,
                  coverPath = wps[1].path,
                  count = #wps,
                  wallpapers = wps,
                  palette = pal,
                  sortKey = makeSortKey(name),
                })
                knownPaths[fullPath] = true
              end
            end
          elseif isImage(name) then
            local cleanName = name:gsub("%.%w+$", "")
            table.insert(rootImages, {
              path = fullPath,
              name = cleanName,
              filename = name,
              sortKey = makeSortKey(cleanName),
            })
          end
        end
      end
    end

    if #rootImages > 0 and not knownPaths[baseDir] then
      table.sort(rootImages, function(a, b) return a.sortKey < b.sortKey end)
      local rootName = baseDir:match("([^/]+)$") or "Wallpapers"
      table.insert(folderList, 1, {
        name = rootName,
        path = baseDir,
        coverPath = rootImages[1].path,
        count = #rootImages,
        wallpapers = rootImages,
        palette = { source = "wallpaper", name = "soft" },
        sortKey = makeSortKey(rootName),
      })
    end
  end

  -- 3. Add Favorites collection if there are saved favorites
  local favList = {}
  for favPath, _ in pairs(favorites) do
    if noctalia.fileExists(favPath) then
      local fname = favPath:match("([^/]+)$") or favPath
      local cname = fname:gsub("%.%w+$", "")
      table.insert(favList, {
        path = favPath,
        name = cname,
        filename = fname,
        sortKey = makeSortKey(cname),
      })
    end
  end

  if #favList > 0 then
    table.sort(favList, function(a, b) return a.sortKey < b.sortKey end)
    table.insert(folderList, 1, {
      name = "★ " .. tr("panel.favorites"),
      path = "favorites://",
      coverPath = favList[1].path,
      count = #favList,
      wallpapers = favList,
      palette = { source = "wallpaper", name = "soft" },
      sortKey = " 00000_favorites",
      isFavoritesFolder = true,
    })
  end

  allFolders = folderList
  isScanning = false

  refreshActiveWallpaper(function()
    if currentWallpaper ~= "" and #allFolders > 0 then
      for i, f in ipairs(allFolders) do
        for _, wp in ipairs(f.wallpapers) do
          if wp.path == currentWallpaper then
            selectedFolderIndex = i
            displayedFolderIndex = i
            break
          end
        end
      end
    end

    local covers = {}
    for _, f in ipairs(allFolders) do
      table.insert(covers, { coverPath = f.coverPath })
    end
    triggerBatchThumbnails(covers)

    if isOpen and render then
      render()
    end
  end)
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

local function scheduleFolderDisplay()
  navToken = navToken + 1
  local cur = navToken
  render()
  noctalia.runAsync({"sleep", "0.040"}, function()
    if isOpen and navToken == cur then
      displayedFolderIndex = selectedFolderIndex
      render()
    end
  end)
end

local function stepFolderSelection(delta)
  local total = #allFolders
  if total == 0 then return end
  selectedFolderIndex = ((selectedFolderIndex - 1 + delta) % total) + 1

  local leftIdx = ((selectedFolderIndex - 2 + total) % total) + 1
  local rightIdx = (selectedFolderIndex % total) + 1
  local cached = noctalia.fileExists(getThumbPath(allFolders[selectedFolderIndex].coverPath))
             and noctalia.fileExists(getThumbPath(allFolders[leftIdx].coverPath))
             and noctalia.fileExists(getThumbPath(allFolders[rightIdx].coverPath))

  if cached then
    displayedFolderIndex = selectedFolderIndex
    render()
  else
    scheduleFolderDisplay()
  end
end

local function scheduleWallpaperDisplay()
  navToken = navToken + 1
  local cur = navToken
  render()
  noctalia.runAsync({"sleep", "0.040"}, function()
    if isOpen and navToken == cur then
      displayedIndex = selectedIndex
      render()
    end
  end)
end

local function stepWallpaperSelection(delta)
  local total = #allWallpapers
  if total == 0 then return end
  selectedIndex = ((selectedIndex - 1 + delta) % total) + 1

  local leftIdx = ((selectedIndex - 2 + total) % total) + 1
  local rightIdx = (selectedIndex % total) + 1
  local cached = noctalia.fileExists(getThumbPath(allWallpapers[selectedIndex].path))
             and noctalia.fileExists(getThumbPath(allWallpapers[leftIdx].path))
             and noctalia.fileExists(getThumbPath(allWallpapers[rightIdx].path))

  if cached then
    displayedIndex = selectedIndex
    render()
  else
    scheduleWallpaperDisplay()
  end
end

local function openFolder(folderIdx)
  if #allFolders == 0 then return end
  local f = allFolders[folderIdx]
  if not f or #f.wallpapers == 0 then return end

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
  render()
end

local function backToFolders()
  viewMode = "folders"
  isScanning = true
  render()
  noctalia.runAsync({"sleep", "0.020"}, function()
    loadAllFolders()
  end)
end

local function openAddCollection()
  viewMode = "add_collection"
  addFolderPath = ""
  addPaletteType = "builtin"
  addPaletteName = BUILTIN_PALETTES[1] or "Nord"
  addPaletteSearch = ""
  addErrorMessage = ""
  render()
end

local function submitAddCollection()
  local trimmedPath = (addFolderPath or ""):match("^%s*(.-)%s*$") or ""
  if trimmedPath == "" then
    addErrorMessage = tr("panel.invalid_folder")
    render()
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
    render()
    return
  end

  local folderBaseName = expPath:match("([^/]+)$") or "Collection"
  local finalPaletteName = addPaletteName
  if not finalPaletteName or finalPaletteName == "" then
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

  if noctalia.getConfig("notify_on_change") ~= false then
    noctalia.notify(tr("panel.title"), tr("notify.collection_added") .. ": " .. folderBaseName)
  end

  viewMode = "folders"
  isScanning = true
  render()

  noctalia.runAsync({"sleep", "0.020"}, function()
    loadAllFolders()
  end)
end

local function applyFolderPalette(palette)
  if noctalia.getConfig("apply_palette") == false then return end
  if not palette or not palette.source or palette.source == "none" then return end

  local cmd = string.format(
    "noctalia msg color-scheme-set %s %s",
    shellQuote(palette.source),
    shellQuote(palette.name or "soft")
  )
  noctalia.runAsync(cmd)
end

local function applyWallpaper(path)
  currentWallpaper = path
  render()

  if noctalia.setWallpaper then
    noctalia.setWallpaper(path)
  else
    noctalia.runAsync("noctalia msg wallpaper-set " .. shellQuote(path))
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

  -- VIEW MODE: ADD COLLECTION
  if viewMode == "add_collection" then
    local allAvailable = getPalettesForType(addPaletteType)
    local filteredPalettes = {}
    local query = addPaletteSearch:lower():gsub("%s+", "")
    for _, pName in ipairs(allAvailable) do
      if query == "" or pName:lower():gsub("%s+", ""):find(query, 1, true) then
        table.insert(filteredPalettes, pName)
      end
    end

    -- Build compact rows of clickable palette buttons
    local paletteGridRows = {}
    local currentRow = {}
    local itemsPerRow = 4
    for i, pName in ipairs(filteredPalettes) do
      local isChosen = (pName == addPaletteName)
      table.insert(currentRow, ui.button({
        text = pName,
        variant = isChosen and "primary" or "outline",
        controlSize = "sm",
        onClick = function()
          addPaletteName = pName
          render()
        end,
      }))
      if #currentRow == itemsPerRow or i == #filteredPalettes then
        table.insert(paletteGridRows, ui.row({ gap = 6, align = "center" }, currentRow))
        currentRow = {}
      end
    end

    local paletteSectionChildren = {
      ui.row({
        align = "center",
        justify = "space_between",
      }, {
        ui.label({ text = tr("panel.palette_name"), fontSize = 12, fontWeight = "bold", color = "on_surface" }),
        ui.row({
          align = "center",
          gap = 6,
          paddingH = 10,
          paddingV = 4,
          radius = rBadge,
          fill = "primary/0.25",
        }, {
          ui.glyph({ name = "palette", size = 12, color = "primary" }),
          ui.label({ text = (addPaletteName ~= "" and addPaletteName or "-"), fontSize = 11, fontWeight = "bold", color = "primary" }),
        }),
      }),
    }

    if #allAvailable > 8 then
      table.insert(paletteSectionChildren, ui.input({
        key = "search_palette_input_" .. addPaletteType,
        placeholder = "Filtrar paletas...",
        value = addPaletteSearch,
        width = 496,
        onChange = function(val)
          addPaletteSearch = val or ""
          render()
        end,
      }))
    end

    if #paletteGridRows > 0 then
      table.insert(paletteSectionChildren, ui.scroll({
        height = 90,
        gap = 5,
      }, paletteGridRows))
    else
      local emptyMsg = (addPaletteType == "custom") and tr("panel.palette_name_custom_empty") or tr("panel.palette_name_community_empty")
      if addPaletteSearch ~= "" then
        emptyMsg = "Sin resultados para '" .. addPaletteSearch .. "'"
      end
      table.insert(paletteSectionChildren, ui.label({
        text = emptyMsg,
        fontSize = 11,
        color = "on_surface_variant",
      }))
    end

    local paletteDisplaySection = ui.column({ gap = 6 }, paletteSectionChildren)

    local cardItems = {
      -- Header
      ui.row({
        align = "center",
        justify = "space_between",
      }, {
        ui.row({ align = "center", gap = 8 }, {
          ui.glyph({ name = "folder-plus", size = 18, color = "primary" }),
          ui.label({ text = tr("panel.add_collection_title"), fontSize = 15, fontWeight = "bold", color = "on_surface" }),
        }),
        ui.button({
          glyph = "x",
          variant = "ghost",
          controlSize = "sm",
          onClick = function()
            viewMode = "folders"
            render()
          end,
        }),
      }),

      -- 1. Folder Path
      ui.column({ gap = 5 }, {
        ui.label({ text = tr("panel.folder_path"), fontSize = 12, fontWeight = "bold", color = "on_surface" }),
        ui.input({
          key = "add_folder_input",
          placeholder = tr("panel.folder_path_placeholder"),
          value = addFolderPath,
          width = 496,
          onChange = function(val)
            addFolderPath = val or ""
            addErrorMessage = ""
          end,
          onSubmit = function()
            submitAddCollection()
          end,
        }),
      }),

      -- 2. Palette Type Selector (Buttons)
      ui.column({ gap = 6 }, {
        ui.label({ text = tr("panel.palette_type"), fontSize = 12, fontWeight = "bold", color = "on_surface" }),
        ui.row({ gap = 8, align = "center" }, {
          ui.button({
            text = tr("panel.palette_source_builtin"),
            variant = (addPaletteType == "builtin") and "primary" or "outline",
            controlSize = "sm",
            onClick = function()
              addPaletteType = "builtin"
              addPaletteSearch = ""
              addPaletteName = BUILTIN_PALETTES[1] or "Nord"
              render()
            end,
          }),
          ui.button({
            text = tr("panel.palette_source_wallpaper"),
            variant = (addPaletteType == "wallpaper") and "primary" or "outline",
            controlSize = "sm",
            onClick = function()
              addPaletteType = "wallpaper"
              addPaletteSearch = ""
              addPaletteName = WALLPAPER_PALETTES[1] or "soft"
              render()
            end,
          }),
          ui.button({
            text = tr("panel.palette_source_custom"),
            variant = (addPaletteType == "custom") and "primary" or "outline",
            controlSize = "sm",
            onClick = function()
              addPaletteType = "custom"
              addPaletteSearch = ""
              local customs = getCustomPalettes()
              addPaletteName = customs[1] or ""
              render()
            end,
          }),
          ui.button({
            text = tr("panel.palette_source_community"),
            variant = (addPaletteType == "community") and "primary" or "outline",
            controlSize = "sm",
            onClick = function()
              addPaletteType = "community"
              addPaletteSearch = ""
              local comms = getCommunityPalettes()
              addPaletteName = comms[1] or ""
              render()
            end,
          }),
        }),
      }),

      -- 3. Palette Selection
      paletteDisplaySection,
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
      justify = "space_between",
      paddingV = 4,
    }, {
      ui.button({
        text = tr("panel.cancel"),
        variant = "outline",
        controlSize = "sm",
        onClick = function()
          viewMode = "folders"
          render()
        end,
      }),
      ui.button({
        text = tr("panel.save"),
        glyph = "check",
        variant = "primary",
        controlSize = "sm",
        onClick = function()
          submitAddCollection()
        end,
      }),
    }))

    panel.render(ui.column({
      width = 1160,
      height = 430,
      align = "center",
      justify = "center",
    }, {
      ui.column({
        width = 540,
        gap = 12,
        padding = 20,
        radius = rCenter,
        fill = "surface_variant/0.35",
        borderWidth = 1,
        border = "outline",
      }, cardItems),
    }))
    return
  end

  -- VIEW MODE: FOLDERS (LEVEL 1)
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
          render()
        end,
      }, {
        ui.image({
          key = "folder-img-left",
          path = resolveDisplayPath(fLeft.coverPath),
          width = 280,
          height = 158,
          fit = "cover",
          radius = rSide,
          borderWidth = 0,
        }),
      }),

      ui.column({
        key = "folder-card-center",
        align = "center",
        width = 460,
        onClick = function()
          openFolder(selectedFolderIndex)
        end,
      }, {
        ui.image({
          key = "folder-img-center",
          path = resolveDisplayPath(fCenter.coverPath),
          width = 460,
          height = 259,
          fit = "cover",
          radius = rCenter,
          borderWidth = 3,
          border = "primary",
        }),
      }),

      ui.column({
        key = "folder-card-right",
        align = "center",
        width = 280,
        opacity = 0.55,
        onClick = function()
          selectedFolderIndex = idxRight
          displayedFolderIndex = idxRight
          render()
        end,
      }, {
        ui.image({
          key = "folder-img-right",
          path = resolveDisplayPath(fRight.coverPath),
          width = 280,
          height = 158,
          fit = "cover",
          radius = rSide,
          borderWidth = 0,
        }),
      }),
    })

    local infoSection = ui.column({
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

      ui.label({
        text = tr("panel.manage_collections_hint"),
        fontSize = 10,
        color = "on_surface_variant",
        opacity = 0.75,
      }),
    })

    panel.render(ui.column({
      padding = 24,
      gap = 14,
      align = "stretch",
      flexGrow = 1,
    }, {
      carouselRow,
      infoSection,
    }))
    return
  end

  -- VIEW MODE: WALLPAPERS (LEVEL 2)
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
        render()
      end,
    }, {
      ui.image({
        key = "img-left",
        path = resolveDisplayPath(wpLeft.path),
        width = 280,
        height = 158,
        fit = "cover",
        radius = rSide,
        borderWidth = (wpLeft.path == currentWallpaper) and 2 or 0,
        border = (wpLeft.path == currentWallpaper) and "primary" or nil,
      }),
    }),

    ui.column({
      key = "card-center",
      align = "center",
      width = 460,
      onClick = function()
        applyWallpaper(wpCenter.path)
      end,
    }, {
      ui.image({
        key = "img-center",
        path = resolveDisplayPath(wpCenter.path),
        width = 460,
        height = 259,
        fit = "cover",
        radius = rCenter,
        borderWidth = (wpCenter.path == currentWallpaper) and 3 or 1,
        border = (wpCenter.path == currentWallpaper) and "primary" or "outline",
      }),
    }),

    ui.column({
      key = "card-right",
      align = "center",
      width = 280,
      opacity = 0.55,
      onClick = function()
        selectedIndex = idxRight
        displayedIndex = idxRight
        render()
      end,
    }, {
      ui.image({
        key = "img-right",
        path = resolveDisplayPath(wpRight.path),
        width = 280,
        height = 158,
        fit = "cover",
        radius = rSide,
        borderWidth = (wpRight.path == currentWallpaper) and 2 or 0,
        border = (wpRight.path == currentWallpaper) and "primary" or nil,
      }),
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
      fill = isCurrentFav and "primary/0.2" or "surface_variant/0.5",
      onClick = function()
        if #allWallpapers > 0 and selectedIndex >= 1 and selectedIndex <= #allWallpapers then
          toggleFavorite(allWallpapers[selectedIndex].path)
        end
      end,
    }, {
      ui.glyph({
        name = isCurrentFav and "star-filled" or "star",
        size = 13,
        color = isCurrentFav and "primary" or "on_surface_variant",
      }),
      ui.label({
        text = tr("panel.favorite"),
        fontSize = 10,
        fontWeight = "bold",
        color = isCurrentFav and "primary" or "on_surface_variant",
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
    padding = 24,
    gap = 14,
    align = "stretch",
    flexGrow = 1,
  }, {
    carouselRow,
    infoSection,
  }))
end

function onKey(chord, pressed)
  if not pressed then return end

  if viewMode == "add_collection" then
    if chord == "Escape" then
      viewMode = "folders"
      render()
    elseif chord == "Return" then
      submitAddCollection()
    end
    return
  end

  if viewMode == "folders" then
    if chord == "a" or chord == "A" then
      openAddCollection()
    elseif chord == "Left" or chord == "Up" then
      stepFolderSelection(-1)
    elseif chord == "Right" or chord == "Down" then
      stepFolderSelection(1)
    elseif chord == "Return" then
      openFolder(selectedFolderIndex)
    elseif chord == "Space" then
      if #allFolders > 0 then
        openFolder(math.random(1, #allFolders))
      end
    elseif chord == "Escape" then
      panel.close()
    end
    return
  end

  -- viewMode == "wallpapers"
  if chord == "Left" or chord == "Up" then
    stepWallpaperSelection(-1)
  elseif chord == "Right" or chord == "Down" then
    stepWallpaperSelection(1)
  elseif chord == "Return" then
    if #allWallpapers > 0 and selectedIndex >= 1 and selectedIndex <= #allWallpapers then
      displayedIndex = selectedIndex
      applyWallpaper(allWallpapers[selectedIndex].path)
    end
  elseif chord == "Delete" or chord == "Backspace" or chord == "BackSpace" then
    backToFolders()
  elseif chord == "f" or chord == "F" then
    if #allWallpapers > 0 and selectedIndex >= 1 and selectedIndex <= #allWallpapers then
      toggleFavorite(allWallpapers[selectedIndex].path)
    end
  elseif chord == "Space" then
    applyRandomWallpaper()
  elseif chord == "Escape" then
    panel.close()
  end
end

local lastScrollTime = 0

function onScroll(axis, steps, _startsGesture)
  if axis ~= "vertical" then return end
  local now = os.clock()
  if now - lastScrollTime < 0.12 then return end
  lastScrollTime = now

  local delta = (steps or 0) > 0 and 1 or -1
  if viewMode == "folders" then
    stepFolderSelection(delta)
  elseif viewMode == "wallpapers" then
    stepWallpaperSelection(delta)
  end
end

function onOpen(_context)
  isOpen = true
  viewMode = "folders"
  loadAllFolders()
end

function onClose()
  isOpen = false
end

loadAllFolders()
