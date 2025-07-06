-- message.lua
local M = {}

local function new_header(msg_type)
	local header = {
		msg_id = vim.fn.reltimestr(vim.fn.reltime()),
		session = vim.v.servername, -- or a unique session ID
		username = vim.env.USER,
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
		user_expressions = vim.empty_dict(), -- Usa un dizionario vuoto per la corretta codifica JSON
		allow_stdin = false,
		stop_on_error = true,
	}

	local msg = {
		header = new_header("execute_request"),
		metadata = vim.empty_dict(), -- Usa un dizionario vuoto
		content = content,
		buffers = {}, -- Questo deve essere un array JSON, quindi {} va bene
		parent_header = vim.empty_dict(), -- Usa un dizionario vuoto
	}
	return msg
end

return M
