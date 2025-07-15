-- lua/jove/commands.lua

local kernel = require("jove.kernel")
local status = require("jove.status")
-- local util = require("jove.util") -- Non ancora utilizzato, ma potrebbe servire in futuro

local M = {}

local active_kernel_name = nil -- Traccia il nome del kernel attualmente attivo

-- Comando per avviare un kernel
function M.start_kernel_cmd(args)
	local kernel_name = args.fargs[1]
	if not kernel_name or kernel_name == "" then
		vim.notify("Nome del kernel non specificato.", vim.log.levels.ERROR)
		vim.api.nvim_err_writeln("Errore: specificare un nome per il kernel. Esempio: :JoveStart python")
		return
	end

	if not vim.g.jove_kernels or not vim.g.jove_kernels[kernel_name] then
		local err_msg = "Configurazione non trovata per il kernel: "
			.. kernel_name
			.. ". Verificare vim.g.jove_kernels."
		vim.notify(err_msg, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln("Errore: " .. err_msg)
		return
	end

	kernel.start(kernel_name)
	active_kernel_name = kernel_name
	status.set_active_kernel(kernel_name) -- Notifica al modulo di stato
	vim.notify("Avvio del kernel '" .. kernel_name .. "' richiesto.", vim.log.levels.INFO)
end

-- Comando per eseguire codice
function M.execute_code_cmd(args)
	if not active_kernel_name then
		vim.notify("Nessun kernel attivo. Avviare un kernel con :JoveStart <nome_kernel>", vim.log.levels.WARN)
		return
	end

	local code_to_execute
	if args.range == 0 then -- Nessuna selezione visuale, esegui riga corrente
		local current_line_nr = vim.api.nvim_win_get_cursor(0)[1]
		code_to_execute = vim.api.nvim_buf_get_lines(0, current_line_nr - 1, current_line_nr, false)[1]
	else -- Selezione visuale
		local first_line = args.line1
		local last_line = args.line2
		local lines = vim.api.nvim_buf_get_lines(0, first_line - 1, last_line, false)
		code_to_execute = table.concat(lines, "\n")
	end

	if code_to_execute and string.gsub(code_to_execute, "%s", "") ~= "" then
		local bufnr = vim.api.nvim_get_current_buf()
		local row = (args.range == 0) and (vim.api.nvim_win_get_cursor(0)[1] - 1) or (args.line1 - 1)
		kernel.execute_cell(active_kernel_name, code_to_execute, bufnr, row)
	else
		vim.notify("Nessun codice da eseguire.", vim.log.levels.INFO)
	end
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
	complete = function(arglead, cmdline, cursorpos)
		if vim.g.jove_kernels then
			local completions = {}
			for name, _ in pairs(vim.g.jove_kernels) do
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

if vim.g.jove_kernels == nil then
	vim.g.jove_kernels = {
		python = {
			cmd = "python -m ipykernel_launcher -f {connection_file}",
			-- python_executable = "python" -- L'utente può sovrascrivere per specificare python3, etc.
		},
	}
	-- vim.notify("[Jove] Configurazione kernel di default impostata.", vim.log.levels.INFO)
end

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

return M
