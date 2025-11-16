-- lua/jove/output.lua
-- Modulo di rendering per gli output delle celle. È stateless.
local M = {}
local log = require("jove.log")
local state = require("jove.state")
local ansi = require("jove.ansi")

-- Fallback in puro Lua per la decodifica base64.
local function lua_b64_decode(data)
	log.add(vim.log.levels.WARN, "[Jove] Funzione nativa 'base64decode' fallita o non trovata. Uso il fallback in Lua.")
	local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
	data = string.gsub(data, "[^" .. b64 .. "]", "")
	local out = {}
	for i = 1, #data, 4 do
		local c1, c2, c3, c4 = string.sub(data, i, i + 3):byte(1, 4)
		c1 = b64:find(string.char(c1), 1, true) - 1
		c2 = b64:find(string.char(c2), 1, true) - 1
		table.insert(out, string.char(bit.bor(bit.lshift(c1, 2), bit.rshift(c2, 4))))
		c3 = b64:find(string.char(c3), 1, true)
		if c3 then
			c3 = c3 - 1
			table.insert(out, string.char(bit.bor(bit.lshift(bit.band(c2, 0x0F), 4), bit.rshift(c3, 2))))
			c4 = b64:find(string.char(c4), 1, true)
			if c4 then
				c4 = c4 - 1
				table.insert(out, string.char(bit.bor(bit.lshift(bit.band(c3, 0x03), 6), c4)))
			end
		end
	end
	return table.concat(out)
end

--- Tenta di usare la funzione nativa di Neovim, altrimenti usa il fallback.
local function b64_decode(b64_data)
	local ok, decoded = pcall(vim.fn.base64decode, b64_data)
	if ok and decoded then
		return decoded
	end
	return lua_b64_decode(b64_data)
end

--- NUOVO: Gestisce il rendering di un'immagine inline.
-- Se l'immagine viene processata, restituisce true. Altrimenti, false.
local function process_inline_image(cell_id, jupyter_msg, is_update)
	local content = jupyter_msg.content
	if not content or not content.data or not content.data["image/png"] then
		return false
	end

	local cell_info = state.get_cell(cell_id)
	if not cell_info then
		return true
	end

	local b64_data = content.data["image/png"]

	local NS_ID = state.get_namespace_id()
	local pos = vim.api.nvim_buf_get_extmark_by_id(cell_info.bufnr, NS_ID, cell_info.end_mark, {})
	if not pos or #pos == 0 then
		return true
	end
	local end_row = pos[1]

	if cell_info.image_output_info then
		require("jove.image_renderer").clear_image_area(cell_info.image_output_info)
		cell_info.image_output_info = nil
	end

	-- Chiama direttamente il renderer con i dati base64
	require("jove.image_renderer").render_image_from_b64(cell_info.bufnr, end_row, b64_data, cell_id)

	-- Salva il placeholder
	local display_id = (content.transient and content.transient.display_id) or nil
	local output_content = { { "[Immagine inline renderizzata nel terminale]", "Comment" } }
	local output_type = "image_inline"

	if is_update and display_id then
		local updated = false
		for i, output in ipairs(cell_info.outputs) do
			if output.display_id == display_id then
				cell_info.outputs[i].content = output_content
				cell_info.outputs[i].type = output_type
				updated = true
				break
			end
		end
		if not updated then
			state.add_output_to_cell(cell_id, {
				type = output_type,
				content = output_content,
				display_id = display_id,
			})
		end
	else
		state.add_output_to_cell(cell_id, {
			type = output_type,
			content = output_content,
			display_id = display_id,
		})
	end
	M.redraw_cell(cell_id)
	return true
end

