local augroup = vim.api.nvim_create_augroup('gitlog')

-- TODO: some of this ci stuff may need slop removal
-- not sure if this namespace is needed for example
local ci_ns = vim.api.nvim_create_namespace('gitlog-ci')

local function show_ci(buf, commits, cwd)
  local fields = {}
  local icons = {
    passed = '',
    failed = '',
    error = '',
    pending = '',
    expected = '',
    loading = '',
  }
  local colors = {
    passed = 'DiagnosticOk',
    failed = 'DiagnosticError',
    error = 'DiagnosticError',
    pending = 'DiagnosticWarn',
    expected = 'DiagnosticWarn',
    ['lookup failed'] = 'DiagnosticWarn',
  }
  local function display(i, label)
    local row = i + 1
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    local suffix = label == 'no checks' and '' or ' | CI: ' .. (icons[label] or label)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_text(buf, row, #commits[i + 2], row, #line, { suffix })
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ci_ns, row, row + 1)
    if suffix ~= '' then
      vim.hl.range(
        buf,
        ci_ns,
        colors[label] or 'Comment',
        { row, #commits[i + 2] + 3 },
        { row, -1 }
      )
    end
  end

  for i = 1, #commits, 4 do
    fields[#fields + 1] = string.format(
      'c%d: object(expression: "%s") { ... on Commit { statusCheckRollup { state } } }',
      i,
      commits[i]
    )
    display(i, 'loading')
  end

  local query = 'query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { '
    .. table.concat(fields, ' ')
    .. ' } }'
  local states = {
    SUCCESS = 'passed',
    FAILURE = 'failed',
    ERROR = 'error',
    PENDING = 'pending',
    EXPECTED = 'expected',
  }

  local function complete(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local ok, response = pcall(vim.json.decode, result.stdout or '')
      local repo = ok
        and type(response) == 'table'
        and type(response.data) == 'table'
        and response.data.repository
      local failed = result.code ~= 0 or type(repo) ~= 'table' or response.errors ~= nil
      for i = 1, #commits, 4 do
        local status = 'lookup failed'
        if not failed then
          local commit = repo['c' .. i]
          if type(commit) ~= 'table' then
            status = 'unavailable on GitHub'
          elseif type(commit.statusCheckRollup) ~= 'table' then
            status = 'no checks'
          else
            status = states[commit.statusCheckRollup.state] or 'unknown'
          end
        end
        display(i, status)
      end
    end)
  end

  local ok = pcall(vim.system, {
    'gh',
    'api',
    'graphql',
    '-F',
    'owner={owner}',
    '-F',
    'name={repo}',
    '-f',
    'query=' .. query,
  }, { cwd = cwd, text = true, timeout = 15000 }, complete)
  if not ok then
    complete({ code = 1 })
  end
end

local function get_commits(cwd)
  local result = vim
    -- Commits are separated with NUL byte %x00 because git commit messages cannot contain them
    .system({ 'git', 'log', '--format=%H%n%s%n%an | %ah%n%b%x00', '-n', '50' }, { cwd = cwd, text = true })
    :wait()

  if result.code ~= 0 then
    vim.notify(result.stderr, vim.log.levels.ERROR)
    return
  end

  local commits = {}

  for commit in result.stdout:gmatch('([^%z]+)') do
    local lines = vim.split(vim.trim(commit), '\n')
    -- Append ... if there is a body to the commit
    if #lines > 3 then
      lines[2] = lines[2] .. '...'
    end
    vim.list_extend(commits, vim.list_slice(lines, 1, 3))
    -- New line
    table.insert(commits, '')
  end

  -- FIXME: bit hacky here
  -- Remove the final new line
  table.remove(commits)
  table.remove(commits)

  return commits
end

local function show_commits()
  local cwd = vim.fn.getcwd()
  local commits = get_commits(cwd)
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
      { zero_index_line_num + 2, #commits[i + 2] }
    )
  end
  show_ci(buf, commits, cwd)
end

vim.api.nvim_create_user_command('GitLog', function()
  show_commits()
end)

vim.api.nvim_create_autocmd('FileType', {
  group = augroup,
  pattern = 'gitlog',
  callback = function()
    vim.keymap.set('n', 'dd', function()
      local commit_hash = vim.api.nvim_get_current_line()

      vim.cmd(([[DiffviewOpen %s~1...%s]]):format(commit_hash, commit_hash))
    end, { desc = 'View diff', buf = 0 })

    vim.keymap.set('n', 'gx', function()
      local commit_hash = vim.api.nvim_get_current_line()

      -- TODO: needs error handling
      vim.system({ 'gh', 'browse', commit_hash })
    end, { desc = 'View diff', buf = 0 })

    -- TODO: also needs error handling
    vim.keymap.set('n', 'K', function()
      local commit_hash = vim.api.nvim_get_current_line()
      local long_description = vim
        .system({ 'git', 'show', '--format=%s%n%n%b', '--no-patch', commit_hash }, { text = true })
        :wait()

      vim.lsp.util.open_floating_preview({ long_description.stdout }, 'plaintext', {
        max_width = 80,
        focus_id = 'my_plugin_hover',
      })
    end, { desc = 'Show details', buf = 0 })
  end,
})
