-- file: lua/jove/kernel.lua

local status = require("jove.status") -- Importa il modulo di stato

local M = {}
local config = require("jove").get_config()
local kernels = config.kernels

function M.start(kernel_name)
	if kernels[kernel_name] and kernels[kernel_name].py_client_job_id then
		vim.notify("Kernel client for '" .. kernel_name .. "' is already running or starting.", vim.log.levels.WARN)
		return
	end

	status.update_status(kernel_name, "starting") -- Stato: in avvio

	local kernel_config = kernels[kernel_name]
	local python_exec = kernel_config.python_executable or vim.g.jove_default_python or "python"
	local connection_file = vim.fn.tempname() .. ".json"

	local ipykernel_cmd = string.gsub(kernel_config.cmd, "{python_executable}", python_exec)
	ipykernel_cmd = string.gsub(ipykernel_cmd, "{connection_file}", connection_file)
	local ipykernel_cmd = string.gsub(ipykernel_cmd_template, "{connection_file}", connection_file)

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
			if kernels[kernel_name] then
				M.stop_python_client(kernel_name, "Il processo ipykernel è terminato.")
				kernels[kernel_name] = nil
			end
			status.remove_kernel(kernel_name) -- Rimuovi dallo stato
		end,
	})

	if ipykernel_job_id <= 0 then
		vim.notify("Errore nell'avvio del processo ipykernel per: " .. kernel_name, vim.log.levels.ERROR)
		status.update_status(kernel_name, "error")
		return
	end

	local poll_interval_ms = 100
	local timeout_ms = 10000 -- Wait for a maximum of 10 seconds
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

		-- Check if file exists and is readable
		if vim.fn.filereadable(connection_file) == 1 then
			-- Optional: Check if file has content, as it might be created empty first
			local content = vim.fn.readfile(connection_file)
			if content and #content > 0 then
				local connection_info = M.parse_connection_file(connection_file)
				if connection_info then
					vim.notify("[Jove] File di connessione trovato, avvio del client Python.", vim.log.levels.INFO)
					M.start_python_client(kernel_name, connection_file, ipykernel_job_id)
				else
					vim.notify(
						"[Jove] Fallimento nel parsare il file di connessione, anche se esistente.",
						vim.log.levels.ERROR
					)
					vim.fn.jobstop(ipykernel_job_id)
					status.update_status(kernel_name, "error")
				end
				return -- Stop polling
			end
		end

		-- If not ready, schedule the next check
		vim.defer_fn(poll_for_connection_file, poll_interval_ms)
	end

	-- Start the first poll check
	vim.defer_fn(poll_for_connection_file, poll_interval_ms)
end

function M.start_python_client(kernel_name, connection_file_path, ipykernel_job_id_ref)
	if not vim.g.jove_plugin_root or vim.g.jove_plugin_root == "" then
		vim.notify("ERRORE KERNEL: vim.g.jove_plugin_root non impostato.", vim.log.levels.ERROR)
		vim.fn.jobstop(ipykernel_job_id_ref)
		status.update_status(kernel_name, "error")
		return
	end

	local py_client_script = vim.g.jove_plugin_root .. "/python/py_kernel_client.py"
	if vim.fn.filereadable(py_client_script) == 0 then
		vim.notify("Script Python client non trovato: " .. py_client_script, vim.log.levels.ERROR)
		vim.fn.jobstop(ipykernel_job_id_ref)
		status.update_status(kernel_name, "error")
		return
	end

	local python_executable = (kernels[kernel_name] or {}).python_executable or "python"
	local py_client_cmd = { python_executable, "-u", py_client_script, connection_file_path }

	kernels[kernel_name] = {
		status = "starting_py_client",
		ipykernel_job_id = ipykernel_job_id_ref,
		py_client_job_id = nil,
	}

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
			local kernel_entry = kernels[kernel_name]
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

	if py_job_id <= 0 then
		vim.notify("Errore nell'avvio del client Python per: " .. kernel_name, vim.log.levels.ERROR)
		kernels[kernel_name] = nil
		vim.fn.jobstop(ipykernel_job_id_ref)
		status.update_status(kernel_name, "error")
		return
	end

	kernels[kernel_name].py_client_job_id = py_job_id
