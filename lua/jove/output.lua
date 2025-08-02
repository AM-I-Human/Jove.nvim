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
	local virt_lines_chunks = output_data.lines

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

local function add_output_lines(bufnr, end_row, lines_of_chunks)
	if not execution_outputs[bufnr] then
		execution_outputs[bufnr] = { end_row = end_row, lines = {} }
	end

	for _, line_chunks in ipairs(lines_of_chunks) do
		table.insert(execution_outputs[bufnr].lines, line_chunks)
	end

	render_accumulated_output(bufnr)
end

local highlights_cache = {}

--- Converte un output ANSI (da chafa) in un formato per il testo virtuale di Neovim.
local function parse_ansi_to_virt_text(ansi_text)
	local lines = vim.split(ansi_text, "\n")
	local virt_lines = {}
	local current_fg = nil
	local current_bg = nil

	for _, line in ipairs(lines) do
		local virt_line = {}
		local remaining_line = line
		while #remaining_line > 0 do
			local s, e, seq = string.find(remaining_line, "(\27%[.-m)")
			local text_chunk = s and string.sub(remaining_line, 1, s - 1) or remaining_line

			if #text_chunk > 0 then
				local hl_group = "Normal"
				if current_fg or current_bg then
					local fg_hex = current_fg and string.format("#%02x%02x%02x", current_fg[1], current_fg[2], current_fg[3])
						or "NONE"
					local bg_hex = current_bg and string.format("#%02x%02x%02x", current_bg[1], current_bg[2], current_bg[3])
						or "NONE"
					hl_group = "JoveImg_" .. (fg_hex):gsub("#", "") .. "_" .. (bg_hex):gsub("#", "")

					if not highlights_cache[hl_group] then
						local hl_opts = {}
						if fg_hex ~= "NONE" then
							hl_opts.fg = fg_hex
						end
						if bg_hex ~= "NONE" then
							hl_opts.bg = bg_hex
						end
						vim.api.nvim_set_hl(0, hl_group, hl_opts)
						highlights_cache[hl_group] = true
					end
				end
				table.insert(virt_line, { text_chunk, hl_group })
			end

			if not s then
				break
			end
			remaining_line = string.sub(remaining_line, e + 1)
			local params_str = seq:match("%[(.*)m")
			if params_str then
				local params = {}
				for p in string.gmatch(params_str, "%d+") do
					table.insert(params, tonumber(p))
				end
				local i = 1
				while i <= #params do
					local p = params[i]
					if p == 0 then
						current_fg, current_bg = nil, nil
					elseif p == 38 and params[i + 1] == 2 then
						current_fg = { params[i + 2], params[i + 3], params[i + 4] }
						i = i + 4
					elseif p == 48 and params[i + 1] == 2 then
						current_bg = { params[i + 2], params[i + 3], params[i + 4] }
						i = i + 4
					end
					i = i + 1
				end
			end
		end
		table.insert(virt_lines, virt_line)
	end
	return virt_lines
end

--- Renderizza una stringa ANSI come testo virtuale. Chiamata da kernel.lua
function M.render_ansi_image(bufnr, start_row, end_row, ansi_string)
	clear_range(bufnr, start_row, end_row)
	execution_outputs[bufnr] = nil

	local virt_lines = parse_ansi_to_virt_text(ansi_string)
	add_output_lines(bufnr, end_row, virt_lines)
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
		local lines_of_chunks = {}
		for _, line in ipairs(lines) do
			table.insert(lines_of_chunks, { { line, "String" } })
		end
		add_output_lines(bufnr, end_row, lines_of_chunks)
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
		local lines_of_chunks = {}
		for _, line in ipairs(lines) do
			table.insert(lines_of_chunks, { { line, "Comment" } })
		end
		add_output_lines(bufnr, end_row, lines_of_chunks)
	end
end

function M.render_execute_result(bufnr, start_row, end_row, jupyter_msg)
	-- La gestione delle immagini è ora fatta in Python e invia un messaggio separato.
	-- Questa funzione gestisce solo il fallback testuale.
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

		local lines_of_chunks = {}
		for _, line in ipairs(cleaned_traceback) do
			table.insert(lines_of_chunks, { { line, "ErrorMsg" } })
		end
		add_output_lines(bufnr, end_row, lines_of_chunks)
	end
end

function M.render_display_data(bufnr, start_row, end_row, jupyter_msg)
	-- La gestione delle immagini è ora fatta in Python e invia un messaggio separato.
	-- Questa funzione gestisce solo il fallback testuale.
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
