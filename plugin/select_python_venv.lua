vim.api.nvim_create_user_command("SelectPythonVenv", function()
  require("select_python_venv").select_path()
end, {})
