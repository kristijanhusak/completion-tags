local luv = vim.loop
local completion = require "completion"
local match = require "completion.matching"
local M = {}
local cache = {}

local getTagfiles = function ()
  local tagfiles = vim.fn.tagfiles()
  local list = {}
  if not tagfiles or #tagfiles == 0 then return list end
  local cwd = vim.fn.getcwd()
  for _, tagfile in ipairs(tagfiles) do
    local path = tagfile
    if not path:find('/') then
      path = cwd..'/'..tagfile
    end
    local stat = luv.fs_stat(path)
    if stat and stat.type ~= 'directory' then
      table.insert(list, { file = path, mtime = stat.mtime.sec })
    end
  end

  return list
end

local splitLine = function (line)
  local entries = {}
  for item in line:gmatch('[^%s\t]+') do
    table.insert(entries, item)
  end
  return entries
end

local populateItems = function (tagfileLines)
  local items = {}
  for line in tagfileLines do
    if not line:match('^!') then
      local line_parts = splitLine(line)
      if #line_parts >= 2 then
        if items[line_parts[1]] ~= nil then
          table.insert(items[line_parts[1]], line_parts[2])
        else
          items[line_parts[1]] = {line_parts[2]}
        end
      end
    end
  end
  return items
end

local getTagfileItems = function(tagfile)
  local cache_item = cache[tagfile.file]
  if cache_item ~= nil and cache_item.mtime >= tagfile.mtime then
    return cache_item.items
  end
  luv.fs_open(tagfile.file, 'r', 438, function(err, fd)
    if err then return end
    luv.fs_fstat(fd, function(err, stat)
      if err then return end
      luv.fs_read(fd, stat.size, 0, function(err, data)
        if err then return end
        cache[tagfile.file] = {
          items = populateItems(data:gmatch('[^\r\n]+')),
          mtime = stat.mtime.sec
        }

        luv.fs_close(fd)
      end)
    end)
  end)

  return {}
end

local getCompletionItems = function(prefix)
  local items = {}
  local complete_items = {}
  if prefix == '' then
    return complete_items
  end
  local tagfiles = getTagfiles()
  for _, tagfile in ipairs(tagfiles) do
    items = vim.tbl_extend('force', items, getTagfileItems(tagfile))
  end

  for word, paths in pairs(items) do
    if prefix:sub(1, 1):lower() == word:sub(1,1):lower() then
      local hover = {unpack(paths, 1, 10)}
      if #paths > 10 then
        table.insert(hover, '... and '..(#paths - 10)..' more')
      end
      match.matching(complete_items, prefix, {
          word = word,
          abbr = word,
          dup = 0,
          empty = 0,
          icase = 1,
          menu = '[T]',
          user_data = vim.fn.json_encode({ hover = table.concat(hover, '\n') })
        })
    end
  end

  return complete_items
end

function M.add_sources()
  completion.addCompletionSource('tags', { item = getCompletionItems });
  -- Cache on init
  local tagfiles = getTagfiles()
  for _, tagfile in ipairs(tagfiles) do
    getTagfileItems(tagfile)
  end
end

return M
