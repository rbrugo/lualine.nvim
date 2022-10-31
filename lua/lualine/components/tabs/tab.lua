local Tab = require('lualine.utils.class'):extend()

local modules = require('lualine_require').lazy_require {
  highlight = 'lualine.highlight',
  utils = 'lualine.utils.utils',
}

---initialize a new tab from opts
---@param opts table
function Tab:init(opts)
  assert(opts.tabnr, 'Cannot create Tab without tabnr')
  self.tabnr = opts.tabnr
  self.tabId = opts.tabId
  self.options = opts.options
  self.highlights = opts.highlights  --[[@type any[] ]]
  self.modified_icon = ''
  self.icon_hl_cache = opts.icon_hl_cache
  self:get_props()
end


Tab.create_hl = require('lualine.component').create_hl


function Tab:get_props()
  local buflist = vim.fn.tabpagebuflist(self.tabnr)
  local winnr = vim.fn.tabpagewinnr(self.tabnr)
  local bufnr = buflist[winnr]
  self.file = modules.utils.stl_escape(vim.api.nvim_buf_get_name(bufnr))
  self.filetype = vim.api.nvim_buf_get_option(bufnr, 'filetype')
  self.buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')

  if self.options.show_modified_status then
    for _, b in ipairs(buflist) do
      if vim.api.nvim_buf_get_option(b, 'modified') then
        self.modified_icon = self.options.symbols.modified or ''
        break
      end
    end
  end
end


---returns filetype for tab. Tabs ft is the filetype of buffer in last active window
--- of the tab.
---@return { icon: string, base_icon: string, ft_icon_len: number }
function Tab:ft_icon()
  if not self.options.ft_icons_enabled then
    return { icon = '', base_icon = '', ft_icon_len = 0}
  end

  local icon, base_icon, icon_highlight_group
  local icon_len = 0
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if ok then
    local win
    ok, win = pcall(vim.api.nvim_tabpage_get_win, self.tabnr)
    if ok then
      local buf
      ok, buf = pcall(vim.api.nvim_win_get_buf, win)
      if ok then
        local ft = vim.fn.getbufvar(buf --[[ @as integer ]], '&ft')
        icon, icon_highlight_group = devicons.get_icon_by_filetype(ft)

        if icon == nil and icon_highlight_group == nil then
          icon = ''
          icon_highlight_group = 'DevIconDefault'
        end
        base_icon = icon
        icon_len = vim.fn.strlen(icon)

        if self.options.ft_icons_colored then
          local highlight_color = modules.utils.extract_highlight_colors(icon_highlight_group, 'fg')
          if highlight_color then
            local is_active = self.current or false
            local current_highlight = self.highlights[is_active and 'active' or 'inactive']
            local mode_suffix = is_active and modules.highlight.get_mode_suffix() or '_inactive'

            local current_hl_with_mode_name = current_highlight.name .. mode_suffix
            local default_highlight = modules.highlight.get_lualine_hl(current_hl_with_mode_name)

            local icon_group_name = ("%s_%s%s_%s"):format(current_highlight.name, icon_highlight_group, mode_suffix, is_active and 'active' or 'inactive')
            local icon_highlight = self.icon_hl_cache[icon_group_name]

            if not icon_highlight or not modules.highlight.highlight_exists(icon_group_name) then
              local _, _, name = icon_group_name:find("^.-_.-_(.*)$")
              local background = default_highlight and default_highlight.bg or nil
              local color = {
                fg = highlight_color,
                bg = background,
              }
              icon_highlight = modules.highlight.create_component_highlight_group(
                color, name, self.options, false
              )
              self.icon_hl_cache[icon_group_name] = icon_highlight
            end

            local formatted_icon_highlight = modules.highlight.component_format_highlight(icon_highlight)
            local formatted_current_highlight = modules.highlight.component_format_highlight(current_highlight)
            icon = formatted_icon_highlight .. icon .. formatted_current_highlight
          end
        end
      end
    end
  end

  return { icon = icon, base_icon = base_icon, ft_icon_len = icon_len }
end

