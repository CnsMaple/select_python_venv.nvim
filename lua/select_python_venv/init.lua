local finder = require("select_python_venv.finder")
local persist = require("select_python_venv.persist")

local M = {}

local function normalize(path)
  return path:gsub("\\", "/")
end

M.config = { auto_detect = true }

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
    local root = get_venv_root()
    if root then
      vim.notify("select_python_venv: auto-applied " .. vim.fn.fnamemodify(root, ":t"), vim.log.levels.INFO)
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

  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local count = 0
  for _, client in ipairs(clients) do
    local config
    if client.name == "pyright" then
      config = { settings = { pyright = { pythonPath = python_path } } }
    elseif client.name == "basedpyright" then
      config = { settings = { basedpyright = { pythonPath = python_path } } }
    elseif client.name == "ty" then
      config = { settings = { ty = { configuration = { environment = { python = python_path } } } } }
    elseif client.name == "ruff" then
      config = { init_options = { settings = { interpreter = { python_path } } } }
    end

    if config then
      local name = client.name
      local id = client.id
      vim.lsp.config[name] = vim.tbl_deep_extend("force", vim.lsp.config[name] or {}, config)
      local c = vim.lsp.get_client_by_id(id)
      if c then
        c:stop()
      end
      vim.schedule(function()
        local ok = pcall(vim.lsp.start, vim.lsp.config[name])
        if ok then
          vim.notify("select_python_venv: restarted " .. name .. " LSP", vim.log.levels.INFO)
        end
      end)
      count = count + 1
    end
  end

  if count == 0 then
    local names = vim.tbl_map(function(c) return c.name end, clients)
    if #names > 0 then
      vim.notify("select_python_venv: no python LSP client active in this buffer: " .. table.concat(names, ", "), vim.log.levels.INFO)
    else
      vim.notify("select_python_venv: no LSP client active in this buffer", vim.log.levels.INFO)
    end
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
