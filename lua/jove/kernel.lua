-- lua/jove/kernel.lua

local status = require("jove.status")
local M = {}

local kernels = {} -- Memorizza lo stato dei client Python per ogni kernel

function M.start(kernel_name)
	if kernels[kernel_name] and kernels[kernel_name].py_client_job_id then
		vim.notify("Kernel client for '" .. kernel_name .. "' is already running or starting.", vim.log.levels.WARN)
		return
	end

	local kernel_config = vim.g.jove_kernels[kernel_name] or {}
	local ipykernel_cmd_template = kernel_config.cmd
	if not ipykernel_cmd_template then
		vim.notify(
			"Comando per avviare il kernel non trovato nella configurazione per: " .. kernel_name,
			vim.log.levels.ERROR
		)
		return
	end

	local connection_file = vim.fn.tempname() .. ".json"
	local ipykernel_cmd = string.gsub(ipykernel_cmd_template, "{connection_file}", connection_file)

	vim.notify("Avvio del processo ipykernel: " .. ipykernel_cmd, vim.log.levels.INFO)

	-- Avvia il processo ipykernel (es. python -m ipykernel_launcher ...)
	local ipykernel_job_id = vim.fn.jobstart(ipykernel_cmd, {
		on_stdout = function(_, data, _)
			if data then
				vim.notify(
					"ipykernel stdout (" .. kernel_name .. "): " .. table.concat(data, "\n"),
					vim.log.levels.INFO
				)
			end
		end,
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
			if kernels[kernel_name] and kernels[kernel_name].py_client_job_id then
				M.stop_python_client(kernel_name, "Il processo ipykernel è terminato.")
			end
			kernels[kernel_name] = nil
			status.remove_kernel(kernel_name)
		end,
	})

	if ipykernel_job_id == 0 or ipykernel_job_id == -1 then
		vim.notify("Errore nell'avvio del processo ipykernel per: " .. kernel_name, vim.log.levels.ERROR)
		return
	end
	vim.notify(
		"Processo ipykernel per '" .. kernel_name .. "' avviato (job ID: " .. ipykernel_job_id .. ")",
		vim.log.levels.INFO
	)

	-- Attendi che il file di connessione sia creato da ipykernel
	vim.defer_fn(function()
		local connection_info = M.parse_connection_file(connection_file)
		if connection_info then
			vim.notify("File di connessione per '" .. kernel_name .. "' letto con successo.", vim.log.levels.INFO)
			M.start_python_client(kernel_name, connection_file, ipykernel_job_id)
		else
			vim.notify(
				"Fallimento nel leggere il file di connessione per: "
					.. kernel_name
					.. ". Il processo ipykernel potrebbe essere fallito.",
				vim.log.levels.ERROR
			)
			vim.fn.jobstop(ipykernel_job_id) -- Ferma il processo ipykernel se non possiamo connetterci
			kernels[kernel_name] = nil
		end
	end, 3000)

	status.update_status(kernel_name, "starting")
end

