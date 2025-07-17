-- lua/jove/message.lua
local M = {}

local function new_header(msg_type)
	local header = {
		msg_id = vim.fn.reltimestr(vim.fn.reltime()),
		session = vim.v.servername, -- or a unique session ID
		username = vim.env.USER or "unknown",
		date = os.date("!%FT%TZ"),
		msg_type = msg_type,
		version = "5.3",
	}
	return header
end

function M.create_execute_request(code)
	local content = {
		code = code,
		silent = false,
		store_history = true,
		user_expressions = vim.empty_dict(),
		allow_stdin = false,
		stop_on_error = true,
	}

	return {
		header = new_header("execute_request"),
		metadata = vim.empty_dict(),
		content = content,
		buffers = {},
		parent_header = vim.empty_dict(),
	}
end

--- Crea un messaggio di inspect_request.
-- @param code (string) Il codice da ispezionare (di solito la riga corrente).
-- @param cursor_pos (integer) La posizione del cursore (colonna) all'interno della stringa di codice.
function M.create_inspect_request(code, cursor_pos)
	local content = {
		code = code,
		cursor_pos = cursor_pos,
		detail_level = 0, -- 0 per info base, 1 per info dettagliate
	}
	return {
		header = new_header("inspect_request"),
		metadata = vim.empty_dict(),
		content = content,
		buffers = {},
		parent_header = vim.empty_dict(),
	}
end

--- Crea un messaggio di history_request.
function M.create_history_request()
	local content = {
		output = false,
		raw = true,
		hist_access_type = "range", -- Richiede una serie di voci della cronologia
		session = 0, -- 0 per la sessione corrente
		start = 1,
		stop = 1000, -- Limita alle ultime 1000 voci
	}
	return {
		header = new_header("history_request"),
		metadata = vim.empty_dict(),
		content = content,
		buffers = {},
		parent_header = vim.empty_dict(),
	}
end

return M
