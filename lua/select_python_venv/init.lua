local finder = require("select_python_venv.finder")
local persist = require("select_python_venv.persist")

local M = {}

local function normalize(path)
  return path:gsub("\\", "/")
end

M.config = { auto_detect = true }

local function extra_for(name, python_path)
  if name == "pyright" then
    return { settings = { pyright = { pythonPath = python_path } } }
  elseif name == "basedpyright" then
    return { settings = { basedpyright = { pythonPath = python_path } } }
  elseif name == "ty" then
    return { settings = { ty = { configuration = { environment = { python = python_path } } } } }
  elseif name == "ruff" then
    return { init_options = { settings = { interpreter = { python_path } } } }
  end
end

local function config_has_path(client, python_path)
  return vim.inspect(client.config):find(vim.pesc(python_path)) ~= nil
end

vim.api.nvim_create_autocmd("LspAttach", {
  desc = "Ensure Python LSP clients are using the venv interpreter",
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
      return
    end

    local python_path = M.get_venv_path()
    if not python_path then
      return
    end

    local extra = extra_for(client.name, python_path)
    if not extra then
      return
    end

    -- Already configured by the vim.lsp.start wrapper; nothing to do
    if config_has_path(client, python_path) then
      return
    end

    -- This client missed our wrapper; restart it now (it has been running
    -- for a while so stop is safe)
    local merged = vim.tbl_deep_extend("force", client.config, extra)
    if not client.is_stopped() then
      client:stop()
    end
    vim.schedule(function()
      pcall(vim.lsp.start, merged)
    end)
    vim.notify("select_python_venv: configured " .. client.name, vim.log.levels.INFO)
  end,
})

local original_start = vim.lsp.start
vim.lsp.start = function(config, opts)
  config = config or {}
  local python_path = M.get_venv_path()
  if python_path then
    local extra = extra_for(config.name, python_path)
    if extra then
      config = vim.tbl_deep_extend("force", config, extra)
    end
  end
  return original_start(config, opts)
end

local function get_venv_root()
  local cwd = normalize(vim.fn.getcwd())
  local stored = persist.get_stored(cwd)

  if stored and vim.fn.isdirectory(stored) == 1 then
    return stored
  end

  local venvs = finder.find_venvs()
  if #venvs == 0 then
    return nil
  end

  local chosen = venvs[1]
  persist.set_stored(cwd, chosen)
  return chosen
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if not M.config.auto_detect then
    return
  end
  vim.schedule(function()
    if get_venv_root() then
      M.restart_lsp()
    end
  end)
end

function M.get_venv_path()
  local root = get_venv_root()
  if root then
    return finder.interpreter_path(root)
  end
  return nil
end

function M.get_venv_name()
  local root = get_venv_root()
  if root then
    return vim.fn.fnamemodify(root, ":t")
  end
  return nil
end

function M.clear_venv()
  local cwd = normalize(vim.fn.getcwd())
  local data = persist.load()
  data[cwd] = nil
  persist.save(data)
  vim.notify("select_python_venv: cleared for this project, using system python", vim.log.levels.INFO)
end

function M.show_path()
  local path = M.get_venv_path()
  if path then
    vim.notify("select_python_venv: " .. path, vim.log.levels.INFO)
  else
    vim.notify("select_python_venv: no venv configured", vim.log.levels.WARN)
  end
end

function M.restart_lsp()
  local python_path = M.get_venv_path()
  if not python_path then
    vim.notify("select_python_venv: no venv configured for this project", vim.log.levels.WARN)
    return
  end

  for name, _ in pairs({
    pyright = true,
    basedpyright = true,
    ty = true,
    ruff = true,
  }) do
    if vim.lsp.config[name] then
      local extra = extra_for(name, python_path)
      if extra then
        vim.lsp.config[name] = vim.tbl_deep_extend("force", vim.lsp.config[name], extra)
      end
    end
  end

  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local restarted = 0
  for _, client in ipairs(clients) do
    local extra = extra_for(client.name, python_path)
    if extra then
      if config_has_path(client, python_path) then
        restarted = restarted + 1
      else
        local merged = vim.tbl_deep_extend("force", client.config, extra)
        if not client.is_stopped() then
          client:stop()
        end
        vim.schedule(function()
          pcall(vim.lsp.start, merged)
        end)
        restarted = restarted + 1
        vim.notify("select_python_venv: restarted " .. client.name, vim.log.levels.INFO)
      end
    end
  end

  if restarted == 0 then
    vim.notify("select_python_venv: configured for future LSP starts", vim.log.levels.INFO)
  end
end

function M.select_path()
  local venvs = finder.find_venvs()
  if #venvs == 0 then
    vim.notify("select_python_venv: no virtual environments found", vim.log.levels.WARN)
    return
  end

  local cwd = normalize(vim.fn.getcwd())
  local items = {}
  for _, v in ipairs(venvs) do
    local rel = v:gsub("^" .. vim.pesc(cwd) .. "/", "./")
    table.insert(items, { path = v, label = rel })
  end

  vim.ui.select(items, {
    prompt = "Select Python venv",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      persist.set_stored(cwd, choice.path)
      vim.notify('select_python_venv: set to ' .. choice.label, vim.log.levels.INFO)
      M.restart_lsp()
    end
  end)
end

return M