function M.start_python_client(kernel_name, connection_file_path, ipykernel_job_id_ref)
	vim.notify(
		"[DebugKernel] M.start_python_client: Inizio. Valore di vim.g.jove_plugin_root = '"
			.. vim.inspect(vim.g.jove_plugin_root)
			.. "'",
		vim.log.levels.INFO
	)

	if not vim.g.jove_plugin_root or vim.g.jove_plugin_root == "" then
		vim.notify(
			"ERRORE KERNEL: Percorso radice del plugin (vim.g.jove_plugin_root) non impostato o vuoto. Impossibile avviare py_kernel_client.py.",
			vim.log.levels.ERROR
		)
		vim.fn.jobstop(ipykernel_job_id_ref)
		kernels[kernel_name] = nil
		return
	end

	local py_client_script = vim.g.jove_plugin_root .. "/python/py_kernel_client.py"
	-- Assicurati che lo script esista
	if vim.fn.filereadable(py_client_script) == 0 then
		vim.notify(
			"Script Python client non trovato o non leggibile: "
				.. py_client_script
				.. " (Plugin root: "
				.. vim.g.jove_plugin_root
				.. ")",
			vim.log.levels.ERROR
		)
		vim.fn.jobstop(ipykernel_job_id_ref)
		kernels[kernel_name] = nil
		return
	end

	-- Comando per avviare lo script Python. Assicurati che 'python' sia nel PATH.
	-- Potrebbe essere necessario renderlo configurabile (python, python3, etc.)
	local python_executable = "python" -- Default
	if vim.g.jove_kernels and vim.g.jove_kernels[kernel_name] and vim.g.jove_kernels[kernel_name].python_executable then
		python_executable = vim.g.jove_kernels[kernel_name].python_executable
	elseif
		vim.g.jove_kernels
		and vim.g.jove_kernels.python -- fallback al kernel 'python' globale se esiste
		and vim.g.jove_kernels.python.python_executable
	then
		python_executable = vim.g.jove_kernels.python.python_executable
	end
	vim.notify("Eseguibile Python per il client: " .. python_executable, vim.log.levels.INFO)

	local py_client_cmd = { python_executable, "-u", py_client_script, connection_file_path }

	vim.notify("Comando avvio client Python: " .. table.concat(py_client_cmd, " "), vim.log.levels.INFO)

	kernels[kernel_name] = {
		status = "starting_py_client",
		ipykernel_job_id = ipykernel_job_id_ref,
		connection_file = connection_file_path,
		py_client_job_id = nil, -- Sarà impostato da jobstart
		current_execution_bufnr = nil,
		current_execution_row = nil,
	}

	local py_job_id = vim.fn.jobstart(py_client_cmd, {

		stdin = "pipe", -- <<< TRY ADDING THIS LINE
		rpc = false, -- Stiamo usando stdio per JSON, non RPC di Neovim
		pty = false, -- Non necessario per stdio
		on_stdout = function(job_id, data, event)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						-- Schedule the handler to avoid blocking the event loop
						vim.schedule(function()
							M.handle_py_client_message(kernel_name, line)
						end)
					end
				end
			end
		end,
		on_stderr = function(job_id, data, event)
			vim.notify(
				"Python client stderr (" .. kernel_name .. "): " .. table.concat(data, "\n"),
				vim.log.levels.ERROR
			)
		end,
		on_exit = function(job_id, exit_code, event)
			local kernel_entry = kernels[kernel_name]
			local msg = "Client Python per '" .. kernel_name .. "' terminato con codice: " .. exit_code
			if kernel_entry and kernel_entry.status ~= "disconnecting" then
				vim.notify(msg, vim.log.levels.WARN)
			else
				vim.notify(msg, vim.log.levels.INFO)
			end

			if kernel_entry then
				kernel_entry.py_client_job_id = nil
				kernel_entry.status = "disconnected"
				status.update_status(kernel_name, "disconnected")
				-- Non fermare ipykernel qui, potrebbe essere ancora utilizzabile o gestito separatamente
			end
		end,
	})

	if py_job_id == 0 or py_job_id == -1 then
		vim.notify("Errore nell'avvio del client Python per: " .. kernel_name, vim.log.levels.ERROR)
		kernels[kernel_name] = nil -- Pulizia
		vim.fn.jobstop(ipykernel_job_id_ref) -- Ferma anche ipykernel
		return
	end

	kernels[kernel_name].py_client_job_id = py_job_id
	kernels[kernel_name].status = "connecting_py_client"
	vim.notify("Client Python per '" .. kernel_name .. "' avviato (Job ID: " .. py_job_id .. ")", vim.log.levels.INFO)
end

