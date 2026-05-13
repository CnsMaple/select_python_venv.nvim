local finder = require("select_python_venv.finder")
local persist = require("select_python_venv.persist")

local M = {}

local function normalize(path)
  return path:gsub("\\", "/")
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config or {}, opts or {})
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

  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local count = 0
  for _, client in ipairs(clients) do
    local settings = client.config.settings
    if not settings then
      settings = {}
      client.config.settings = settings
    end

    if client.name == "pyright" then
      settings.pyright = settings.pyright or {}
      settings.pyright.pythonPath = python_path
      pcall(client.notify, client, "workspace/didChangeConfiguration", {
        settings = settings,
      })
      count = count + 1
      vim.notify("select_python_venv: updated pyright LSP", vim.log.levels.INFO)

    elseif client.name == "basedpyright" then
      settings.basedpyright = settings.basedpyright or {}
      settings.basedpyright.pythonPath = python_path
      pcall(client.notify, client, "workspace/didChangeConfiguration", {
        settings = settings,
      })
      count = count + 1
      vim.notify("select_python_venv: updated basedpyright LSP", vim.log.levels.INFO)

    elseif client.name == "ty" then
      settings.ty = settings.ty or {}
      settings.ty.environment = settings.ty.environment or {}
      settings.ty.environment.python = python_path
      pcall(client.notify, client, "workspace/didChangeConfiguration", {
        settings = settings,
      })
      count = count + 1
      vim.notify("select_python_venv: updated ty LSP", vim.log.levels.INFO)
    end
  end

  if count == 0 then
    local names = vim.tbl_map(function(c) return c.name end, clients)
    if #names > 0 then
      vim.notify("select_python_venv: no python LSP settings found in active clients: " .. table.concat(names, ", "), vim.log.levels.INFO)
    else
      vim.notify("select_python_venv: no LSP client active in this buffer", vim.log.levels.INFO)
    end
  else
    vim.notify("select_python_venv: sent config update to " .. count .. " LSP client(s)", vim.log.levels.INFO)
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
