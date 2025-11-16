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

--- Assicura che il percorso python del plugin sia aggiunto a sys.path in Python.
local function setup_python_path()
	-- Questa funzione assicura che il nostro modulo `image_renderer.py` sia importabile.
	if M._python_path_setup then
		return
	end

	local plugin_root = vim.g.jove_plugin_root
	if not plugin_root then
		log.add(vim.log.levels.ERROR, "[Jove] `vim.g.jove_plugin_root` non è definito. Impossibile trovare il backend Python.")
		return
	end

	local python_path = plugin_root .. "/python"

	-- Aggiunge il percorso a sys.path di Python, se non è già presente.
	local python_code = string.format([[
import sys
path = r'%s'
if path not in sys.path:
    sys.path.append(path)
]], python_path)
	vim.cmd("py3 << EOF\n" .. python_code .. "\nEOF")
	M._python_path_setup = true
end

--- Invia dati grezzi allo stdout del terminale, bypassando la TUI di Neovim.
local function write_raw_to_terminal(data)
	-- Usa vim.loop (libuv) per scrivere direttamente sul TTY di stdout (fd=1).
	-- Questo bypassa l'interprete RPC di Neovim, che causa errori come
	-- "Can't send raw data to rpc channel".
	local stdout = vim.loop.new_tty(1, false)
	if not stdout then
		log.add(vim.log.levels.ERROR, "[Jove Image] Impossibile aprire TTY per stdout.")
		return
	end

	stdout:write(data, function(err)
		if err then
			log.add(vim.log.levels.ERROR, "[Jove Image] Errore di scrittura su stdout: " .. err)
		end
		-- È importante chiudere l'handle dopo la scrittura asincrona.
		stdout:close()
	end)
end

--- Ottiene le proprietà dell'immagine (dimensioni, dati b64) da Python.
-- @param b64_data (string) Dati dell'immagine codificati in base64.
-- @return (table | nil) Una tabella con `width`, `height`, `b64` o `nil` in caso di errore.
function M.get_inline_image_properties(b64_data)
	setup_python_path()
	if not M._python_path_setup then
		return nil, "Python path non configurato."
	end

	local py_call = string.format('__import__("image_renderer").prepare_iterm_image_from_b64("%s")', b64_data)
	local json_result = vim.fn.py3eval(py_call)
	if not json_result then
		return nil, "Python non ha restituito dati."
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
function M.draw_and_register_inline_image(bufnr, lineno, image_props, cell_id)
	local cell_info = cell_id and require("jove.state").get_cell(cell_id)
	if cell_info then
		cell_info.image_output_info = {
			line = lineno + 1, -- La pulizia è 1-indexed
			width = image_props.width,
			height = image_props.height,
		}
	end

	local move_cursor_cmd = string.format("\x1b[%d;1H", lineno + 2) -- +1 per 1-indexing, +1 per andare sotto la linea
	local sequence = string.format("\x1b]1337;File=inline=1;doNotMoveCursor=1:%s\a", image_props.b64)
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

	local r, w, h = image_info.line, image_info.width, image_info.height
	local space_line = string.rep(" ", w)
	local clear_packet = ""

	for i = 0, h - 1 do
		local move_cmd = string.format("\x1b[%d;1H", r + 1 + i)
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
