local M = {}

local log = require("jove.log")

-- Fallback in puro Lua per la codifica base64.
local b64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
local function lua_b64_encode(data)
	return ((data:gsub('.', function(x)
		local r, b = '', x:byte()
		for i = 8, 1, -1 do
			r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0')
		end
		return r
	end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
		if #x < 6 then
			return ''
		end
		local c = 0
		for i = 1, 6 do
			c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0)
		end
		return b64_chars:sub(c + 1, c + 1)
	end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

--- Tenta di usare la funzione nativa di Neovim, altrimenti usa il fallback.
local function b64_encode(data)
	local ok, encoded = pcall(vim.fn.base64encode, data)
	if ok and encoded then
		return encoded
	end
	log.add(vim.log.levels.WARN, "[Jove] Funzione nativa 'base64encode' fallita o non trovata. Uso il fallback in Lua.")
	return lua_b64_encode(data)
end

--- Invia dati grezzi allo stdout del terminale, bypassando la TUI di Neovim.
local function write_raw_to_terminal(data)
	-- DEC Save/Restore Cursor are usually more reliable for iTerm2 direct writes
	local final_data = "\x1b7" .. data .. "\x1b8"

	-- Scrittura diretta su /dev/tty per bypassare il buffer di Neovim
	local tty = io.open("/dev/tty", "wb")
	if tty then
		tty:write(final_data)
		tty:flush()
		tty:close()
		return
	end

	-- Fallback estremo tramite canale nvim (meno diretto ma bufferizzato)
	vim.api.nvim_chan_send(2, final_data)
end

--- Ottiene le proprietà dell'immagine (dimensioni, dati b64) da Python.
-- @param b64_data (string) Dati dell'immagine codificati in base64.
-- @param max_width (number|nil) Larghezza massima in caratteri.
-- @param max_pixels (number|nil) Dimensione massima in pixel (override config).
-- @return (table | nil) Una tabella con `width`, `height`, `b64` o `nil` in caso di errore.
function M.get_inline_image_properties(b64_data, max_width, max_pixels)
	local plugin_root = vim.g.jove_plugin_root
	if not plugin_root then
		return nil, "vim.g.jove_plugin_root non definito."
	end

	-- Sanitizza i dati b64 rimuovendo eventuali newline che potrebbero rompere il passaggio argomenti
	b64_data = b64_data:gsub("[\n\r]", "")

	local python_script = plugin_root .. "/python/image_renderer.py"
	local python_exec = vim.g.python3_host_prog or vim.g.jove_default_python or "python3"

	-- Esegue lo script python passandogli i dati b64 via stdin
	-- Passa la larghezza massima come argomento se fornita
	local cmd = { python_exec, python_script }
	if max_width then
		table.insert(cmd, tostring(max_width))
	else
		table.insert(cmd, "80") -- Default width if not provided
	end

	-- Gestione max_pixels: priorità all'argomento, poi config
	if max_pixels then
		table.insert(cmd, tostring(max_pixels))
	else
		local config = require("jove").get_config()
		local config_max = config.image_max_size
		if config_max then
			table.insert(cmd, tostring(config_max))
		end
	end

	local json_result = vim.fn.system(cmd, b64_data)

	if vim.v.shell_error ~= 0 then
		return nil, "Errore esecuzione Python: " .. json_result
	end

	local ok, image_data = pcall(vim.json.decode, json_result)
	if not ok or (image_data and image_data.error) then
		local err_msg = (image_data and image_data.error) or tostring(json_result)
		return nil, "Errore da Python: " .. err_msg
	end
	if not image_data or not image_data.b64 or not image_data.height or not image_data.width then
		return nil, "Dati immagine incompleti da Python."
	end

	return image_data
end

--- Disegna un'immagine nel terminale e registra le sue informazioni per la pulizia.
function M.draw_and_register_inline_image(bufnr, lineno, image_props, cell_id, row_offset, col_offset)
	local cell_info = cell_id and require("jove.state").get_cell(cell_id)
	row_offset = row_offset or 0
	col_offset = col_offset or 0

	-- Trova la finestra che visualizza il buffer
	local winid = vim.fn.bufwinid(bufnr)
	if winid == -1 then
		return
	end

	-- Verifica se la finestra è valida per screenpos
	if not vim.api.nvim_win_is_valid(winid) then
		return
	end

	-- Ottiene la posizione sullo schermo della riga del buffer.
	local pos = vim.fn.screenpos(winid, lineno + 1, 1)
	if pos.row == 0 and pos.col == 0 then
		return
	end

	-- Applichiamo gli offset alla posizione calcolata.
	-- +1 perché screenpos restituisce la riga del testo nel buffer,
	-- e le immagini vengono caricate nello spazio delle virtual lines sotto.
	local screen_row = pos.row + 1 + row_offset
	local screen_col = pos.col + col_offset

	if cell_info then
		cell_info.image_output_info = {
			bufnr = bufnr,
			buffer_line = lineno,
			width = image_props.width,
			height = image_props.height,
			line = screen_row,
			col = screen_col,
		}
	end

	local move_cursor_cmd = string.format("\x1b[%d;%dH", screen_row, screen_col)
	local sequence = string.format("\x1b]1337;File=inline=1:%s\a", image_props.b64)
	write_raw_to_terminal(move_cursor_cmd .. sequence)
end

--- Disegna un'immagine a coordinate assolute dello schermo (per finestre flottanti).
function M.draw_inline_image_at_pos(screen_row, screen_col, image_props)
	-- +1 per il bordo della finestra, +1 perché le coordinate ANSI sono 1-indexed.
	local target_col = screen_col + 1 + 1
	-- +1 perché le coordinate ANSI sono 1-indexed.
	local target_row = screen_row + 1
	local move_cursor_cmd = string.format("\x1b[%d;%dH", target_row, target_col)
	local sequence = string.format("\x1b]1337;File=inline=1;size=%d;doNotMoveCursor=1:%s\a", #image_props.b64, image_props.b64)
	write_raw_to_terminal(move_cursor_cmd .. sequence)
end

function M.render_image_from_b64(bufnr, lineno, b64_data, cell_id)
	local image_props, err = M.get_inline_image_properties(b64_data)
	if err then
		log.add(vim.log.levels.ERROR, "[Jove TestImage] " .. err)
		return
	end
	M.draw_and_register_inline_image(bufnr, lineno, image_props, cell_id)
end

--- Renderizza un'immagine da un file (per JoveTestImage).
function M.render_image_inline(bufnr, lineno, image_path, cell_id)
	-- Questa funzione ora legge il file e delega a `render_image_from_b64`.
	local file = io.open(image_path, "rb")
	if not file then
		log.add(vim.log.levels.ERROR, "Impossibile aprire il file immagine: " .. image_path)
		return
	end
	local content = file:read("*a")
	file:close()
	local b64_data = b64_encode(content)
	M.render_image_from_b64(bufnr, lineno, b64_data, cell_id)
end

--- Pulisce l'area dove era stata disegnata un'immagine.
function M.clear_image_area(image_info)
	if not image_info then
		return
	end

	local start_row, start_col

	if image_info.bufnr and image_info.buffer_line then
		local winid = vim.fn.bufwinid(image_info.bufnr)
		if winid == -1 then
			-- Se il buffer non è visibile, non c'è nulla da pulire sullo schermo
			return
		end

		local pos = vim.fn.screenpos(winid, image_info.buffer_line + 1, 1)
		if pos.row == 0 then
			return
		end

		start_row = pos.row + 1
		start_col = pos.col
	elseif image_info.line then
		-- Modalità assoluta (es. popup o legacy)
		start_row = image_info.line
		start_col = image_info.col or 1
	else
		return
	end

	local w, h = image_info.width, image_info.height
	local space_line = string.rep(" ", w)
	local clear_packet = ""

	for i = 0, h - 1 do
		-- Usiamo start_col se disponibile, altrimenti 1
		local col = start_col or 1
		local move_cmd = string.format("\x1b[%d;%dH", start_row + i, col)
		clear_packet = clear_packet .. move_cmd .. space_line
	end

	write_raw_to_terminal(clear_packet)
end

--- NUOVO: Renderizza un'immagine da dati B64 in una finestra popup Tcl/Tk.
-- @param b64_data (string) I dati dell'immagine codificati in base64.
function M.render_image_popup_from_b64(b64_data)
	local popup_script = vim.g.jove_plugin_root .. "/python/popup_renderer.py"
	local executable = vim.g.python3_host_prog or vim.g.jove_default_python or "python"

	local cmd = {
		executable,
		"-u",
		popup_script,
	}

	local job_id = vim.fn.jobstart(cmd, {
		stdin = "pipe",
		on_stderr = function(_, data, _)
			if data then
				require("jove.log").add(
					vim.log.levels.ERROR,
					"Image Popup stderr: " .. table.concat(data, "\n")
				)
			end
		end,
	})

	if job_id and job_id > 0 then
		vim.fn.chansend(job_id, b64_data)
		vim.fn.chanclose(job_id, "stdin") -- Chiude lo stdin dopo aver inviato i dati
	else
		log.add(vim.log.levels.ERROR, "Impossibile avviare il processo popup_renderer.py.")
	end
end

return M
