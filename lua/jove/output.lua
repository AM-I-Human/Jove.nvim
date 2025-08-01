-- lua/jove/output.lua
local M = {}
local log = require("jove.log")
local term_image_adapter = require("jove.term-image.adapter")
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
local execution_outputs = {} -- Memorizza le linee di output accumulate per una data esecuzione

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

local function render_accumulated_output(bufnr)
	local output_data = execution_outputs[bufnr]
	if not output_data or not output_data.lines or #output_data.lines == 0 then
		return
	end

	local row = output_data.end_row
	local virt_lines_chunks = {}
	for _, line_info in ipairs(output_data.lines) do
		table.insert(virt_lines_chunks, { { line_info.text, line_info.highlight } })
	end

	-- Pulisce l'output composito precedente sulla riga di destinazione
	if line_marks[bufnr] and line_marks[bufnr][row] then
		pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, line_marks[bufnr][row])
		line_marks[bufnr][row] = nil
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

local function add_output_lines(bufnr, end_row, text_lines, opts)
	opts = opts or {}
	if not execution_outputs[bufnr] then
		execution_outputs[bufnr] = { end_row = end_row, lines = {} }
	end

	for _, line in ipairs(text_lines) do
		table.insert(execution_outputs[bufnr].lines, { text = line, highlight = opts.highlight or "Comment" })
	end

	render_accumulated_output(bufnr)
end

local function render_image(bufnr, start_row, end_row, jupyter_msg)
	local data = jupyter_msg.content.data
	local b64_data = data["image/png"] or data["image/jpeg"] or data["image/gif"]
	if not b64_data then
		return false
	end

	local sequence = term_image_adapter.render(b64_data)
	if not sequence then
		return false -- Il terminale non è supportato, il fallback gestirà l'output di testo.
	end

	-- Pulisce l'output virtuale precedente poiché usiamo una finestra flottante.
	clear_range(bufnr, start_row, end_row)
	if execution_outputs[bufnr] then
		execution_outputs[bufnr] = nil
	end

	-- Dimensioni e posizione della finestra (valori fissi per ora)
	local win_height = 20 -- TODO: Calcolare dalle dimensioni dell'immagine
	local win_width = 80 -- TODO: Calcolare dalle dimensioni dell'immagine
	local parent_win = vim.api.nvim_get_current_win()
	local win_opts = {
		relative = "win",
		win = parent_win,
		width = win_width,
		height = win_height,
		row = vim.fn.winline() - 1, -- Relativo alla riga corrente nella finestra
		col = vim.fn.wincol() + 3, -- Leggermente a destra del cursore
		style = "minimal",
		border = "rounded",
	}

	-- Crea una finestra flottante con un terminale
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Avvia un terminale e invia la sequenza di escape
	vim.api.nvim_set_current_win(win)
	vim.cmd("terminal")
	local job_id = vim.b.terminal_job_id
	vim.api.nvim_chan_send(job_id, sequence)

	-- Torna alla finestra originale
	vim.api.nvim_set_current_win(parent_win)

	-- Aggiungi una mappatura per chiudere la finestra dell'immagine
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })

	return true
end

local function add_text_plain_output(bufnr, end_row, jupyter_msg, with_prompt)
	local text_plain = jupyter_msg.content.data["text/plain"]
	if not (text_plain and text_plain ~= "") then
		return
	end

	local exec_count = jupyter_msg.content.execution_count
	local cleaned_text = clean_string(text_plain)
	local lines = vim.split(cleaned_text:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { trimempty = true })
	if #lines > 0 then
		if with_prompt and exec_count then
			lines[1] = string.format("Out[%d]: %s", exec_count, lines[1])
		end
		add_output_lines(bufnr, end_row, lines, { highlight = "String" })
	end
end

function M.render_stream(bufnr, start_row, end_row, jupyter_msg)
	local text = jupyter_msg.content.text
	if not text or text == "" then
		return
	end
	local cleaned_text = clean_string(text)
	local lines = vim.split(cleaned_text:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { trimempty = true })
	if #lines > 0 then
		add_output_lines(bufnr, end_row, lines, { highlight = "Comment" })
	end
end

function M.render_execute_result(bufnr, start_row, end_row, jupyter_msg)
	if render_image(bufnr, start_row, end_row, jupyter_msg) then
		return
	end
	add_text_plain_output(bufnr, end_row, jupyter_msg, true) -- with prompt
end

function M.render_input_prompt(bufnr, start_row, end_row, jupyter_msg)
	local exec_count = jupyter_msg.content.execution_count
	if not exec_count then
		return
	end

	-- Clear all previous marks (prompts and outputs) in the execution range.
	clear_range(bufnr, start_row, end_row)
	-- Azzera l'accumulatore di output per la nuova esecuzione
	execution_outputs[bufnr] = nil

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
		add_output_lines(bufnr, end_row, cleaned_traceback, { highlight = "ErrorMsg" })
	end
end

function M.render_display_data(bufnr, start_row, end_row, jupyter_msg)
	-- Tenta di renderizzare l'immagine. Se ha successo, termina.
	if render_image(bufnr, start_row, end_row, jupyter_msg) then
		return
	end

	-- Altrimenti, esegui il fallback al rendering del testo semplice.
	add_text_plain_output(bufnr, end_row, jupyter_msg, false) -- without prompt
end

--- NUOVO ---
--- Mostra la risposta di una inspect_request in una finestra flottante.
function M.render_inspect_reply(jupyter_msg)
	if jupyter_msg.content.status ~= "ok" or not jupyter_msg.content.found then
		log.add(vim.log.levels.INFO, "Oggetto non trovato.")
		return
	end

	local docstring = jupyter_msg.content.data["text/plain"]
	if not docstring or docstring == "" then
		log.add(vim.log.levels.INFO, "Nessuna documentazione disponibile per questo oggetto.")
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

--- Mostra la risposta di una history_request in un nuovo buffer.
function M.render_history_reply(jupyter_msg)
	if jupyter_msg.content.status ~= "ok" then
		log.add(vim.log.levels.ERROR, "Impossibile recuperare la cronologia.")
		return
	end

	local history = jupyter_msg.content.history
	if not history or #history == 0 then
		log.add(vim.log.levels.INFO, "Nessuna cronologia trovata per questa sessione.")
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
	display_data = M.render_display_data, -- Gestisce immagini o testo
	error = M.render_error,
	execute_input = M.render_input_prompt,
}

return M