--- NUOVO: Gestisce il rendering di un'immagine in un popup.
-- Se l'immagine viene processata, restituisce true. Altrimenti, false.
local function process_popup_image(cell_id, jupyter_msg, is_update)
	local content = jupyter_msg.content
	if not content or not content.data or not content.data["image/png"] then
		return false -- Non è un messaggio con immagine
	end

	local b64_data = content.data["image/png"]
	if not b64_data or b64_data == "" then
		log.add(vim.log.levels.ERROR, "Dati immagine base64 vuoti.")
		return false
	end

	require("jove.image_renderer").render_image_popup_from_b64(b64_data)

	local display_id = (content.transient and content.transient.display_id) or nil
	local output_content = { { "[Immagine visualizzata in popup]", "Comment" } }
	local output_type = "image_popup"
	local cell_info = state.get_cell(cell_id)
	if not cell_info then
		return true
	end

	if is_update and display_id then
		local updated = false
		for i, output in ipairs(cell_info.outputs) do
			if output.display_id == display_id then
				cell_info.outputs[i].content = output_content
				cell_info.outputs[i].type = output_type
				updated = true
				break
			end
		end
		if not updated then -- Primo messaggio per questo display_id
			state.add_output_to_cell(cell_id, {
				type = output_type,
				content = output_content,
				display_id = display_id,
			})
		end
		M.redraw_cell(cell_id)
	else
		-- Aggiunge come nuovo output
		state.add_output_to_cell(cell_id, {
			type = output_type,
			content = output_content,
			display_id = display_id,
		})
		M.redraw_cell(cell_id)
	end
	return true -- Gestito
end
--- Pulisce una stringa da caratteri di controllo non desiderati.
-- MANTIENE i codici di escape ANSI per il parsing dei colori.
-- @param str La stringa da pulire.
-- @return La stringa pulita.
local function clean_string(str)
	if not str then
		return ""
	end
	-- Rimuove solo caratteri specifici come NUL, ma non le sequenze ANSI.
	local cleaned = string.gsub(str, "\0", "")
	-- Le barre di avanzamento possono usare \r per sovrascrivere la riga. Lo gestiamo a parte.
	return cleaned
end


--- Pulisce solo i marcatori visuali (extmarks) di una cella.
local function clear_cell_display(cell_info)
	local NS_ID = state.get_namespace_id()
	for _, mark_id in ipairs(cell_info.output_marks) do
		pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, mark_id)
	end
	cell_info.output_marks = {}
end

--- Ridisegna tutti gli output di una cella leggendo dal modulo di stato.
function M.redraw_cell(cell_id)
	local cell_info = state.get_cell(cell_id)
	if not cell_info then
		return
	end
	clear_cell_display(cell_info)

	local NS_ID = state.get_namespace_id()
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
		elseif output.type == "image_inline" or output.type == "image_popup" then
			for _, line_chunks in ipairs(output.content) do
				table.insert(virt_lines, line_chunks)
			end
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

