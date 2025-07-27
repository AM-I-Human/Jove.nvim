-- file: lua/jove/kernel.lua

local M = {}
local config_module = require("jove")
local status = require("jove.status")
local message = require("jove.message")
local output = require("jove.output")

local function get_plugin_root()
	-- Get the path of the current Lua source file
	function get_plugin_path(plugin_name)
		local paths = vim.api.nvim_list_runtime_paths()
		for _, path in ipairs(paths) do
			if path:match(plugin_name .. "$") then
				return path
			end
		end
		return "."
	end

	local my_plugin_path = get_plugin_path("Jove.nvim")
	return my_plugin_path
end

function M.start(kernel_name)
	if not kernel_name then
		vim.notify("Kernel name is nil", vim.log.levels.ERROR)
		return
	end

	local kernels_config = config_module.get_config().kernels
	if kernels_config[kernel_name] and kernels_config[kernel_name].py_client_job_id then
		vim.notify("Kernel client for '" .. kernel_name .. "' is already running or starting.", vim.log.levels.WARN)
		return
	end
	status.update_status(kernel_name, "starting")

	local kernel_config = kernels_config[kernel_name]
	if not kernel_config then
		vim.notify("Configurazione non trovata per il kernel: " .. kernel_name, vim.log.levels.ERROR)
		return
	end
	local python_exec = kernel_config.executable or vim.g.jove_default_python or "python"
	local connection_file = vim.fn.tempname() .. ".json"

	local ipykernel_cmd = string.gsub(kernel_config.cmd, "{executable}", python_exec)
	ipykernel_cmd = string.gsub(ipykernel_cmd, "{connection_file}", connection_file)

	vim.notify("Avvio del processo ipykernel: " .. ipykernel_cmd, vim.log.levels.INFO)
	local ipykernel_job_id = vim.fn.jobstart(ipykernel_cmd, {
		on_stderr = function(_, data, _)
			if data then
				vim.notify(
					"ipykernel stderr (" .. kernel_name .. "): " .. table.concat(data, "\n"),
					vim.log.levels.WARN
				)
			end
		end,
		on_exit = function(_, exit_code, _)
			vim.notify(
				"Processo ipykernel per '" .. kernel_name .. "' terminato con codice: " .. exit_code,
				vim.log.levels.INFO
			)
		end,
	})

	if ipykernel_job_id <= 0 then
		vim.notify("Errore nell'avvio del processo ipykernel per: " .. kernel_name, vim.log.levels.ERROR)
		status.update_status(kernel_name, "error")
		return
	end

	local poll_interval_ms = 100
	local timeout_ms = 10000
	local attempts = timeout_ms / poll_interval_ms

	local function poll_for_connection_file()
		if attempts <= 0 then
			vim.notify(
				"Timeout: Il file di connessione per '" .. kernel_name .. "' non è stato creato in tempo.",
				vim.log.levels.ERROR
			)
			vim.fn.jobstop(ipykernel_job_id)
			return
		end
		attempts = attempts - 1
		if vim.fn.filereadable(connection_file) == 1 and #vim.fn.readfile(connection_file) > 0 then
			M.start_python_client(kernel_name, connection_file, ipykernel_job_id)
			return
		end
		vim.defer_fn(poll_for_connection_file, poll_interval_ms)
	end
	vim.defer_fn(poll_for_connection_file, poll_interval_ms)
end

function M.start_python_client(kernel_name, connection_file_path, ipykernel_job_id_ref)
	local kernels_config = config_module.get_config().kernels
	local py_client_script = get_plugin_root() .. "/python/py_kernel_client.py"
	local executable = (kernels_config[kernel_name] or {}).executable or "python"
	local py_client_cmd = { executable, "-u", py_client_script, connection_file_path }

	-- Assicura che la tabella esista e imposta i job ID
	kernels_config[kernel_name] = kernels_config[kernel_name] or {}
	kernels_config[kernel_name].ipykernel_job_id = ipykernel_job_id_ref
	kernels_config[kernel_name].py_client_job_id = nil

	local py_job_id = vim.fn.jobstart(py_client_cmd, {
		stdin = "pipe",
		on_stdout = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						vim.schedule(function()
							M.handle_py_client_message(kernel_name, line)
						end)
					end
				end
			end
		end,
		on_stderr = function(_, data, _)
			vim.notify(
				"Python client stderr (" .. kernel_name .. "): " .. table.concat(data, "\n"),
				vim.log.levels.ERROR
			)
		end,
		on_exit = function(_, exit_code, _)
			local msg = "Client Python per '" .. kernel_name .. "' terminato con codice: " .. exit_code
			vim.notify(msg, vim.log.levels.INFO)
			if kernels_config[kernel_name] then
				kernels_config[kernel_name].py_client_job_id = nil
			end
		end,
	})
	kernels_config[kernel_name].py_client_job_id = py_job_id
end

