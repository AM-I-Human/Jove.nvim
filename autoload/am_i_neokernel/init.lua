-- init.lua
local kernel = require("jupytex.kernel")

vim.api.nvim_create_user_command("JupyterStart", function(opts)
	kernel.start(opts.args)
end, { nargs = 1, desc = "Start a Jupyter kernel" })

vim.api.nvim_create_user_command("JupyterExecute", function()
	local bufnr = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
	local cell_content = lines[1]
	kernel.execute_cell("python3", cell_content) --  "python3" for now
end, { desc = "Execute the current cell" })

-- Example configuration (you can move this to a separate config file later)
vim.g.jupytex_kernels = {
	python3 = {
		cmd = "python3 -m ipykernel_launcher -f {connection_file}",
	},
}