--- Funzione unificata per elaborare e aggiungere/aggiornare output di tipo "rich text".
local function process_rich_output(cell_id, jupyter_msg, output_type, is_update)
	local cell_info = state.get_cell(cell_id)
	if not cell_info then
		return
	end

	-- Gestisce clear_output(wait=true)
	if cell_info.pending_clear then
		state.clear_cell_outputs(cell_id)
		cell_info.pending_clear = false
	end

	local content = jupyter_msg.content
	if not content or not content.data then
		return
	end
	local text_plain = content.data["text/plain"]
	if not (text_plain and text_plain ~= "") then
		return
	end

	-- Estrae il display_id per gli aggiornamenti
	local display_id = (content.transient and content.transient.display_id) or nil

	local cleaned_text = clean_string(text_plain)
	-- Gestisce `\r` per sovrascrivere la riga, tipico delle barre di avanzamento
	cleaned_text = cleaned_text:gsub(".*\r", "")

	local lines_of_chunks = {}
	for _, line in ipairs(vim.split(cleaned_text, "\n", { trimempty = true })) do
		table.insert(lines_of_chunks, ansi.parse(line, "Normal"))
	end

	if #lines_of_chunks == 0 then
		return
	end

	-- Aggiunge il prompt "Out[n]:" se necessario
	if output_type == "execute_result" and content.execution_count then
		local prompt = string.format("Out[%d]: ", content.execution_count)
		table.insert(lines_of_chunks[1], 1, { prompt, "JoveOutPrompt" })
	end

	if is_update and display_id then
		local updated = false
		-- Cerca l'output esistente con lo stesso display_id e lo aggiorna
		for i, output in ipairs(cell_info.outputs) do
			if output.display_id == display_id then
				cell_info.outputs[i].content = lines_of_chunks
				updated = true
				break
			end
		end

		-- Se non è stato trovato nessun output da aggiornare, significa che questo è il
		-- primo messaggio per questo display_id, quindi lo aggiungiamo come nuovo.
		if not updated then
			state.add_output_to_cell(cell_id, {
				type = output_type,
				content = lines_of_chunks,
				display_id = display_id,
			})
		end
		M.redraw_cell(cell_id)
	else
		-- Aggiunge come nuovo output
		state.add_output_to_cell(cell_id, {
			type = output_type,
			content = lines_of_chunks,
			display_id = display_id,
		})
		M.redraw_cell(cell_id)
	end
end

