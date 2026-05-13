local M = {}

local function is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

local function scripts_dir()
  return is_windows() and "Scripts" or "bin"
end

local function python_exe()
  return is_windows() and "python.exe" or "python"
end

function M.interpreter_path(venv_root)
  return venv_root .. "/" .. scripts_dir() .. "/" .. python_exe()
end

local function is_valid_venv(path)
  return vim.fn.filereadable(M.interpreter_path(path)) == 1
end

local function normalize(path)
  return path:gsub("\\", "/")
end

local function find_with_fd()
  if vim.fn.executable("fd") ~= 1 then
    return {}
  end

  local cmd = { "fd", "--type", "f", "--hidden", "--no-ignore", "-E", ".git", "^pyvenv\\.cfg$" }
  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local paths = {}
  for _, line in ipairs(lines) do
    line = normalize(line:gsub("\r$", ""))
    if line ~= "" then
      local parent = vim.fn.fnamemodify(line, ":h")
      if parent ~= "" and vim.fn.isdirectory(parent) == 1 then
        table.insert(paths, parent)
      end
    end
  end
  return paths
end

local function find_common()
  local cwd = vim.fn.getcwd()
  local names = { ".venv", "venv", "env", ".env", "virtualenv" }
  local paths = {}
  for _, name in ipairs(names) do
    local p = cwd .. "/" .. name
    if vim.fn.isdirectory(p) == 1 and is_valid_venv(p) then
      table.insert(paths, p)
    end
  end
  return paths
end

function M.find_venvs()
  local paths = find_with_fd()
  if #paths == 0 then
    paths = find_common()
  end
  return paths
end

return M
