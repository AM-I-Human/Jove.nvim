-- file: lua/jove/kernel.lua

local M = {}
local config = require("jove").get_config()
local kernels_config = config.kernels
local status = require("jove.status")
local message = require("jove.message")
local output = require("jove.output")

function M.start(kernel_name)
	if not kernel_name then
		vim.notify("Kernel name is nil", vim.log.levels.ERROR)
		return
	end

	if kernels_config[kernel_name] and kernels_config[kernel_name].py_client_job_id then
		vim.notify("Kernel client for '" .. kernel_name .. "' is already running or starting.", vim.log.levels.WARN)
		return
	end
	status.update_status(kernel_name, "starting")

	local kernel_config = kernels_config[kernel_name]
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
			local kernel_info = kernels_config[kernel_name]
			-- Controlla se il kernel esiste e se il flag di riavvio è impostato
			if kernel_info and kernel_info.is_restarting then
				vim.notify(
					"Processo ipykernel terminato per riavvio. Il client Python si riconnetterà.",
					vim.log.levels.INFO
				)
				-- Resetta il flag. Il client Python gestirà la logica di riconnessione.
				kernel_info.is_restarting = false
				kernel_info.ipykernel_job_id = nil -- Il vecchio job ID non è più valido
			else
				-- Comportamento di default per chiusura normale o errore
				vim.notify(
					"Processo ipykernel per '" .. kernel_name .. "' terminato con codice: " .. exit_code,
					vim.log.levels.INFO
				)
				if kernel_info then
					M.stop_python_client(kernel_name, "Il processo ipykernel è terminato.")
					kernels_config[kernel_name] = nil
				end
				status.remove_kernel(kernel_name)
			end
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
			status.update_status(kernel_name, "error")
			return
		end
		attempts = attempts - 1
		if vim.fn.filereadable(connection_file) == 1 then
			local content = vim.fn.readfile(connection_file)
			if content and #content > 0 then
				M.start_python_client(kernel_name, connection_file, ipykernel_job_id)
				return
			end
		end
		vim.defer_fn(poll_for_connection_file, poll_interval_ms)
	end
	vim.defer_fn(poll_for_connection_file, poll_interval_ms)
end

function M.start_python_client(kernel_name, connection_file_path, ipykernel_job_id_ref)
	local py_client_script = vim.g.jove_plugin_root .. "/python/py_kernel_client.py"
	local executable = (kernels_config[kernel_name] or {}).executable or "python"
	local py_client_cmd = { executable, "-u", py_client_script, connection_file_path }

	kernels_config[kernel_name] = kernels_config[kernel_name] or {}
	kernels_config[kernel_name].ipykernel_job_id = ipykernel_job_id_ref

	local py_job_id = vim.fn.jobstart(py_client_cmd, {
		stdin = "pipe",
		rpc = false,
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
			local kernel_entry = kernels_config[kernel_name]
			if kernel_entry and kernel_entry.status ~= "disconnecting" then
				vim.notify(msg, vim.log.levels.WARN)
				status.update_status(kernel_name, "error")
			else
				vim.notify(msg, vim.log.levels.INFO)
				status.update_status(kernel_name, "disconnected")
			end
			if kernel_entry then
				kernel_entry.py_client_job_id = nil
			end
		end,
	})
	kernels_config[kernel_name].py_client_job_id = py_job_id
end