function M.stop_python_client(kernel_name, reason)
	local kernel_info = kernels[kernel_name]
	if kernel_info and kernel_info.py_client_job_id then
		vim.notify(
			"Arresto del client Python per '" .. kernel_name .. "'. Motivo: " .. (reason or "richiesta utente"),
			vim.log.levels.INFO
		)
		kernel_info.status = "disconnecting"
		-- Invia un comando di shutdown allo script Python
		M.send_to_py_client(kernel_name, { command = "shutdown" })
		-- vim.fn.jobstop(kernel_info.py_client_job_id) -- Lo script dovrebbe terminare da solo
		-- Se anche ipykernel deve essere fermato, gestiscilo qui o in on_exit di py_client
		if kernel_info.ipykernel_job_id then
			vim.fn.jobstop(kernel_info.ipykernel_job_id)
			kernel_info.ipykernel_job_id = nil
		end
		-- kernels[kernel_name] = nil -- Verrà pulito in on_exit del client Python
	end
end

function M.parse_connection_file(filename)
	local file = io.open(filename, "r")
	if not file then
		vim.notify("Impossibile aprire il file di connessione: " .. filename, vim.log.levels.ERROR)
		return nil
	end
	local content = file:read("*all")
	file:close()
	-- Tentativo di rimuovere il file di connessione dopo averlo letto, ma potrebbe essere prematuro
	-- pcall(vim.loop.fs_unlink, filename)

	local ok, result = pcall(vim.json.decode, content)
	if ok then
		return result
	else
		vim.notify(
			"Impossibile decodificare JSON dal file di connessione: "
				.. filename
				.. "\nErrore: "
				.. result
				.. "\nContenuto grezzo: "
				.. content,
			vim.log.levels.ERROR
		)
		return nil
	end
end

function M.send_to_py_client(kernel_name, data_table)
	local kernel_info = kernels[kernel_name]
	if not kernel_info or not kernel_info.py_client_job_id then
		vim.notify(
			"Client Python per '" .. kernel_name .. "' non in esecuzione o job ID non trovato.",
			vim.log.levels.WARN
		)
		return
	end

	local json_data = vim.json.encode(data_table)
	-- vim.notify("Invio a PyClient ("..kernel_name.."): " .. json_data, vim.log.levels.DEBUG)
	--
	--
	--    -- >>>>>>>> ADD THIS DEBUG LINE <<<<<<<<<<
	local payload_to_send = json_data .. "\n"
	vim.notify("[LUA DEBUG] Sending to stdin: " .. vim.inspect(payload_to_send), vim.log.levels.WARN)
	-- >>>>>>>> END OF ADDED DEBUG LINE <<<<<<<<<<
	vim.fn.jobsend(kernel_info.py_client_job_id, json_data .. "\n")
end

