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
		output_marks = {}, -- Marcatori extmark visuali
		prompt_marks = {},
		outputs = {}, -- Struttura dati per gli output
	}
	return start_mark_id -- Usiamo l'ID del marcatore di inizio come ID della cella
end

--- Pulisce solo i marcatori visuali (extmarks) di una cella, ma non i dati.
local function clear_cell_display(cell_info)
	for _, mark_id in ipairs(cell_info.output_marks) do
		pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, mark_id)
	end
	cell_info.output_marks = {}
end

--- Ridisegna tutti gli output di una cella basandosi sulla sua struttura dati `outputs`.
local function redisplay_cell_outputs(cell_id)
	local cell_info = cell_marks[cell_id]
	if not cell_info then
		return
	end
	clear_cell_display(cell_info)

	local virt_lines = {}
	for _, output in ipairs(cell_info.outputs) do
		if output.type == "stream" then
			for _, line_chunks in ipairs(output.content) do
				table.insert(virt_lines, line_chunks)
			end
		elseif output.type == "execute_result" or output.type == "display_data" then
			for _, line_chunks in ipairs(output.content) do
				table.insert(virt_lines, line_chunks)
			end
		elseif output.type == "error" then
			for _, line_chunks in ipairs(output.content) do
				table.insert(virt_lines, line_chunks)
			end
		elseif output.type == "image_iip" or output.type == "image_sixel" then
			table.insert(virt_lines, { { output.content, "Normal" } })
		end
	end

	if #virt_lines == 0 then
		return
	end

	local pos = vim.api.nvim_buf_get_extmark_by_id(cell_info.bufnr, NS_ID, cell_info.end_mark, {})
	if not pos or #pos == 0 then
		return
	end
	local end_row = pos[1]

	local mark_id = vim.api.nvim_buf_set_extmark(cell_info.bufnr, NS_ID, end_row, -1, {
		virt_lines = virt_lines,
		virt_lines_above = false,
	})
	table.insert(cell_info.output_marks, mark_id)
end

--- Aggiunge un nuovo output alla struttura dati di una cella e la ridisegna.
local function add_output_to_cell(cell_id, output_data)
	local cell_info = cell_marks[cell_id]
	if not cell_info then
		return
	end
	table.insert(cell_info.outputs, output_data)
	redisplay_cell_outputs(cell_id)
end

--- Renderizza un'immagine usando il protocollo iTerm2 (IIP) come testo virtuale.
function M.render_iip_image(cell_id, b64_data)
	local term_image_adapter = require("jove.term-image.adapter")
	local sequence = term_image_adapter.render(b64_data, {})
	if not sequence or sequence == "" then
		log.add(vim.log.levels.WARN, "[Jove] Il terminale potrebbe non supportare le immagini o l'adattatore ha fallito.")
		return
	end
	add_output_to_cell(cell_id, { type = "image_iip", content = sequence, b64 = b64_data })
end

--- Renderizza una stringa Sixel come testo virtuale.
function M.render_sixel_image(cell_id, sixel_string)
	if not sixel_string or sixel_string == "" then
		log.add(vim.log.levels.WARN, "[Jove] Ricevuta stringa Sixel vuota.")
		return
	end
	add_output_to_cell(cell_id, { type = "image_sixel", content = sixel_string })
end

local function add_text_plain_output(cell_id, jupyter_msg, with_prompt, output_type, highlight_group)
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
			table.insert(lines_of_chunks, { { line, highlight_group } })
		end
		add_output_to_cell(cell_id, { type = output_type, content = lines_of_chunks })
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
		add_output_to_cell(cell_id, { type = "stream", content = lines_of_chunks })
	end
end

function M.render_execute_result(cell_id, jupyter_msg)
	-- La gestione delle immagini è ora fatta in Python e invia un messaggio separato.
	-- Questa funzione gestisce solo il fallback testuale.
	add_text_plain_output(cell_id, jupyter_msg, true, "execute_result", "String") -- with prompt
end

