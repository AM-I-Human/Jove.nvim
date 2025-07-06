-- output.lua
local M = {}

-- A unique namespace for our virtual text. This is good practice.
local NS_ID = vim.api.nvim_create_namespace("jove_output")

-- A simple cache to store the extmark ID for each line we've added output to.
-- This lets us easily find and clear old output before showing new output.
-- Format: line_marks[bufnr][row] = mark_id
local line_marks = {}

--- Clears any previous output for a given buffer and line.
-- @param bufnr (integer) The buffer number.
-- @param row (integer) The 0-indexed row number.
local function clear_previous_output(bufnr, row)
	if line_marks[bufnr] and line_marks[bufnr][row] then
		-- Safely delete the extmark using its unique ID
		pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, line_marks[bufnr][row])
		line_marks[bufnr][row] = nil
	end
end

--- The main rendering function. Displays text below a given line.
-- @param bufnr (integer) The buffer number.
-- @param row (integer) The 0-indexed row to anchor the text below.
-- @param text_lines (table) A list of strings, one for each line of output.
-- @param opts (table) Options, including the highlight group to use.
local function render_output(bufnr, row, text_lines, opts)
	opts = opts or {}
	local highlight = opts.highlight or "Comment"

	print(string.format("render_output called with bufnr=%d, row=%d", bufnr, row))

	-- Debug: check if text_lines is nil or empty
	if not text_lines then
		print("text_lines is nil")
	else
		print("text_lines contents:")
		for i, line in ipairs(text_lines) do
			print(string.format("  line %d: %s", i, line))
		end
	end

	clear_previous_output(bufnr, row)

	if not text_lines or #text_lines == 0 then
		print("No text_lines to render, returning early")
		return
	end

	local virt_text_chunks = {}
	for _, line in ipairs(text_lines) do
		table.insert(virt_text_chunks, { line, highlight })
	end

	-- Debug: print virt_text_chunks
	print("virt_text_chunks prepared:")
	for i, chunk in ipairs(virt_text_chunks) do
		print(string.format("  chunk %d: text='%s', highlight='%s'", i, chunk[1], chunk[2]))
	end

	local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, row, 0, {
		virt_text = virt_text_chunks,
		virt_text_pos = "below",
		virt_text_hide = false,
	})

	print(string.format("Set extmark with id %d at row %d", mark_id, row))

	if not line_marks[bufnr] then
		line_marks[bufnr] = {}
	end
	line_marks[bufnr][row] = mark_id
end

--- Handles 'stream' messages (e.g., from a print() statement).
function M.render_stream(bufnr, row, jupyter_msg)
	local text = jupyter_msg.content.text
	if not text or text == "" then
		return
	end

	-- Sanitize newlines and split, removing empty lines automatically.
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	local lines = vim.split(text, "\n", { trimempty = true })

	if #lines > 0 then
		render_output(bufnr, row, lines, { highlight = "Comment" })
	end
end

--- Handles 'execute_result' messages (the final return value of a cell).
function M.render_execute_result(bufnr, row, jupyter_msg)
	local text_plain = jupyter_msg.content.data["text/plain"]
	if text_plain and text_plain ~= "" then
		-- Sanitize newlines and split, removing empty lines automatically.
		text_plain = text_plain:gsub("\r\n", "\n"):gsub("\r", "\n")
		local lines = vim.split(text_plain, "\n", { trimempty = true })

		if #lines > 0 then
			-- Use a different highlight to distinguish results from print statements
			render_output(bufnr, row, lines, { highlight = "String" })
		end
	end
end

--- Handles 'error' messages from the kernel.
function M.render_error(bufnr, row, jupyter_msg)
	-- The traceback from Jupyter is already a table of strings, which is perfect!
	local traceback = jupyter_msg.content.traceback
	if traceback then
		render_output(bufnr, row, traceback, { highlight = "ErrorMsg" })
	end
end

return M