-- Gestisce i messaggi JSON ricevuti da stdout dello script Python
function M.handle_py_client_message(kernel_name, json_line)
	local kernel_info = kernels[kernel_name]
	if not kernel_info then
		return
	end -- Il kernel potrebbe essere stato fermato

	local ok, data = pcall(vim.json.decode, json_line)
	if not ok then
		vim.notify(
			"Errore nel decodificare JSON da Python client (" .. kernel_name .. "): " .. json_line,
			vim.log.levels.ERROR
		)
		return
	end

	local data_type = data.type
	local jupyter_msg = data.message

	-- Log generico per qualsiasi messaggio ricevuto da python
	vim.notify("PyClient (" .. kernel_name .. ") sent: " .. data_type, vim.log.levels.DEBUG)

	if data_type == "status" then
		vim.notify("Stato client Python (" .. kernel_name .. "): " .. data.message, vim.log.levels.INFO)
		if data.message == "connected" then
			kernel_info.status = "idle"
			status.update_status(kernel_name, "idle")
			kernel_info.py_kernel_connection_info = data.kernel_info -- Salva le info del kernel passate da python
		elseif data.message == "disconnected" then
			kernel_info.status = "disconnected"
			status.update_status(kernel_name, "disconnected")
			-- Potremmo voler fermare anche il processo ipykernel qui se non è già terminato
			if kernel_info.ipykernel_job_id then
				vim.fn.jobstop(kernel_info.ipykernel_job_id)
				kernel_info.ipykernel_job_id = nil
			end
			kernels[kernel_name] = nil
			status.remove_kernel(kernel_name)
		end
	elseif data_type == "shell" then
		if jupyter_msg.header.msg_type == "execute_reply" and jupyter_msg.content.status == "error" then
			vim.notify("Shell reply indicates an error occurred.", vim.log.levels.WARN)
		end
	elseif data_type == "iopub" then
		local msg_type = jupyter_msg.header.msg_type
		vim.notify("IOPub message received: " .. msg_type, vim.log.levels.DEBUG)
		status.update_status(kernel_name, exec_state)

		if msg_type == "status" then
			local exec_state = jupyter_msg.content.execution_state
			vim.notify("Kernel status is now: " .. exec_state, vim.log.levels.INFO)
			kernel_info.status = exec_state -- Directly set the status ('busy', 'idle', etc.)

			-- If the kernel is now idle, clear the execution context
			if exec_state == "idle" then
				kernel_info.current_execution_bufnr = nil
				kernel_info.current_execution_row = nil
			end
		elseif msg_type == "execute_input" then
			if kernel_info.current_execution_bufnr then
				require("jove.output").render_input_prompt(
					kernel_info.current_execution_bufnr,
					kernel_info.current_execution_row,
					jupyter_msg
				)
			end
		elseif msg_type == "stream" then
			if kernel_info.current_execution_bufnr then
				require("jove.output").render_stream(
					kernel_info.current_execution_bufnr,
					kernel_info.current_execution_row,
					jupyter_msg
				)
			end
		elseif msg_type == "execute_result" then
			if kernel_info.current_execution_bufnr then
				require("jove.output").render_execute_result(
					kernel_info.current_execution_bufnr,
					kernel_info.current_execution_row,
					jupyter_msg
				)
			end
		elseif msg_type == "display_data" then
			if kernel_info.current_execution_bufnr and jupyter_msg.content.data["text/plain"] then
				require("jove.output").render_execute_result(
					kernel_info.current_execution_bufnr,
					kernel_info.current_execution_row,
					jupyter_msg
				)
			end
		elseif msg_type == "error" then
			if kernel_info.current_execution_bufnr then
				require("jove.output").render_error(
					kernel_info.current_execution_bufnr,
					kernel_info.current_execution_row,
					jupyter_msg
				)
			end
		end
	elseif data_type == "error" then
		vim.notify("Errore dal client Python (" .. kernel_name .. "): " .. data.message, vim.log.levels.ERROR)
	else
		vim.notify(
			"Messaggio sconosciuto dal client Python (" .. kernel_name .. "): " .. vim.inspect(data),
			vim.log.levels.WARN
		)
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
			"Kernel '"
				.. kernel_name
				.. "' (tramite client Python) non è idle (stato: "
				.. kernel_info.status
				.. "). Attendere.",
			vim.log.levels.WARN
		)
		return
	end

	local jupyter_msg_payload = require("jove.message").create_execute_request(cell_content)

	kernel_info.current_execution_bufnr = bufnr
	kernel_info.current_execution_row = row
	kernel_info.status = "busy"
	status.update_status(kernel_name, "busy")

	M.send_to_py_client(kernel_name, {
		command = "execute",
		payload = jupyter_msg_payload,
	})
	vim.notify("Richiesta di esecuzione inviata al client Python per '" .. kernel_name .. "'.", vim.log.levels.INFO)
end

function M.list_running_kernels()
	local running = {}
	if next(kernels) == nil then
		return { "Nessun kernel gestito al momento." }
	end
	for name, info in pairs(kernels) do
		local status_line = string.format(
			"Kernel: %s, Stato: %s, IPYKernel Job ID: %s, PyClient Job ID: %s",
			name,
			info.status or "sconosciuto",
			info.ipykernel_job_id or "N/A",
			info.py_client_job_id or "N/A"
		)
		table.insert(running, status_line)
	end
	return running
end

return M
