local M = {}

local function normalize(path)
  return path:gsub("\\", "/")
end

local function data_dir()
  return vim.fn.stdpath("data") .. "/select_python_venv"
end

local function data_file()
  return data_dir() .. "/data.json"
end

function M.ensure()
  if vim.fn.isdirectory(data_dir()) == 0 then
    vim.fn.mkdir(data_dir(), "p")
  end
end

function M.load()
  M.ensure()
  local file = data_file()
  if vim.fn.filereadable(file) == 0 then
    return {}
  end
  local ok, data = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(file), "\n"))
  if ok and type(data) == "table" then
    return data
  end
  return {}
end

function M.save(data)
  M.ensure()
  vim.fn.writefile({ vim.fn.json_encode(data) }, data_file())
end

function M.get_stored(project)
  return M.load()[normalize(project)]
end

function M.set_stored(project, path)
  local data = M.load()
  data[normalize(project)] = normalize(path)
  M.save(data)
end

return M
