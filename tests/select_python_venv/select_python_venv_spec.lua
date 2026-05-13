local plugin = require("select_python_venv")

describe("select_python_venv", function()
  it("get_path returns nil when no venv exists", function()
    assert.is_nil(plugin.get_path())
  end)
end)