function M.handle_py_client_message(kernel_name, json_line)
	local kernels_config = config_module.get_config().kernels
	if not kernels_config[kernel_name] then
		return
	end

	local ok, data = pcall(vim.json.decode, json_line)
	if not ok then
		vim.notify("Errore JSON da Python (" .. kernel_name .. "): " .. json_line, vim.log.levels.ERROR)
		return
	end

	local msg_type = data.type
	local jupyter_msg = data.message

	if msg_type == "status" and data.message == "connected" then
		status.update_status(kernel_name, "idle")
	elseif msg_type == "iopub" and jupyter_msg.header.msg_type == "status" then
		status.update_status(kernel_name, jupyter_msg.content.execution_state)
	elseif msg_type == "error" then
		vim.notify("Errore dal client Python (" .. kernel_name .. "): " .. data.message, vim.log.levels.ERROR)
		status.update_status(kernel_name, "error")
	elseif msg_type == "shell" then
		local shell_msg_type = jupyter_msg.header.msg_type
		if shell_msg_type == "inspect_reply" then
			output.render_inspect_reply(jupyter_msg)
		elseif shell_msg_type == "history_reply" then
			output.render_history_reply(jupyter_msg)
		elseif shell_msg_type == "interrupt_reply" then
			vim.notify("Kernel interrotto con successo.", vim.log.levels.INFO)
			status.update_status(kernel_name, "idle")
		end
	elseif msg_type == "iopub" and kernels_config[kernel_name].current_execution_bufnr then
		local iopub_msg_type = jupyter_msg.header.msg_type
		local handler = output.iopub_handlers[iopub_msg_type]
		if handler then
			handler(
				kernels_config[kernel_name].current_execution_bufnr,
				kernels_config[kernel_name].current_execution_row,
				jupyter_msg
			)
		end
	end
end

function M.execute_cell(kernel_name, cell_content, bufnr, row)
	local kernels_config = config_module.get_config().kernels
	local kernel_info = kernels_config[kernel_name]
	if not kernel_info or not kernel_info.py_client_job_id then
		return
	end
	--- CORREZIONE: Chiamata alla funzione corretta in status.lua ---
	if status.get_status(kernel_name) ~= "idle" then
		vim.notify("Kernel '" .. kernel_name .. "' è occupato.", vim.log.levels.WARN)
		return
	end
	kernel_info.current_execution_bufnr = bufnr
	kernel_info.current_execution_row = row
	status.update_status(kernel_name, "busy")
	M.send_to_py_client(kernel_name, { command = "execute", payload = message.create_execute_request(cell_content) })
end

function M.inspect(kernel_name, code, cursor_pos)
	M.send_to_py_client(
		kernel_name,
		{ command = "inspect", payload = message.create_inspect_request(code, cursor_pos).content }
	)
end

function M.interrupt(kernel_name)
	M.send_to_py_client(kernel_name, { command = "interrupt" })
end

--- CORREZIONE: Logica di riavvio "stop and start" non distruttiva ---
function M.restart(kernel_name)
	local kernels_config = config_module.get_config().kernels
	local kernel_info = kernels_config[kernel_name]
	if not kernel_info then
		vim.notify("Impossibile riavviare un kernel non esistente: " .. kernel_name, vim.log.levels.WARN)
		return
	end

	vim.notify("Arresto del kernel '" .. kernel_name .. "' per il riavvio...", vim.log.levels.INFO)

	-- Arresta i processi esistenti
	if kernel_info.py_client_job_id then
		vim.fn.jobstop(kernel_info.py_client_job_id)
		kernel_info.py_client_job_id = nil
	end
	if kernel_info.ipykernel_job_id then
		vim.fn.jobstop(kernel_info.ipykernel_job_id)
		kernel_info.ipykernel_job_id = nil
	end

	-- Pulisci lo stato, ma NON la configurazione statica
	status.remove_kernel(kernel_name)

	-- Aggiungi un piccolo ritardo per dare tempo al sistema operativo di chiudere i processi
	vim.defer_fn(function()
		vim.notify("Riavvio del kernel '" .. kernel_name .. "'...", vim.log.levels.INFO)
		M.start(kernel_name)
		-- Associa di nuovo il kernel al buffer corrente
		vim.b.jove_active_kernel = kernel_name
		status.set_active_kernel(kernel_name)
	end, 200) -- 200ms di ritardo
end

function M.history(kernel_name)
	M.send_to_py_client(kernel_name, { command = "history", payload = message.create_history_request().content })
end

function M.send_to_py_client(kernel_name, data_table)
	local kernels_config = config_module.get_config().kernels
	local kernel_info = kernels_config[kernel_name]
	if not kernel_info or not kernel_info.py_client_job_id then
		return
	end
	local json_data = vim.json.encode(data_table)
	vim.fn.jobsend(kernel_info.py_client_job_id, json_data .. "\n")
end

-- Funzioni di utility non modificate
function M.parse_connection_file(filename)
	local file = io.open(filename, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	local ok, result = pcall(vim.json.decode, content)
	return ok and result or nil
end

function M.list_running_kernels()
	local kernels_config = config_module.get_config().kernels
	local running = {}
	if not next(kernels_config) then
		return { "Nessun kernel gestito al momento." }
	end
	for name, info in pairs(kernels_config) do
		local status_line = string.format(
			"Kernel: %s, Stato: %s, IPYKernel Job ID: %s, PyClient Job ID: %s",
			name,
			status.get_status(name) or "sconosciuto",
			tostring(info.ipykernel_job_id),
			tostring(info.py_client_job_id)
		)
		table.insert(running, status_line)
	end
	return running
end

vim.api.nvim_create_augroup("JoveCleanup", { clear = true })
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = "JoveCleanup",
	pattern = "*",
	callback = function()
		local kernels_config = config_module.get_config().kernels
		if kernels_config and next(kernels_config) ~= nil then
			for name, info in pairs(kernels_config) do
				if info.py_client_job_id then
					vim.fn.jobstop(info.py_client_job_id)
				end
				if info.ipykernel_job_id then
					vim.fn.jobstop(info.ipykernel_job_id)
				end
			end
		end
	end,
})

return M
