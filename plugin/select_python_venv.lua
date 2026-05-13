vim.api.nvim_create_user_command("SelectPythonVenv", function()
  require("select_python_venv").select_path()
end, {})

vim.api.nvim_create_user_command("SelectPythonVenvShow", function()
  require("select_python_venv").show_path()
end, {})

vim.api.nvim_create_user_command("SelectPythonVenvRestart", function()
  require("select_python_venv").restart_lsp()
end, {})

vim.api.nvim_create_user_command("SelectPythonVenvClear", function()
  require("select_python_venv").clear_venv()
end, {})
