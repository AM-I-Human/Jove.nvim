local kernel = require("jove.kernel")
-- local util = require("jove.util") -- Non ancora utilizzato, ma potrebbe servire in futuro

local M = {}

local active_kernel_name = nil -- Traccia il nome del kernel attualmente attivo

-- Comando per avviare un kernel
-- Prende il nome del kernel come argomento
function M.start_kernel_cmd(args)
	local kernel_name = args.fargs[1]
	if not kernel_name or kernel_name == "" then
		vim.notify("Nome del kernel non specificato.", vim.log.levels.ERROR)
		vim.api.nvim_err_writeln("Errore: specificare un nome per il kernel. Esempio: :JoveStart python")
		return
	end

	-- Verifica se il kernel_name esiste nella configurazione globale
	if not vim.g.jove_kernels or not vim.g.jove_kernels[kernel_name] then
		local err_msg = "Configurazione non trovata per il kernel: "
			.. kernel_name
			.. ". Verificare vim.g.jove_kernels."
		vim.notify(err_msg, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln("Errore: " .. err_msg)
		return
	end

	kernel.start(kernel_name)
	active_kernel_name = kernel_name -- Imposta questo come kernel attivo
	vim.notify("Avvio del kernel '" .. kernel_name .. "' richiesto.", vim.log.levels.INFO)
end

-- Comando per eseguire codice
-- Usa il kernel attivo
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
		-- Passa il bufnr e la riga iniziale della selezione/cursore a kernel.execute_cell
		-- La riga è 0-indexed per le API, ma args.line1/cursor[1] sono 1-indexed
		local bufnr = vim.api.nvim_get_current_buf()
		local row
		if args.range == 0 then
			row = vim.api.nvim_win_get_cursor(0)[1] - 1
		else
			row = args.line1 - 1
		end
		kernel.execute_cell(active_kernel_name, code_to_execute, bufnr, row)
	else
		vim.notify("Nessun codice da eseguire.", vim.log.levels.INFO)
	end
end

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

vim.api.nvim_create_user_command("JoveExecute", M.execute_code_cmd, {
	range = "%", -- Consente di gestire sia la riga corrente (senza range) sia un range (selezione visuale)
	desc = "Esegue la riga corrente o la selezione visuale nel kernel attivo.",
})

function M.list_kernels_cmd()
	local kernel_list = kernel.list_running_kernels()
	if #kernel_list == 0 then
		vim.notify("Nessun kernel attualmente in esecuzione o gestito.", vim.log.levels.INFO)
	else
		vim.notify("Kernel gestiti:", vim.log.levels.INFO)
		for _, status_line in ipairs(kernel_list) do
			vim.api.nvim_echo({ { status_line, "Normal" } }, false, {})
		end
	end
end

vim.api.nvim_create_user_command("JoveList", M.list_kernels_cmd, {
	nargs = 0,
	desc = "Elenca i kernel attualmente gestiti e il loro stato.",
})

return M
