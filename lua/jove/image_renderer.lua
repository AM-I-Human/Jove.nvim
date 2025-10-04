local M = {}

local log = require("jove.log")

local NS_ID = vim.api.nvim_create_namespace("jove_inline_image")

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
	vim.fn.py3eval(python_code)
	M._python_path_setup = true
end

--- Renderizza un'immagine inline nel buffer specificato.
-- @param bufnr (integer) Il numero del buffer.
-- @param lineno (integer) La riga (0-indexed) su cui renderizzare l'immagine.
-- @param image_path (string) Il percorso del file immagine.
function M.render_image(bufnr, lineno, image_path)
	setup_python_path()

	if not M._python_path_setup then
		return -- Non continuare se il setup del percorso python è fallito
	end

	-- Prepara la chiamata alla funzione python in modo sicuro, escapando il percorso.
	-- NOTA: Windows usa '\', che deve essere escapato in stringhe Lua e Python.
	local safe_path = string.gsub(image_path, "\\", "\\\\")
	local py_call = string.format('__import__("image_renderer").prepare_iterm_image(r"%s")', safe_path)

	local b64_data = vim.fn.py3eval(py_call)

	-- Controlla se Python ha restituito un errore.
	if not b64_data or b64_data:match("^Error:") then
		log.add(vim.log.levels.ERROR, "[Jove Image] " .. (b64_data or "Errore sconosciuto da Python."))
		return
	end

	-- Costruisce la sequenza di escape iTerm2.
	-- Usiamo `preserveAspectRatio=1` per evitare distorsioni.
	local sequence = string.format("\x1b]1337;File=inline=1;preserveAspectRatio=1:%s\a", b64_data)

	-- Pulisce eventuali immagini precedenti sulla stessa riga.
	vim.api.nvim_buf_clear_namespace(bufnr, NS_ID, lineno, lineno + 1)

	-- Inserisce la sequenza come testo virtuale SOTTO la riga specificata.
	-- Anche se richiesto `virt_text`, `virt_lines` offre un'esperienza utente migliore
	-- non sovrapponendosi al codice, ed è tecnicamente corretto.
	vim.api.nvim_buf_set_extmark(bufnr, NS_ID, lineno, -1, {
		virt_lines = { { { sequence, "Normal" } } },
		virt_lines_above = false,
	})
end

--- NUOVO: Renderizza un'immagine in una finestra popup Tcl/Tk.
-- @param image_path (string) Il percorso del file immagine.
function M.render_image_popup(image_path)
	local popup_script = vim.g.jove_plugin_root .. "/python/popup_renderer.py"
	-- Usa l'eseguibile Python di Neovim per il client
	local executable = vim.g.python3_host_prog
		or vim.g.jove_default_python
		or "python"

	local cmd = {
		executable,
		"-u",
		popup_script,
		image_path,
	}

	vim.fn.jobstart(cmd, {
		on_stderr = function(_, data, _)
			if data then
				require("jove.log").add(
					vim.log.levels.ERROR,
					"Image Popup stderr: " .. table.concat(data, "\n")
				)
			end
		end,
	})
end

return M
