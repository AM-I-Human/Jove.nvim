-- output.lua
local M = {}

-- A unique namespace for our virtual text. This is good practice.
local NS_ID = vim.api.nvim_create_namespace("jove_output")

-- A simple cache to store the extmark ID for each line we've added output to.
-- This lets us easily find and clear old output before showing new output.
-- Format: line_marks[bufnr][row] = mark_id
local line_marks = {}
local line_prompt_marks = {} -- For input prompts like In[1]:

--- Clears any previous input prompt for a given buffer and line.
local function clear_previous_prompt(bufnr, row)
	if line_prompt_marks[bufnr] and line_prompt_marks[bufnr][row] then
		pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, line_prompt_marks[bufnr][row])
		line_prompt_marks[bufnr][row] = nil
	end
end

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

	clear_previous_output(bufnr, row)

	if not text_lines or #text_lines == 0 then
		return
	end

	-- For Neovim 0.7+ compatibility, use `virt_lines`.
	-- It expects a list of lines, where each line is a list of [text, hl_group] chunks.
	local virt_lines_chunks = {}
	for _, line in ipairs(text_lines) do
		-- Each line is a table of chunks. Here, each line is just one chunk.
		table.insert(virt_lines_chunks, { { line, highlight } })
	end

	-- Create a new extmark to anchor the virtual text.
	local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, row, 0, {
		virt_lines = virt_lines_chunks,
		virt_lines_above = false, -- Display below the line (default for Nvim 0.7)
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
	local exec_count = jupyter_msg.content.execution_count or 0

	if text_plain and text_plain ~= "" then
		-- Sanitize newlines and split, removing empty lines automatically.
		text_plain = text_plain:gsub("\r\n", "\n"):gsub("\r", "\n")
		local lines = vim.split(text_plain, "\n", { trimempty = true })

		if #lines > 0 then
			if exec_count then
				lines[1] = string.format("Out[%d]: %s", exec_count, lines[1])
			end
			-- Use a different highlight to distinguish results from print statements
			render_output(bufnr, row, lines, { highlight = "String" })
		end
	end
end

--- Handles 'execute_input' messages, showing the "In[n]:" prompt.
function M.render_input_prompt(bufnr, row, jupyter_msg)
	local exec_count = jupyter_msg.content.execution_count
	if not exec_count then
		return
	end

	-- It's possible we are re-running a cell. Clear any old prompt on this line.
	clear_previous_prompt(bufnr, row)

	-- Also clear any old output from a previous run on this line.
	clear_previous_output(bufnr, row)

	local prompt_text = string.format("In[%d]: ", exec_count)

	-- Use an extmark with inline virtual text to display the prompt.
	-- This requires Neovim 0.10+
	local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, row, 0, {
		virt_text = { { prompt_text, "Question" } },
		virt_text_pos = "inline",
	})

	if mark_id then
		if not line_prompt_marks[bufnr] then
			line_prompt_marks[bufnr] = {}
		end
		line_prompt_marks[bufnr][row] = mark_id
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
