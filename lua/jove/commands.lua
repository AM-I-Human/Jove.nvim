-- lua/jove/commands.lua

local M = {}
local config = require("jove")
local status = require("jove.status")

local kernel = require("jove.kernel")
local status = require("jove.status")

--- Ottiene il nome del kernel attivo per il buffer corrente.
local function get_active_kernel_name()
	local kernel_name = vim.b.jove_active_kernel
	if not kernel_name then
		vim.notify("Nessun kernel attivo. Avviare un kernel con :JoveStart <nome_kernel>", vim.log.levels.WARN)
		return nil
	end
	return kernel_name
end

--- Cerca di ottenere un kernel attivo. Se non ce n'è uno, ne avvia uno basato
--- sul filetype e poi esegue la callback.
local function run_with_kernel(callback)
	local active_kernel_name = vim.b.jove_active_kernel
	if active_kernel_name then
		-- Se il kernel è attivo e idle, esegui subito
		if status.get_status(active_kernel_name) == "idle" then
			callback(active_kernel_name)
		else
			vim.notify(
				"Kernel '"
					.. active_kernel_name
					.. "' non è pronto (stato: "
					.. (status.get_status(active_kernel_name) or "sconosciuto")
					.. ").",
				vim.log.levels.WARN
			)
		end
		return
	end

	-- Nessun kernel attivo per questo buffer, cerchiamone uno
	local filetype = vim.bo.filetype
	local kernels_config = config.get_config().kernels
	local found_kernel_name
	if kernels_config then
		for name, k_config in pairs(kernels_config) do
			if k_config and k_config.filetypes then
				for _, ft in ipairs(k_config.filetypes) do
					if ft == filetype then
						found_kernel_name = name
						break
					end
				end
			end
			if found_kernel_name then
				break
			end
		end
	end

	if found_kernel_name then
		vim.notify(
			"Nessun kernel attivo. Avvio di '" .. found_kernel_name .. "' per filetype '" .. filetype .. "'...",
			vim.log.levels.INFO
		)
		kernel.start(found_kernel_name, function(started_kernel_name)
			vim.b.jove_active_kernel = started_kernel_name
			status.set_active_kernel(started_kernel_name)
			vim.notify("Kernel '" .. started_kernel_name .. "' pronto. Esecuzione del comando.", vim.log.levels.INFO)
			callback(started_kernel_name)
		end)
	else
		vim.notify(
			"Nessun kernel attivo per il buffer e nessun kernel trovato per filetype '" .. filetype .. "'.",
			vim.log.levels.WARN
		)
	end
end

-- Comando per avviare un kernel
function M.start_kernel_cmd(args)
	local kernel_name = args.fargs[1]
	if not kernel_name or kernel_name == "" then
		vim.notify("Nome del kernel non specificato.", vim.log.levels.ERROR)
		return
	end

	local kernels_config = config.get_config().kernels
	if not kernels_config or not kernels_config[kernel_name] then
		local err_msg = "Configurazione non trovata per il kernel: " .. kernel_name
		vim.notify(err_msg, vim.log.levels.ERROR)
		return
	end

	kernel.start(kernel_name)
	vim.b.jove_active_kernel = kernel_name -- Use buffer-local variable
	status.set_active_kernel(kernel_name)
	vim.notify("Kernel '" .. kernel_name .. "' avviato per il buffer corrente.", vim.log.levels.INFO)
end

-- Comando per eseguire codice
function M.execute_code_cmd(args)
	run_with_kernel(function(active_kernel_name)
		local code_to_execute
		local bufnr = vim.api.nvim_get_current_buf()
		local start_row, end_row

		if args.range == 0 then -- Nessuna selezione visuale, esegui riga corrente
			start_row = vim.api.nvim_win_get_cursor(0)[1] - 1
			end_row = start_row
			code_to_execute = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)[1]
		else -- Selezione visuale
			start_row = args.line1 - 1
			end_row = args.line2 - 1
			local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row + 1, false)
			code_to_execute = table.concat(lines, "\n")
		end

		if code_to_execute and string.gsub(code_to_execute, "%s", "") ~= "" then
			kernel.execute_cell(active_kernel_name, code_to_execute, bufnr, start_row, end_row)
		else
			vim.notify("Nessun codice da eseguire.", vim.log.levels.INFO)
		end
	end)
end

