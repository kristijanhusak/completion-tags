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
        local name = line_parts[1]
        local path = line_parts[2]
        if items[name] ~= nil then
          if not vim.tbl_contains(items[name], path) then
            table.insert(items[name], path)
          end
        else
          items[name] = {path}
        end
      end
    end
  end

  for name, paths in pairs(items) do
    local p = paths
    if #paths > 10 then
      p = {unpack(paths, 1, 10)}
      table.insert(p, '... and '..(#paths - 10)..' more')
    end
    items[name] = table.concat(p, '\n')
  end
  return items
end

local getTagfileItems = function(tagfile)
  local cache_item = cache[tagfile.file]
  if cache_item ~= nil and cache_item.mtime >= tagfile.mtime then
    return cache_item.items
  end
  luv.fs_open(tagfile.file, 'r', 438, vim.schedule_wrap(function(err, fd)
    if err then return end
    luv.fs_fstat(fd, vim.schedule_wrap(function(er, stat)
      if er then return end
      luv.fs_read(fd, stat.size, 0, vim.schedule_wrap(function(e, data)
        if e then return end
        cache[tagfile.file] = {
          items = populateItems(data:gmatch('[^\r\n]+')),
          mtime = stat.mtime.sec
        }

        luv.fs_close(fd)
      end))
    end))
  end))

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
    if vim.startswith(word:lower(), prefix:lower()) then
      match.matching(complete_items, prefix, {
          word = word,
          abbr = word,
          dup = 0,
          empty = 0,
          icase = 1,
          menu = '[T]',
          user_data = vim.fn.json_encode({ hover = paths })
        })
    end
  end

  return complete_items
end

function M.add_sources()
  completion.addCompletionSource('tags', { item = getCompletionItems });
  -- Cache on init
  local tagfiles = getTagfiles()
  for i, tagfile in ipairs(tagfiles) do
    vim.defer_fn(function() getTagfileItems(tagfile) end, i * 200)
  end
end

return M
