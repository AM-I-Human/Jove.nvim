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

	-- First, clear any old output that might be on this line
	clear_previous_output(bufnr, row)

	-- Don't render if there's no text
	if not text_lines or #text_lines == 0 then
		return
	end

	-- Create a new extmark to anchor the virtual text.
	-- This is the core of the rendering logic.
	local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, row, 0, {
		virt_text = text_lines, -- Pass the table of lines
		virt_text_pos = "below", -- CRITICAL: Display output *below* the code line
		virt_text_hide = false, -- Make sure the virtual text is visible
		hl_group = highlight, -- Apply the desired highlight
	})

	-- Store the new mark ID in our cache so we can clear it later
	if not line_marks[bufnr] then
		line_marks[bufnr] = {}
	end
	line_marks[bufnr][row] = mark_id
end

--- Handles 'stream' messages (e.g., from a print() statement).
function M.render_stream(bufnr, row, jupyter_msg)
	local text = jupyter_msg.content.text
	-- CRITICAL: Split the incoming text into a table of lines
	local lines = vim.split(text, "\n", { trimempty = false })

	-- Often, a print statement adds a final newline, creating an empty string
	-- at the end of the table. We usually don't want to display this empty line.
	if lines[#lines] == "" then
		table.remove(lines)
	end

	render_output(bufnr, row, lines, { highlight = "Comment" })
end

--- Handles 'execute_result' messages (the final return value of a cell).
function M.render_execute_result(bufnr, row, jupyter_msg)
	local text_plain = jupyter_msg.content.data["text/plain"]
	if text_plain then
		local lines = vim.split(text_plain, "\n", { trimempty = false })
		if lines[#lines] == "" then
			table.remove(lines)
		end
		-- Use a different highlight to distinguish results from print statements
		render_output(bufnr, row, lines, { highlight = "String" })
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
