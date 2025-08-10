-- lua/jove/output.lua
local M = {}
local log = require("jove.log")
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

-- Struttura per memorizzare gli extmarks per ogni cella
-- La chiave è l'ID del primo extmark (start_mark_id)
local cell_marks = {} -- { [cell_id] = { bufnr, start_mark, end_mark, output_marks = {} } }

--- Crea i marcatori di inizio e fine per una nuova cella.
function M.create_cell_markers(bufnr, start_row, end_row)
	local start_mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, start_row, 0, { right_gravity = false })
	local end_mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, end_row, -1, { right_gravity = true })

	cell_marks[start_mark_id] = {
		bufnr = bufnr,
		start_mark = start_mark_id,
		end_mark = end_mark_id,
		output_marks = {},
		accumulated_lines = {},
	}
	return start_mark_id -- Usiamo l'ID del marcatore di inizio come ID della cella
end

local function clear_cell_output(cell_id)
	local cell_info = cell_marks[cell_id]
	if not cell_info then
		return
	end
	for _, mark_id in ipairs(cell_info.output_marks) do
		pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, mark_id)
	end
	cell_info.output_marks = {}
	cell_info.accumulated_lines = {}
end

--- Renderizza un'immagine o altro output che occupa una singola linea virtuale.
local function render_single_line_output(cell_id, sequence_text)
	local cell_info = cell_marks[cell_id]
	if not cell_info then
		return
	end
	clear_cell_output(cell_id)

	local pos = vim.api.nvim_buf_get_extmark_by_id(cell_info.bufnr, NS_ID, cell_info.end_mark, {})
	if not pos or #pos == 0 then
		return
	end -- Marcatore potrebbe essere stato cancellato
	local end_row = pos[1]
	local virt_lines = { { { sequence_text, "Normal" } } }

	local mark_id = vim.api.nvim_buf_set_extmark(cell_info.bufnr, NS_ID, end_row, -1, {
		virt_lines = virt_lines,
		virt_lines_above = false,
	})
	table.insert(cell_info.output_marks, mark_id)
end

--- Renderizza un'immagine usando il protocollo iTerm2 (IIP) come testo virtuale.
function M.render_iip_image(cell_id, b64_data)
	local term_image_adapter = require("jove.term-image.adapter")
	local sequence = term_image_adapter.render(b64_data, {})
	if not sequence or sequence == "" then
		log.add(vim.log.levels.WARN, "[Jove] Il terminale potrebbe non supportare le immagini o l'adattatore ha fallito.")
		return
	end
	render_single_line_output(cell_id, sequence)
end

--- Renderizza una stringa Sixel come testo virtuale.
function M.render_sixel_image(cell_id, sixel_string)
	if not sixel_string or sixel_string == "" then
		log.add(vim.log.levels.WARN, "[Jove] Ricevuta stringa Sixel vuota.")
		return
	end
	render_single_line_output(cell_id, sixel_string)
end

local function add_output_lines(cell_id, lines_of_chunks)
	local cell_info = cell_marks[cell_id]
	if not cell_info then
		return
	end

	-- Cancella i vecchi output di testo accumulato
	for _, mark_id in ipairs(cell_info.output_marks) do
		pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, mark_id)
	end
	cell_info.output_marks = {}

	for _, line_chunks in ipairs(lines_of_chunks) do
		table.insert(cell_info.accumulated_lines, line_chunks)
	end

	local pos = vim.api.nvim_buf_get_extmark_by_id(cell_info.bufnr, NS_ID, cell_info.end_mark, {})
	if not pos or #pos == 0 then
		return
	end
	local end_row = pos[1]

	local mark_id = vim.api.nvim_buf_set_extmark(cell_info.bufnr, NS_ID, end_row, -1, {
		virt_lines = cell_info.accumulated_lines,
		virt_lines_above = false,
	})
	table.insert(cell_info.output_marks, mark_id)
end

