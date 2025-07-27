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
--- @param level vim.log.levels
--- @param message string
function M.add(level, message)
	local level_str = log_levels[level] or "UNKNOWN"
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")

	local log_entry = string.format("[%s] [%s] %s", timestamp, level_str, message)
	table.insert(log_messages, log_entry)

	-- Continua a notificare per i messaggi importanti
	if level >= vim.log.levels.INFO then
		vim.notify(message, level)
	end
end

--- Mostra lo storico dei log in un nuovo buffer.
function M.show()
	if #log_messages == 0 then
		M.add(vim.log.levels.INFO, "Nessun log da mostrare.")
		return
	end

	vim.cmd("enew")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "hide"
	vim.bo[bufnr].swapfile = false
	vim.api.nvim_buf_set_name(bufnr, "JoveLog")
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, log_messages)
	vim.bo[bufnr].readonly = true
	vim.bo[bufnr].filetype = "log"
end

return M