function M.render_input_prompt(cell_id, jupyter_msg)
	local exec_count = jupyter_msg.content.execution_count
	local cell_info = cell_marks[cell_id]
	if not exec_count or not cell_info then
		return
	end

	-- Pulisce tutti i marcatori visivi (output e prompt) per questa cella
	clear_cell_display(cell_info) -- Pulisce l'output precedente
	cell_info.outputs = {} -- Cancella i dati dell'output precedente
	for _, mark_id in ipairs(cell_info.prompt_marks) do
		pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, mark_id)
	end
	cell_info.prompt_marks = {}

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
		table.insert(cell_info.prompt_marks, mark_id)
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
		table.insert(cell_info.prompt_marks, first_line_mark)

		-- Subsequent lines: Padding + Bracket
		for i = start_row + 1, end_row do
			local line_mark = vim.api.nvim_buf_set_extmark(cell_info.bufnr, NS_ID, i, 0, {
				virt_text = { { padding, "Question" }, { bracket_char, "Question" } },
				virt_text_pos = "inline",
				right_gravity = false,
			})
			table.insert(cell_info.prompt_marks, line_mark)
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
			-- Una riga di traceback può contenere newline, quindi la splittiamo
			local sub_lines = vim.split(line:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n")
			for _, sub_line in ipairs(sub_lines) do
				table.insert(lines_of_chunks, { { sub_line, "ErrorMsg" } })
			end
		end
		add_output_to_cell(cell_id, { type = "error", content = lines_of_chunks })
	end
end

function M.render_display_data(cell_id, jupyter_msg)
	-- La gestione delle immagini è ora fatta in Python e invia un messaggio separato.
	-- Questa funzione gestisce solo il fallback testuale.
	add_text_plain_output(cell_id, jupyter_msg, false, "display_data", "String") -- without prompt
end

--- Pulisce l'output (testo virtuale e prompt) per le celle che si sovrappongono a un dato range.
-- @param bufnr (integer) Il numero del buffer.
-- @param start_row (integer) La riga di inizio (0-indexed).
-- @param end_row (integer) La riga di fine (0-indexed).
function M.clear_output_in_range(bufnr, start_row, end_row)
	local cells_to_clear = {}
	for cell_id, cell_info in pairs(cell_marks) do
		if cell_info.bufnr == bufnr then
			local pos_start = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.start_mark, {})
			local pos_end = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.end_mark, {})

			if pos_start and #pos_start > 0 and pos_end and #pos_end > 0 then
				local cell_start_row = pos_start[1]
				local cell_end_row = pos_end[1]

				-- Controlla se il range della cella si sovrappone al range specificato
				if math.max(cell_start_row, start_row) <= math.min(cell_end_row, end_row) then
					table.insert(cells_to_clear, cell_id)
				end
			end
		end
	end

	if #cells_to_clear == 0 then
		log.add(vim.log.levels.INFO, "Nessuna cella Jove con output trovata nel range specificato.")
		return
	end

	for _, cell_id in ipairs(cells_to_clear) do
		local cell_info = cell_marks[cell_id]
		if cell_info then
			-- Pulisce i marcatori di output
			clear_cell_display(cell_info)
			cell_info.outputs = {}
			-- Pulisce i marcatori di prompt
			for _, mark_id in ipairs(cell_info.prompt_marks) do
				pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, mark_id)
			end
			cell_info.prompt_marks = {}
		end
	end

	log.add(vim.log.levels.INFO, "Pulito l'output per " .. #cells_to_clear .. " cella/e.")
end

--- Trova e pulisce le celle esistenti contenute nel range specificato.
function M.find_and_clear_cell_at_range(bufnr, start_row, end_row)
	local cells_to_remove = {}
	for cell_id, cell_info in pairs(cell_marks) do
		if cell_info.bufnr == bufnr then
			local pos_start = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.start_mark, {})
			local pos_end = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.end_mark, {})

			if pos_start and #pos_start > 0 and pos_end and #pos_end > 0 then
				local cell_start_row = pos_start[1]
				local cell_end_row = pos_end[1]

				-- Controlla se il range della cella è contenuto nel nuovo range di esecuzione
				if cell_start_row >= start_row and cell_end_row <= end_row then
					-- Pulisce i marcatori visuali (output/prompt) dal buffer
					for _, mark_id in ipairs(cell_info.output_marks) do
						pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, mark_id)
					end
					for _, mark_id in ipairs(cell_info.prompt_marks) do
						pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, mark_id)
					end
					-- Rimuove i marcatori invisibili di inizio e fine
					pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, cell_info.start_mark)
					pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, cell_info.end_mark)

					-- Raccoglie l'ID della cella da rimuovere
					table.insert(cells_to_remove, cell_id)
				end
			end
		end
	end

	-- Rimuove tutte le celle identificate dalla tabella di tracciamento
	for _, cell_id in ipairs(cells_to_remove) do
		cell_marks[cell_id] = nil
	end
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
		local source_lines = vim.split(entry[3], "\n")
		for _, line in ipairs(source_lines) do
			table.insert(lines, line)
		end
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