end

function M.handle_py_client_message(kernel_name, json_line)
	local kernel_info = kernels[kernel_name]
	if not kernel_info then
		return
	end

	local ok, data = pcall(vim.json.decode, json_line)
	if not ok then
		vim.notify("Errore JSON da Python (" .. kernel_name .. "): " .. json_line, vim.log.levels.ERROR)
		return
	end

	if data.type == "status" then
		if data.message == "connected" then
			kernel_info.status = "idle"
			status.update_status(kernel_name, "idle") -- Stato: idle
		elseif data.message == "disconnected" then
			kernel_info.status = "disconnected"
			status.update_status(kernel_name, "disconnected")
			if kernel_info.ipykernel_job_id then
				vim.fn.jobstop(kernel_info.ipykernel_job_id)
				kernel_info.ipykernel_job_id = nil
			end
			kernels[kernel_name] = nil
			status.remove_kernel(kernel_name)
		end
	elseif data.type == "iopub" and data.message.header.msg_type == "status" then
		local exec_state = data.message.content.execution_state -- 'busy' o 'idle'
		kernel_info.status = exec_state
		status.update_status(kernel_name, exec_state) -- Aggiorna lo stato
		if exec_state == "idle" then
			kernel_info.current_execution_bufnr = nil
			kernel_info.current_execution_row = nil
		end
	elseif data.type == "error" then
		vim.notify("Errore dal client Python (" .. kernel_name .. "): " .. data.message, vim.log.levels.ERROR)
		status.update_status(kernel_name, "error")
	else
		-- Gestione altri messaggi (output, etc.)
		local handlers = {
			execute_input = "render_input_prompt",
			stream = "render_stream",
			execute_result = "render_execute_result",
			display_data = "render_execute_result",
			error = "render_error",
		}
		if data.type == "iopub" and kernel_info.current_execution_bufnr then
			local msg_type = data.message.header.msg_type
			local handler_name = handlers[msg_type]
			if handler_name then
				require("jove.output")[handler_name](
					kernel_info.current_execution_bufnr,
					kernel_info.current_execution_row,
					data.message
				)
			end
		end
	end
end

function M.execute_cell(kernel_name, cell_content, bufnr, row)
	local kernel_info = kernels[kernel_name]
	if not kernel_info or not kernel_info.py_client_job_id then
		vim.notify("Client Python per '" .. kernel_name .. "' non attivo.", vim.log.levels.WARN)
		return
	end
	if kernel_info.status ~= "idle" then
		vim.notify(
			"Kernel '" .. kernel_name .. "' è occupato (stato: " .. kernel_info.status .. ").",
			vim.log.levels.WARN
		)
		return
	end

	kernel_info.current_execution_bufnr = bufnr
	kernel_info.current_execution_row = row
	kernel_info.status = "busy"
	status.update_status(kernel_name, "busy") -- Stato: busy

	M.send_to_py_client(kernel_name, {
		command = "execute",
		payload = require("jove.message").create_execute_request(cell_content),
	})
end

-- Funzioni di utility non modificate (parse_connection_file, send_to_py_client, etc.)
function M.stop_python_client(kernel_name, reason)
	local kernel_info = kernels[kernel_name]
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
	local kernel_info = kernels[kernel_name]
	if not kernel_info or not kernel_info.py_client_job_id then
		return
	end
	local json_data = vim.json.encode(data_table)
	vim.fn.jobsend(kernel_info.py_client_job_id, json_data .. "\n")
end

function M.list_running_kernels()
	local running = {}
	if not next(kernels) then
		return { "Nessun kernel gestito al momento." }
	end
	for name, info in pairs(kernels) do
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
		vim.notify("[Jove] Chiusura di Neovim, arresto di tutti i kernel...", vim.log.levels.INFO)
		if kernels and next(kernels) ~= nil then
			for name, _ in pairs(kernels) do
				M.stop_python_client(name, "Chiusura di Neovim")
			end
		end
	end,
})

return M
