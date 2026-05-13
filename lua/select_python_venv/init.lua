local finder = require("select_python_venv.finder")
local persist = require("select_python_venv.persist")

local M = {}

local function normalize(path)
  return path:gsub("\\", "/")
end

M.config = { auto_detect = true }

local applied_clients = {}

vim.api.nvim_create_autocmd("LspAttach", {
  desc = "Apply select_python_venv path to Python LSP clients on start",
  callback = function(args)
    if applied_clients[args.data.client_id] then
      return
    end
    applied_clients[args.data.client_id] = true

    local python_path = M.get_venv_path()
    if not python_path then
      return
    end

    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
      return
    end

    local extra
    if client.name == "pyright" then
      extra = { settings = { pyright = { pythonPath = python_path }, python = { pythonPath = python_path } } }
    elseif client.name == "basedpyright" then
      extra = { settings = { basedpyright = { pythonPath = python_path }, python = { pythonPath = python_path } } }
    elseif client.name == "ty" then
      extra = { settings = { ty = { configuration = { environment = { python = python_path } } } } }
    elseif client.name == "ruff" then
      extra = { init_options = { settings = { interpreter = { python_path } } } }
    end

    if extra then
      client.config = vim.tbl_deep_extend("force", client.config, extra)
      if client.config.settings then
        pcall(client.notify, client, "workspace/didChangeConfiguration", {
          settings = client.config.settings,
        })
      end
    end
  end,
})

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

  local server_configs = {
    pyright = { settings = { pyright = { pythonPath = python_path }, python = { pythonPath = python_path } } },
    basedpyright = { settings = { basedpyright = { pythonPath = python_path }, python = { pythonPath = python_path } } },
    ty = { settings = { ty = { configuration = { environment = { python = python_path } } } } },
    ruff = { init_options = { settings = { interpreter = { python_path } } } },
  }

  for name, config in pairs(server_configs) do
    if vim.lsp.config[name] then
      vim.lsp.config[name] = vim.tbl_deep_extend("force", vim.lsp.config[name], config)
    end
  end

  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local updated = 0
  for _, client in ipairs(clients) do
    local extra = server_configs[client.name]
    if extra then
      client.config = vim.tbl_deep_extend("force", client.config, extra)
      pcall(client.notify, client, "workspace/didChangeConfiguration", {
        settings = client.config.settings,
      })
      updated = updated + 1
      vim.notify("select_python_venv: updated " .. client.name, vim.log.levels.INFO)
    end
  end

  if updated == 0 then
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