-- Comando per ispezionare un oggetto
function M.inspect_cmd()
	run_with_kernel(function(active_kernel_name)
		local code = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
		local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
		local cursor_pos_bytes = vim.fn.line2byte(cursor_row) + cursor_col - 1

		kernel.inspect(active_kernel_name, code, cursor_pos_bytes)
	end)
end

-- Comando per interrompere il kernel
function M.interrupt_cmd()
	local active_kernel_name = get_active_kernel_name()
	if not active_kernel_name then
		return
	end
	vim.notify("Invio richiesta di interruzione al kernel '" .. active_kernel_name .. "'...", vim.log.levels.INFO)
	kernel.interrupt(active_kernel_name)
end

-- Comando per riavviare il kernel
function M.restart_cmd()
	local active_kernel_name = get_active_kernel_name()
	if not active_kernel_name then
		return
	end

	-- --- CORREZIONE: Usa vim.fn.confirm invece di vim.ui.confirm ---
	local question = "Sei sicuro di voler riavviare il kernel '" .. active_kernel_name .. "'? Lo stato verrà perso."
	local choices = "&Riavvia\n&Annulla"
	local choice = vim.fn.confirm(question, choices, 2)

	if choice == 1 then -- 1 corrisponde alla prima scelta ("Riavvia")
		vim.notify("Riavvio del kernel '" .. active_kernel_name .. "'...", vim.log.levels.INFO)
		kernel.restart(active_kernel_name)
	end
end

-- Comando per visualizzare la cronologia
function M.history_cmd()
	run_with_kernel(function(active_kernel_name)
		kernel.history(active_kernel_name)
	end)
end

-- Funzione per la statusline
function M.status_text()
	return status.get_status_text()
end

-- Comando per mostrare lo stato pulito dei kernel
function M.status_cmd()
	local status_lines = status.get_full_status()
	vim.notify("Stato dei kernel Jove:", vim.log.levels.INFO)
	for _, line in ipairs(status_lines) do
		vim.api.nvim_echo({ { line, "Normal" } }, false, {})
	end
end

-- Comando per elencare i kernel con informazioni di debug
function M.list_kernels_cmd()
	local kernel_list = kernel.list_running_kernels()
	if #kernel_list == 0 or (#kernel_list == 1 and kernel_list[1]:match("Nessun kernel")) then
		vim.notify("Nessun kernel Jove gestito.", vim.log.levels.INFO)
	else
		vim.notify("Kernel gestiti (info di debug):", vim.log.levels.INFO)
		for _, status_line in ipairs(kernel_list) do
			vim.api.nvim_echo({ { status_line, "Normal" } }, false, {})
		end
	end
end

-- =========================================================================
-- REGISTRAZIONE DEI COMANDI
-- =========================================================================

vim.api.nvim_create_user_command("JoveStart", M.start_kernel_cmd, {
	nargs = 1,
	complete = function(arglead)
		local kernels_config = config.get_config().kernels
		if kernels_config then
			local completions = {}
			for name, _ in pairs(kernels_config) do
				if string.sub(name, 1, #arglead) == arglead then
					table.insert(completions, name)
				end
			end
			return completions
		end
		return {}
	end,
	desc = "Avvia un kernel Jupyter specificato (es. python).",
})

vim.api.nvim_create_user_command("JoveExecute", M.execute_code_cmd, {
	range = "%",
	desc = "Esegue la riga corrente o la selezione visuale nel kernel attivo.",
})

vim.api.nvim_create_user_command("JoveStatus", M.status_cmd, {
	nargs = 0,
	desc = "Mostra lo stato di tutti i kernel Jove gestiti.",
})

vim.api.nvim_create_user_command("JoveList", M.list_kernels_cmd, {
	nargs = 0,
	desc = "Elenca i kernel gestiti con informazioni di debug (job ID, etc.).",
})

vim.api.nvim_create_user_command("JoveInspect", M.inspect_cmd, {
	nargs = 0,
	desc = "Ispeziona l'oggetto sotto il cursore nel kernel attivo.",
})

vim.api.nvim_create_user_command("JoveInterrupt", M.interrupt_cmd, {
	nargs = 0,
	desc = "Invia una richiesta di interruzione al kernel attivo.",
})

vim.api.nvim_create_user_command("JoveRestart", M.restart_cmd, {
	nargs = 0,
	desc = "Riavvia il kernel attivo.",
})

vim.api.nvim_create_user_command("JoveHistory", M.history_cmd, {
	nargs = 0,
	desc = "Mostra la cronologia di esecuzione del kernel attivo.",
})

return M
