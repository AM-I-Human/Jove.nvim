-- lua/jove/log.lua
local M = {}

local log_messages = {}
local log_levels = {
	[vim.log.levels.TRACE] = "TRACE",
	[vim.log.levels.DEBUG] = "DEBUG",
	[vim.log.levels.INFO] = "INFO",
	[vim.log.levels.WARN] = "WARN",
	[vim.log.levels.ERROR] = "ERROR",
}

--- Aggiunge un messaggio al log e lo notifica all'utente.
--- Gestisce i messaggi su più righe.
--- @param level vim.log.levels
--- @param message string
function M.add(level, message)
	local lines = vim.split(message, "\n")
	local level_str = log_levels[level] or "UNKNOWN"
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")

	-- Aggiungi la prima riga con timestamp e livello
	local first_line = string.format("[%s] [%s] %s", timestamp, level_str, lines[1])
	table.insert(log_messages, first_line)

	-- Aggiungi le righe successive con indentazione per allineamento
	if #lines > 1 then
		local prefix = string.format("[%s] [%s] ", timestamp, level_str)
		local indent = string.rep(" ", #prefix)
		for i = 2, #lines do
			table.insert(log_messages, indent .. lines[i])
		end
	end

	-- Continua a notificare per i messaggi importanti
	if level >= vim.log.levels.INFO then
		vim.notify(message, level)
	end
end

--- Mostra lo storico dei log in una finestra flottante.
function M.show()
	if #log_messages == 0 then
		M.add(vim.log.levels.INFO, "Nessun log da mostrare.")
		return
	end

	-- Crea un buffer temporaneo per il contenuto del log
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.api.nvim_buf_set_name(buf, "JoveLog")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, log_messages)
	vim.bo[buf].readonly = true
	vim.bo[buf].filetype = "log"

	-- Calcola dimensioni e posizione della finestra
	local width = math.floor(vim.o.columns * 0.5)
	local height = math.floor(vim.o.lines * 0.4)
	local row = vim.o.lines - height -- In basso
	local col = vim.o.columns - width -- A destra

	-- Apri la finestra flottante
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = "Jove Log",
		title_pos = "center",
	})

	-- Mappa 'q' per chiudere la finestra
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", { noremap = true, silent = true })
end

return M