--- Mostra l'output di una cella in una finestra flottante per la selezione.
function M.show_selectable_output(bufnr, cursor_row)
	local target_cell_id
	-- Trova la cella in cui si trova il cursore o la cella il cui output è più vicino
	local best_candidate = { id = nil, distance = math.huge }

	for cell_id, cell_info in pairs(cell_marks) do
		if cell_info.bufnr == bufnr then
			local pos_start = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.start_mark, {})
			if pos_start and #pos_start > 0 then
				local cell_start_row = pos_start[1]
				-- Se il cursore è all'interno del range del codice sorgente della cella
				local pos_end = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.end_mark, {})
				if pos_end and #pos_end > 0 and cursor_row >= cell_start_row and cursor_row <= pos_end[1] then
					best_candidate = { id = cell_id, distance = 0 }
					break -- Trovata corrispondenza esatta
				end
				-- Altrimenti, calcola la distanza e tienila come candidata
				local distance = math.abs(cursor_row - cell_start_row)
				if distance < best_candidate.distance then
					best_candidate = { id = cell_id, distance = distance }
				end
			end
		end
	end
	target_cell_id = best_candidate.id

	if not target_cell_id then
		log.add(vim.log.levels.INFO, "Nessuna cella Jove trovata vicino alla posizione del cursore.")
		return
	end

	local cell_info = cell_marks[target_cell_id]
	if not cell_info or not cell_info.outputs or #cell_info.outputs == 0 then
		log.add(vim.log.levels.INFO, "La cella Jove trovata non ha output.")
		return
	end

	-- Estrae il contenuto testuale da tutti gli output della cella
	local lines = {}
	for _, output in ipairs(cell_info.outputs) do
		if output.type == "stream" or output.type == "execute_result" or output.type == "display_data" or output.type == "error" then
			for _, line_chunks in ipairs(output.content) do
				local line_text = ""
				for _, chunk in ipairs(line_chunks) do
					line_text = line_text .. chunk[1]
				end
				table.insert(lines, line_text)
			end
		elseif output.type == "image_iip" then
			table.insert(lines, "[Immagine: IIP]")
		elseif output.type == "image_sixel" then
			table.insert(lines, "[Immagine: Sixel]")
		end
	end

	if #lines == 0 then
		log.add(vim.log.levels.INFO, "La cella Jove trovata non ha output di testo da selezionare.")
		return
	end

	-- Crea e mostra la finestra flottante
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width = math.floor(vim.o.columns * 0.7)
	local height = math.min(#lines, math.floor(vim.o.lines * 0.5))

	vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		width = width,
		height = height,
		row = 1,
		col = 0,
		style = "minimal",
		border = "rounded",
		title = "Jove Output (press 'q' to close)",
		title_pos = "center",
	})
	-- Mappa 'q' per chiudere
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", { noremap = true, silent = true })
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