function M.render_stream(cell_id, jupyter_msg)
	local cell_info = state.get_cell(cell_id)
	if not cell_info then
		return
	end

	-- Gestisce clear_output(wait=true)
	if cell_info.pending_clear then
		state.clear_cell_outputs(cell_id)
		cell_info.pending_clear = false
	end

	if not jupyter_msg or not jupyter_msg.content then
		return
	end
	local text = jupyter_msg.content.text
	if not text or text == "" then
		return
	end

	local cleaned_text = clean_string(text)
	cleaned_text = cleaned_text:gsub(".*\r", "") -- Gestisce la sovrascrittura di riga
	local lines_of_chunks = {}
	for _, line in ipairs(vim.split(cleaned_text, "\n", { trimempty = true })) do
		table.insert(lines_of_chunks, ansi.parse(line, "Normal"))
	end

	if #lines_of_chunks > 0 then
		-- Heuristic: stream updates often replace the last stream output.
		if #cell_info.outputs > 0 and cell_info.outputs[#cell_info.outputs].type == "stream" then
			cell_info.outputs[#cell_info.outputs].content = lines_of_chunks
		else
			state.add_output_to_cell(cell_id, { type = "stream", content = lines_of_chunks })
		end
		M.redraw_cell(cell_id)
	end
end

function M.render_execute_result(cell_id, jupyter_msg)
	process_rich_output(cell_id, jupyter_msg, "execute_result", false)
end

function M.render_input_prompt(cell_id, jupyter_msg)
	local exec_count = jupyter_msg.content.execution_count
	local cell_info = state.get_cell(cell_id)
	if not exec_count or not cell_info then
		return
	end

	local NS_ID = state.get_namespace_id()

	-- Pulisce tutti i marcatori visivi (output e prompt) per questa cella
	clear_cell_display(cell_info) -- Pulisce l'output precedente
	state.clear_cell_outputs(cell_id) -- Cancella i dati dell'output precedente
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
	local cell_info = state.get_cell(cell_id)
	if not cell_info then
		return
	end

	-- Gestisce clear_output(wait=true)
	if cell_info.pending_clear then
		state.clear_cell_outputs(cell_id)
		cell_info.pending_clear = false
	end

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
		state.add_output_to_cell(cell_id, { type = "error", content = lines_of_chunks })
		M.redraw_cell(cell_id)
	end
end

function M.render_display_data(cell_id, jupyter_msg)
	local renderer = require("jove").get_config().image_renderer
	local content = jupyter_msg.content

	if content and content.data and content.data["image/png"] then
		if renderer == "popup" then
			if process_popup_image(cell_id, jupyter_msg, false) then
				return -- Gestito
			end
		else -- Tratta qualsiasi altro valore (es. "sixel", "iip") come inline
			if process_inline_image(cell_id, jupyter_msg, false) then
				return -- Gestito
			end
		end
	end

	-- Fallback a testo se non è un'immagine o se il rendering dell'immagine fallisce
	process_rich_output(cell_id, jupyter_msg, "display_data", false)
end

function M.render_update_display_data(cell_id, jupyter_msg)
	local renderer = require("jove").get_config().image_renderer
	local content = jupyter_msg.content

	if content and content.data and content.data["image/png"] then
		if renderer == "popup" then
			if process_popup_image(cell_id, jupyter_msg, true) then
				return -- Gestito
			end
		else
			if process_inline_image(cell_id, jupyter_msg, true) then
				return -- Gestito
			end
		end
	end

	process_rich_output(cell_id, jupyter_msg, "display_data", true)
end

function M.render_clear_output(cell_id, jupyter_msg)
	local wait = jupyter_msg.content.wait or false

	if wait then
		-- Imposta un flag sulla cella per indicare che l'output
		-- deve essere cancellato al prossimo messaggio di output.
		local cell = state.get_cell(cell_id)
		if cell then
			cell.pending_clear = true
		end
	else
		state.clear_cell_outputs(cell_id)
		M.redraw_cell(cell_id)
	end
end

--- Pulisce l'output (testo virtuale e prompt) per le celle che si sovrappongono a un dato range.
-- @param bufnr (integer) Il numero del buffer.
-- @param start_row (integer) La riga di inizio (0-indexed).
-- @param end_row (integer) La riga di fine (0-indexed).
function M.clear_output_in_range(bufnr, start_row, end_row)
	local cells_to_clear = {}
	local NS_ID = state.get_namespace_id()
	for cell_id, cell_info in pairs(state.get_all_cells()) do
		if cell_info.bufnr == bufnr then
			local pos_start = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.start_mark, {})
			local pos_end = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.end_mark, {})

			if pos_start and #pos_start > 0 and pos_end and #pos_end > 0 then
				local cell_start_row = pos_start[1]
				local cell_end_row = pos_end[1]
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
		local cell_info = state.get_cell(cell_id)
		if cell_info then
			-- NUOVO: Pulisce l'immagine dal terminale se esiste
			if cell_info.image_output_info then
				require("jove.image_renderer").clear_image_area(cell_info.image_output_info)
				cell_info.image_output_info = nil -- Rimuovi le informazioni dopo la pulizia
			end

			state.clear_cell_outputs(cell_id)
			M.redraw_cell(cell_id)

			-- Pulisce solo i marcatori di prompt, che non vengono ridisegnati automaticamente
			for _, mark_id in ipairs(cell_info.prompt_marks) do
				pcall(vim.api.nvim_buf_del_extmark, bufnr, NS_ID, mark_id)
			end
			cell_info.prompt_marks = {}
		end
	end

	log.add(vim.log.levels.INFO, "Pulito l'output per " .. #cells_to_clear .. " cella/e.")
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
	local NS_ID = state.get_namespace_id()

	for cell_id, cell_info in pairs(state.get_all_cells()) do
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

	local cell_info = state.get_cell(target_cell_id)
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
		elseif output.type == "image_inline" then
			table.insert(lines, "[Immagine: inline]")
		elseif output.type == "image_popup" then
			for _, line_chunks in ipairs(output.content) do
				local line_text = ""
				for _, chunk in ipairs(line_chunks) do
					line_text = line_text .. chunk[1]
				end
				table.insert(lines, line_text)
			end
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
	display_data = M.render_display_data,
	update_display_data = M.render_update_display_data,
	clear_output = M.render_clear_output,
	error = M.render_error,
	execute_input = M.render_input_prompt,
}

return M
