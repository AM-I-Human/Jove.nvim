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
		user_expressions = {},
		allow_stdin = false,
		stop_on_error = true,
	}

	local msg = {
		header = new_header("execute_request"),
		metadata = {},
		content = content,
		buffers = {},
		parent_header = {},
	}
	return msg
end

return M
