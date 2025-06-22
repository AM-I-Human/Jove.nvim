-- output.lua
local M = {}

local output_ns = vim.api.nvim_create_namespace("am_i_neokernel_output")

local function get_cell_end_row(bufnr, cell_start_row)
	-- VERY basic cell end detection.  We'll improve this later.
	return cell_start_row + 1
end

local function clear_output(bufnr, cell_start_row)
	local cell_end_row = get_cell_end_row(bufnr, cell_start_row)
	vim.api.nvim_buf_clear_namespace(bufnr, output_ns, cell_start_row + 1, cell_end_row)
end

function M.render_stream(bufnr, row, msg)
	clear_output(bufnr, row)
	local text = msg.content.text
	vim.api.nvim_buf_set_extmark(bufnr, output_ns, row + 1, 0, {
		virt_text = { { text, "Comment" } },
		virt_text_pos = "overlay",
	})
end

function M.render_execute_result(bufnr, row, msg)
	clear_output(bufnr, row)
	local data = msg.content.data
	if data and data["text/plain"] then
		local text = data["text/plain"]
		vim.api.nvim_buf_set_extmark(bufnr, output_ns, row + 1, 0, {
			virt_text = { { text, "Comment" } },
			virt_text_pos = "overlay",
		})
	end
end

function M.render_error(bufnr, row, msg)
	clear_output(bufnr, row)
	local ename = msg.content.ename
	local evalue = msg.content.evalue
	local traceback = table.concat(msg.content.traceback, "\n")

	local error_text = string.format("%s: %s\n%s", ename, evalue, traceback)
	vim.api.nvim_buf_set_extmark(bufnr, output_ns, row + 1, 0, {
		virt_text = { { error_text, "ErrorMsg" } }, -- Use ErrorMsg highlight group
		virt_text_pos = "overlay",
	})
end

return M
