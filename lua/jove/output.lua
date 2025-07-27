-- lua/jove/output.lua
local M = {}

--- Pulisce una stringa dai codici di escape ANSI e da altri caratteri non stampabili.
-- @param str La stringa da pulire.
-- @return La stringa pulita.
local function clean_string(str)
	if not str then
		return ""
	end
	-- Rimuove i codici di colore/stile ANSI (es. ^[[31m)
	local cleaned = string.gsub(str, "\x1b%[[%d;]*m", "")
	-- Rimuove i caratteri nulli (^@) che a volte vengono inseriti
	cleaned = string.gsub(cleaned, "\0", "")
	return cleaned
end

local NS_ID = vim.api.nvim_create_namespace("jove_output")
local line_marks = {}
local line_prompt_marks = {}

local function clear_range(bufnr, start_row, end_row)
	-- Clear all extmarks (prompts and outputs) in the given range.
	-- `end_row + 1` is because the range is exclusive for the end line.
	vim.api.nvim_buf_clear_namespace(bufnr, NS_ID, start_row, end_row + 1)
	for row = start_row, end_row do
		if line_marks[bufnr] then
			line_marks[bufnr][row] = nil
		end
		if line_prompt_marks[bufnr] then
			line_prompt_marks[bufnr][row] = nil
		end
	end
end

local function render_output(bufnr, row, text_lines, opts)
	opts = opts or {}
	local highlight = opts.highlight or "Comment"
	-- Clear previous output on the target line
	if line_marks[bufnr] and line_marks[bufnr][row] then
		pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, line_marks[bufnr][row])
		line_marks[bufnr][row] = nil
	end
	if not text_lines or #text_lines == 0 then
		return
	end
	local virt_lines_chunks = {}
	for _, line in ipairs(text_lines) do
		table.insert(virt_lines_chunks, { { line, highlight } })
	end
	local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, row, -1, {
		virt_lines = virt_lines_chunks,
		virt_lines_above = false,
	})
	if not line_marks[bufnr] then
		line_marks[bufnr] = {}
	end
	line_marks[bufnr][row] = mark_id
end

function M.render_stream(bufnr, start_row, end_row, jupyter_msg)
	local text = jupyter_msg.content.text
	if not text or text == "" then
		return
	end
	local cleaned_text = clean_string(text)
	local lines = vim.split(cleaned_text:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { trimempty = true })
	if #lines > 0 then
		render_output(bufnr, end_row, lines, { highlight = "Comment" })
	end
end

function M.render_execute_result(bufnr, start_row, end_row, jupyter_msg)
	local text_plain = jupyter_msg.content.data["text/plain"]
	local exec_count = jupyter_msg.content.execution_count
	if text_plain and text_plain ~= "" then
		local cleaned_text = clean_string(text_plain)
		local lines = vim.split(cleaned_text:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { trimempty = true })
		if #lines > 0 then
			if exec_count then
				lines[1] = string.format("Out[%d]: %s", exec_count, lines[1])
			end
			render_output(bufnr, end_row, lines, { highlight = "String" })
		end
	end
end

function M.render_input_prompt(bufnr, start_row, end_row, jupyter_msg)
	local exec_count = jupyter_msg.content.execution_count
	if not exec_count then
		return
	end

	-- Clear all previous marks (prompts and outputs) in the execution range.
	clear_range(bufnr, start_row, end_row)

	if not line_prompt_marks[bufnr] then
		line_prompt_marks[bufnr] = {}
	end

	if start_row == end_row then -- Single-line execution
		local prompt_text = string.format("In[%d]: ", exec_count)
		local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, start_row, 0, {
			virt_text = { { prompt_text, "Question" } },
			virt_text_pos = "inline",
			right_gravity = false,
		})
		line_prompt_marks[bufnr][start_row] = mark_id
	else -- Multi-line execution
		local prompt_text = string.format("In[%d]:", exec_count)
		local bracket_char = " ┃" -- space before for padding
		local prompt_width = vim.fn.strwidth(prompt_text)
		local padding = string.rep(" ", prompt_width)

		-- First line: Prompt + Bracket
		line_prompt_marks[bufnr][start_row] = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, start_row, 0, {
			virt_text = { { prompt_text, "Question" }, { bracket_char, "Question" } },
			virt_text_pos = "inline",
			right_gravity = false,
		})

		-- Subsequent lines: Padding + Bracket
		for i = start_row + 1, end_row do
			line_prompt_marks[bufnr][i] = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, i, 0, {
				virt_text = { { padding, "Question" }, { bracket_char, "Question" } },
				virt_text_pos = "inline",
				right_gravity = false,
			})
		end
	end
end

function M.render_error(bufnr, start_row, end_row, jupyter_msg)
	local traceback = jupyter_msg.content.traceback
	if traceback then
		local cleaned_traceback = {}
		for _, line in ipairs(traceback) do
			table.insert(cleaned_traceback, clean_string(line))
		end
		render_output(bufnr, end_row, cleaned_traceback, { highlight = "ErrorMsg" })
	end
end

--- NUOVO ---
--- Mostra la risposta di una inspect_request in una finestra flottante.
function M.render_inspect_reply(jupyter_msg)
	if jupyter_msg.content.status ~= "ok" or not jupyter_msg.content.found then
		vim.notify("Oggetto non trovato.", vim.log.levels.INFO)
		return
	end

	local docstring = jupyter_msg.content.data["text/plain"]
	if not docstring or docstring == "" then
		vim.notify("Nessuna documentazione disponibile per questo oggetto.", vim.log.levels.INFO)
		return
	end

	local cleaned_docstring = clean_string(docstring)
	local lines = vim.split(cleaned_docstring, "\n")

	-- Crea un buffer temporaneo per la finestra flottante
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = "markdown" -- MODIFICATO: API non deprecata
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Calcola le dimensioni della finestra
	local width = math.floor(vim.o.columns * 0.6)
	local height = math.floor(vim.o.lines * 0.6)

	-- Apri la finestra flottante
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
	})
end

--- NUOVO ---
--- Mostra la risposta di una history_request in un nuovo buffer.
function M.render_history_reply(jupyter_msg)
	if jupyter_msg.content.status ~= "ok" then
		vim.notify("Impossibile recuperare la cronologia.", vim.log.levels.ERROR)
		return
	end

	local history = jupyter_msg.content.history
	if not history or #history == 0 then
		vim.notify("Nessuna cronologia trovata per questa sessione.", vim.log.levels.INFO)
		return
	end

	local lines = {}
	for _, entry in ipairs(history) do
		-- entry è una tabella: {session, line_number, source}
		table.insert(lines, string.format("-- In[%d]", entry[2]))
		table.insert(lines, entry[3])
		table.insert(lines, "") -- Riga vuota per separare
	end

	-- Apri un nuovo buffer e mostra la cronologia
	vim.cmd("enew")
	local bufnr = vim.api.nvim_get_current_buf()
	-- MODIFICATO: Usa la sintassi vim.bo per le opzioni del buffer
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].swapfile = false
	vim.api.nvim_buf_set_name(bufnr, "JoveHistory")
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].filetype = "python" -- o il filetype del kernel
end

-- Mappa per i gestori dei messaggi iopub
M.iopub_handlers = {
	stream = M.render_stream,
	execute_result = M.render_execute_result,
	display_data = M.render_execute_result, -- Tratta display_data come execute_result
	error = M.render_error,
	execute_input = M.render_input_prompt,
}

return M