local function add_text_plain_output(cell_id, jupyter_msg, with_prompt)
	if not jupyter_msg or not jupyter_msg.content or not jupyter_msg.content.data then
		return
	end
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
		local lines_of_chunks = {}
		for _, line in ipairs(lines) do
			table.insert(lines_of_chunks, { { line, "String" } })
		end
		add_output_lines(cell_id, lines_of_chunks)
	end
end

function M.render_stream(cell_id, jupyter_msg)
	if not jupyter_msg or not jupyter_msg.content then
		return
	end
	local text = jupyter_msg.content.text
	if not text or text == "" then
		return
	end
	local cleaned_text = clean_string(text)
	local lines = vim.split(cleaned_text:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { trimempty = true })
	if #lines > 0 then
		local lines_of_chunks = {}
		for _, line in ipairs(lines) do
			table.insert(lines_of_chunks, { { line, "Comment" } })
		end
		add_output_lines(cell_id, lines_of_chunks)
	end
end

function M.render_execute_result(cell_id, jupyter_msg)
	-- La gestione delle immagini è ora fatta in Python e invia un messaggio separato.
	-- Questa funzione gestisce solo il fallback testuale.
	add_text_plain_output(cell_id, jupyter_msg, true) -- with prompt
end

function M.render_input_prompt(cell_id, jupyter_msg)
	local exec_count = jupyter_msg.content.execution_count
	local cell_info = cell_marks[cell_id]
	if not exec_count or not cell_info then
		return
	end

	clear_cell_output(cell_id)

	local pos_start = vim.api.nvim_buf_get_extmark_by_id(cell_info.bufnr, NS_ID, cell_info.start_mark, {})
	local pos_end = vim.api.nvim_buf_get_extmark_by_id(cell_info.bufnr, NS_ID, cell_info.end_mark, {})

	if not pos_start or #pos_start == 0 or not pos_end or #pos_end == 0 then
		return
	end

	local start_row = pos_start[1]
	local end_row = pos_end[1]

	if start_row == end_row then -- Single-line execution
		local prompt_text = string.format("In[%d]: ", exec_count)
		local mark_id = vim.api.nvim_buf_set_extmark(cell_info.bufnr, NS_ID, start_row, 0, {
			virt_text = { { prompt_text, "Question" } },
			virt_text_pos = "inline",
			right_gravity = false,
		})
		table.insert(cell_info.output_marks, mark_id)
	else -- Multi-line execution
		local prompt_text = string.format("In[%d]:", exec_count)
		local bracket_char = " ┃" -- space before for padding
		local prompt_width = vim.fn.strwidth(prompt_text)
		local padding = string.rep(" ", prompt_width)

		-- First line: Prompt + Bracket
		local first_line_mark = vim.api.nvim_buf_set_extmark(cell_info.bufnr, NS_ID, start_row, 0, {
			virt_text = { { prompt_text, "Question" }, { bracket_char, "Question" } },
			virt_text_pos = "inline",
			right_gravity = false,
		})
		table.insert(cell_info.output_marks, first_line_mark)

		-- Subsequent lines: Padding + Bracket
		for i = start_row + 1, end_row do
			local line_mark = vim.api.nvim_buf_set_extmark(cell_info.bufnr, NS_ID, i, 0, {
				virt_text = { { padding, "Question" }, { bracket_char, "Question" } },
				virt_text_pos = "inline",
				right_gravity = false,
			})
			table.insert(cell_info.output_marks, line_mark)
		end
	end
end

function M.render_error(cell_id, jupyter_msg)
	local traceback = jupyter_msg.content.traceback
	if traceback then
		local cleaned_traceback = {}
		for _, line in ipairs(traceback) do
			table.insert(cleaned_traceback, clean_string(line))
		end

		local lines_of_chunks = {}
		for _, line in ipairs(cleaned_traceback) do
			table.insert(lines_of_chunks, { { line, "ErrorMsg" } })
		end
		add_output_lines(cell_id, lines_of_chunks)
	end
end

function M.render_display_data(cell_id, jupyter_msg)
	-- La gestione delle immagini è ora fatta in Python e invia un messaggio separato.
	-- Questa funzione gestisce solo il fallback testuale.
	add_text_plain_output(cell_id, jupyter_msg, false) -- without prompt
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