---returns name for tab. Tabs name is the name of buffer in last active window
--- of the tab.
---@return string
function Tab:label()
  local ok, custom_tabname = pcall(vim.api.nvim_tabpage_get_var, self.tabId, 'tabname')
  if not ok then
    custom_tabname = nil
  end
  if custom_tabname and custom_tabname ~= '' then
    return modules.utils.stl_escape(custom_tabname)
  end
  if self.filetype == 'fugitive' then
    return 'fugitive: ' .. vim.fn.fnamemodify(self.file, ':h:h:t')
  elseif self.buftype == 'help' then
    return 'help:' .. vim.fn.fnamemodify(self.file, ':t:r')
  elseif self.buftype == 'terminal' then
    local match = string.match(vim.split(self.file, ' ')[1], 'term:.*:(%a+)')
    return match ~= nil and match or vim.fn.fnamemodify(vim.env.SHELL, ':t')
  elseif self.file == '' then
    return '[No Name]'
  end
  if self.options.path == 1 then
    return vim.fn.fnamemodify(self.file, ':~:.')
  elseif self.options.path == 2 then
    return vim.fn.fnamemodify(self.file, ':p')
  elseif self.options.path == 3 then
    return vim.fn.fnamemodify(self.file, ':p:~')
  else
    return vim.fn.fnamemodify(self.file, ':t')
  end
end

---shortens path by turning apple/orange -> a/orange
---@param path string
---@param sep string path separator
---@param max_len integer maximum length of the full filename string
---@return string
local function shorten_path(path, sep, max_len)
  local len = #path
  if len <= max_len then
    return path
  end

  local segments = vim.split(path, sep)
  for idx = 1, #segments - 1 do
    if len <= max_len then
      break
    end

    local segment = segments[idx]
    local shortened = segment:sub(1, vim.startswith(segment, '.') and 2 or 1)
    segments[idx] = shortened
    len = len - (#segment - #shortened)
  end

  return table.concat(segments, sep)
end

---returns rendered tab
---@return string
function Tab:render()
  local name = self:label()
  local icon_result = self:ft_icon()
  local icon = icon_result.icon
  local base_icon = icon_result.base_icon
  local ft_icon_len = icon_result.ft_icon_len
  if self.options.tab_max_length ~= 0 then
    local path_separator = package.config:sub(1, 1)
    name = shorten_path(name, path_separator, self.options.tab_max_length)
  end
  if self.options.fmt then
    name = self.options.fmt(name or '', self)
  end
  if self.ellipse then -- show ellipsis
    name = '...'
  else
    -- different formats for different modes
    if self.options.mode == 0 then
      name = tostring(self.tabnr)
      if self.modified_icon ~= '' then
        name = string.format('%s%s', name, self.modified_icon)
      end
    elseif self.options.mode == 1 then
      if self.modified_icon ~= '' then
        name = string.format('%s %s', self.modified_icon, name)
      end
    else
      name = string.format('%s%s %s', tostring(self.tabnr), self.modified_icon, name)
    end
  end

  local original_len = vim.fn.strchars(name)
  if self.options.ft_icons_enabled and not self.ellipse and ft_icon_len > 0 then
    self.len = vim.fn.strchars(Tab.apply_padding(name .. ' ' .. base_icon, self.options.padding))
    name = Tab.apply_padding(name .. ' ' .. icon, self.options.padding)
  else
    name = Tab.apply_padding(name, self.options.padding)
    self.len = vim.fn.strchars(name)
  end


  -- setup for mouse clicks
  local line = string.format('%%%s@LualineSwitchTab@%s%%T', self.tabnr, name)
  -- apply highlight
  line = modules.highlight.component_format_highlight(self.highlights[(self.current and 'active' or 'inactive')])
    .. line

  -- apply separators
  if self.options.self.section < 'x' and not self.first then
    local sep_before = self:separator_before()
    line = sep_before .. line
    self.len = self.len + vim.fn.strchars(sep_before)
  elseif self.options.self.section >= 'x' and not self.last then
    local sep_after = self:separator_after()
    line = line .. sep_after
    self.len = self.len + vim.fn.strchars(sep_after)
  end
  return line
end

---apply separator before current tab
---@return string
function Tab:separator_before()
  if self.current or self.aftercurrent then
    return '%Z{' .. self.options.section_separators.left .. '}'
  else
    return self.options.component_separators.left
  end
end

---apply separator after current tab
---@return string
function Tab:separator_after()
  if self.current or self.beforecurrent then
    return '%z{' .. self.options.section_separators.right .. '}'
  else
    return self.options.component_separators.right
  end
end

---adds spaces to left and right
function Tab.apply_padding(str, padding)
  local l_padding, r_padding = 1, 1
  if type(padding) == 'number' then
    l_padding, r_padding = padding, padding
  elseif type(padding) == 'table' then
    l_padding, r_padding = padding.left or 0, padding.right or 0
  end
  return string.rep(' ', l_padding) .. str .. string.rep(' ', r_padding)
end

return Tab
