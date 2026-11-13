local function get_commits()
  local result = vim
    .system({ 'git', 'log', '--format=%H%n%s%n%an | %ah%n', '-n', '50' }, { text = true })
    :wait()

  if result.code ~= 0 then
    vim.notify(result.stderr, vim.log.levels.ERROR)
    return
  end

  return vim.split(vim.trim(result.stdout), '\n')
end

local function show_commits()
  local commits = get_commits()
  if not commits then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_set_current_buf(buf)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, commits)
  vim.bo[buf].modifiable = false

  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'gitlog'

  -- Highlight stuff
  local ns = vim.api.nvim_create_namespace('gitlog')
  vim.api.nvim_set_hl(ns, 'Bold', { bold = true })

  for i = 1, #commits, 4 do
    local zero_index_line_num = i - 1
    vim.hl.range(buf, ns, 'Comment', { zero_index_line_num, 0 }, { zero_index_line_num, -1 })

    vim.hl.range(buf, ns, 'Bold', { zero_index_line_num + 1, 0 }, { zero_index_line_num + 1, -1 })
    vim.hl.range(buf, ns, 'Type', { zero_index_line_num + 1, 0 }, { zero_index_line_num + 1, -1 })

    local author = commits[i + 2]:match('^[^|]+')
    vim.hl.range(
      buf,
      ns,
      'Identifier',
      { zero_index_line_num + 2, 0 },
      { zero_index_line_num + 2, #author }
    )

    vim.hl.range(
      buf,
      ns,
      'Number',
      { zero_index_line_num + 2, #author + 1 },
      { zero_index_line_num + 2, -1 }
    )
  end
end

vim.api.nvim_create_user_command('GitLog', function()
  show_commits()
end)