function M.handle_py_client_message(kernel_name, json_line)
	local kernel_info = kernels_config[kernel_name]
	if not kernel_info then
		return
	end

	local ok, data = pcall(vim.json.decode, json_line)
	if not ok then
		vim.notify("Errore JSON da Python (" .. kernel_name .. "): " .. json_line, vim.log.levels.ERROR)
		return
	end

	local msg_type = data.type
	local jupyter_msg = data.message

	if msg_type == "status" then
		if data.message == "connected" then
			kernel_info.status = "idle"
			status.update_status(kernel_name, "idle")
		elseif data.message == "disconnected" then
			kernel_info.status = "disconnected"
			status.update_status(kernel_name, "disconnected")
			if kernel_info.ipykernel_job_id then
				vim.fn.jobstop(kernel_info.ipykernel_job_id)
				kernel_info.ipykernel_job_id = nil
			end
			kernels_config[kernel_name] = nil
			status.remove_kernel(kernel_name)
		end
	elseif msg_type == "iopub" and jupyter_msg.header.msg_type == "status" then
		local exec_state = jupyter_msg.content.execution_state
		kernel_info.status = exec_state
		status.update_status(kernel_name, exec_state)
		if exec_state == "idle" then
			kernel_info.current_execution_bufnr = nil
			kernel_info.current_execution_row = nil
		end
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
		elseif shell_msg_type == "shutdown_reply" then
			vim.notify("Kernel '" .. kernel_name .. "' riavviato con successo.", vim.log.levels.INFO)
			status.update_status(kernel_name, "idle")
		end
	elseif msg_type == "iopub" and kernel_info.current_execution_bufnr then
		local iopub_msg_type = jupyter_msg.header.msg_type
		local handler_name = output.iopub_handlers[iopub_msg_type]
		if handler_name then
			handler_name(kernel_info.current_execution_bufnr, kernel_info.current_execution_row, jupyter_msg)
		end
	end
end

function M.execute_cell(kernel_name, cell_content, bufnr, row)
	local kernel_info = kernels_config[kernel_name]
	if not kernel_info or not kernel_info.py_client_job_id then
		return
	end
	if kernel_info.status ~= "idle" then
		vim.notify("Kernel '" .. kernel_name .. "' è occupato.", vim.log.levels.WARN)
		return
	end

	kernel_info.current_execution_bufnr = bufnr
	kernel_info.current_execution_row = row
	status.update_status(kernel_name, "busy")

	M.send_to_py_client(kernel_name, {
		command = "execute",
		payload = message.create_execute_request(cell_content),
	})
end

function M.inspect(kernel_name, code, cursor_pos)
	M.send_to_py_client(kernel_name, {
		command = "inspect",
		payload = { content = message.create_inspect_request(code, cursor_pos).content },
	})
end

function M.interrupt(kernel_name)
	M.send_to_py_client(kernel_name, { command = "interrupt" })
end

--- CORREZIONE: Aggiunta del flag is_restarting ---
function M.restart(kernel_name)
	local kernel_info = kernels_config[kernel_name]
	if not kernel_info then
		return
	end

	-- Imposta un flag per indicare che il riavvio è intenzionale
	kernel_info.is_restarting = true
	status.update_status(kernel_name, "busy") -- Mostra uno stato di occupato

	M.send_to_py_client(kernel_name, { command = "restart" })
end

function M.history(kernel_name)
	M.send_to_py_client(kernel_name, {
		command = "history",
		payload = { content = message.create_history_request().content },
	})
end

function M.stop_python_client(kernel_name, reason)
	local kernel_info = kernels_config[kernel_name]
	if kernel_info and kernel_info.py_client_job_id then
		vim.notify(
			"Arresto del client Python per '" .. kernel_name .. "'. Motivo: " .. (reason or "richiesta utente"),
			vim.log.levels.INFO
		)
		kernel_info.status = "disconnecting"
		M.send_to_py_client(kernel_name, { command = "shutdown" })
		if kernel_info.ipykernel_job_id then
			vim.fn.jobstop(kernel_info.ipykernel_job_id)
			kernel_info.ipykernel_job_id = nil
		end
	end
end

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

function M.send_to_py_client(kernel_name, data_table)
	local kernel_info = kernels_config[kernel_name]
	if not kernel_info or not kernel_info.py_client_job_id then
		return
	end
	local json_data = vim.json.encode(data_table)
	vim.fn.jobsend(kernel_info.py_client_job_id, json_data .. "\n")
end

function M.list_running_kernels()
	local running = {}
	if not next(kernels_config) then
		return { "Nessun kernel gestito al momento." }
	end
	for name, info in pairs(kernels_config) do
		local status_line = string.format(
			"Kernel: %s, Stato: %s, IPYKernel Job ID: %s, PyClient Job ID: %s",
			name,
			info.status or "sconosciuto",
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
		if kernels_config and next(kernels_config) ~= nil then
			for name, _ in pairs(kernels_config) do
				M.stop_python_client(name, "Chiusura di Neovim")
			end
		end
	end,
})

return M
