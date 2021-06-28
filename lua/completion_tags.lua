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
  local is_context = false
  local context = ""
  local cstart = 1
  local cend = -1
  for item in line:gmatch('[^%s\t]+') do
    if item:sub(1, 2) == '/^' then
        is_context = true
        cstart = 3
    else
        cstart = 1
    end
    if item:sub(-3) == '/;"' then
        is_context = false
        if cstart == 1 then
            context = context .. ' ' .. item:sub(cstart, -5)
        end
        item = context
    end
    if not is_context then
        table.insert(entries, item)
    else
        context = context .. ' ' .. item:sub(cstart, cend)
    end
  end
  return entries
end

local populateItems = function (tagfileLines)
  local items_p = {}
  local items_i = {}
  for line in tagfileLines do
    if not line:match('^!') then
      local line_parts = splitLine(line)
      if #line_parts >= 2 then
        local name = line_parts[1]
        local path = line_parts[2]
        local context = line_parts[3]
        local tagtype = line_parts[4]

        local taginfo = '[T]'
        if tagtype ~= nil then
            taginfo = tagtype .. ' ' .. taginfo
        end
        if context ~= nil then
            path = path .. '\n' .. context
        end
        if items_p[name] ~= nil then
          if not vim.tbl_contains(items_p[name], path) then
            table.insert(items_p[name], path)
            table.insert(items_i[name], taginfo)
          end
        else
          items_p[name] = {path}
          items_i[name] = {taginfo}
        end
      end
    end
  end

  for name, paths in pairs(items_p) do
    local p = paths
    if #paths > 10 then
      p = {unpack(paths, 1, 10)}
      table.insert(p, '... and '..(#paths - 10)..' more')
    end
    items_p[name] = table.concat(p, '\n')
  end
  for name, info in pairs(items_i) do
    if #info > 1 then
        items_i[name] = '[T]'
        -- items_i[name] = items_i[name] .. table.concat(info, '\n')
    else
        items_i[name] = unpack(info)
    end
  end
  return items_p, items_i
end

local getTagfileItems = function(tagfile)
  local cache_item = cache[tagfile.file]
  if cache_item ~= nil and cache_item.mtime >= tagfile.mtime then
    return cache_item.items_p, cache_item.items_i
  end
  luv.fs_open(tagfile.file, 'r', 438, vim.schedule_wrap(function(err, fd)
    if err then return end
    luv.fs_fstat(fd, vim.schedule_wrap(function(er, stat)
      if er then return end
      luv.fs_read(fd, stat.size, 0, vim.schedule_wrap(function(e, data)
        if e then return end
        items_p, items_i = populateItems(data:gmatch('[^\r\n]+'))
        cache[tagfile.file] = {
          items_p = items_p,
          items_i = items_i,
          mtime = stat.mtime.sec
        }

        luv.fs_close(fd)
      end))
    end))
  end))

  return {}
end

local getCompletionItems = function(prefix)
  local items_p = {}
  local items_i = {}
  local complete_items = {}
  if prefix == '' then
    return complete_items
  end
  local tagfiles = getTagfiles()
  for _, tagfile in ipairs(tagfiles) do
    new_items_p, new_items_i = getTagfileItems(tagfile)
    items_p = vim.tbl_extend('force', items_p, new_items_p)
    items_i = vim.tbl_extend('force', items_i, new_items_i)
  end

  for word, paths in pairs(items_p) do
    if vim.startswith(word:lower(), prefix:lower()) then
      match.matching(complete_items, prefix, {
          word = word,
          abbr = word,
          dup = 0,
          empty = 0,
          icase = 1,
          menu = items_i[word],
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
