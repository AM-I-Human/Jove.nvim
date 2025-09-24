-- lua/jove/commands.lua
--
local M = {}
local config = require("jove")
local kernel = require("jove.kernel")
local status = require("jove.status")
local log = require("jove.log")

--- Ottiene il nome del kernel attivo per il buffer corrente.
local function get_active_kernel_name()
	local kernel_name = vim.b.jove_active_kernel
	if not kernel_name then
		log.add(vim.log.levels.WARN, "Nessun kernel attivo. Avviare un kernel con :JoveStart <nome_kernel>")
		return nil
	end
	return kernel_name
end

--- Trova un kernel in base al linguaggio specificato (es. da un blocco di codice markdown).
local function find_kernel_by_language(language)
	local kernels_config = config.get_config().kernels
	if kernels_config then
		for name, k_config in pairs(kernels_config) do
			if k_config and k_config.languages then
				for _, lang in ipairs(k_config.languages) do
					if lang == language then
						return name
					end
				end
			end
		end
	end
	return nil
end

--- Trova i limiti di un blocco di codice markdown e il suo linguaggio.
local function find_markdown_cell_boundaries(bufnr, cursor_row)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local fence_pattern = "^%s*```"
	local start_fence_pattern = "^%s*```([%w_.-]+)"

	local prev_fence = -1
	for i = cursor_row, 0, -1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(fence_pattern) then
			prev_fence = i
			break
		end
	end

	if prev_fence == -1 then
		return nil
	end

	local line = vim.api.nvim_buf_get_lines(bufnr, prev_fence, prev_fence + 1, false)[1] or ""
	local language = line:match(start_fence_pattern)
	-- Se la riga precedente è una fence ma senza linguaggio, non è un inizio di cella eseguibile
	if not language then
		return nil
	end

	local next_fence = -1
	for i = cursor_row + 1, line_count - 1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(fence_pattern) then
			next_fence = i
			break
		end
	end

	if next_fence == -1 then
		return nil
	end

	local start_cell = prev_fence + 1
	local end_cell = next_fence - 1

	if start_cell > end_cell then
		return nil -- Cella vuota
	end

	return start_cell, end_cell, language
end

--- Trova i limiti della cella Jupytext corrente basata su marcatori '# %%'.
local function find_current_cell_boundaries(bufnr, cursor_row)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local cell_marker_pattern = "^#%s*%%%%"

	-- Cerca all'indietro dal cursore per trovare il marcatore di inizio della cella corrente
	local start_marker_row = -1
	for i = cursor_row, 0, -1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(cell_marker_pattern) then
			start_marker_row = i
			break
		end
	end

	local cell_start_row = start_marker_row + 1

	-- Cerca in avanti da dopo il marcatore di inizio per trovare il marcatore di fine
	local end_marker_row = -1
	-- Inizia la ricerca dalla riga DOPO il marcatore di inizio
	for i = cell_start_row, line_count - 1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(cell_marker_pattern) then
			end_marker_row = i
			break
		end
	end

	local cell_end_row
	if end_marker_row ~= -1 then
		cell_end_row = end_marker_row - 1
	else
		cell_end_row = line_count - 1
	end

	-- Se la cella è vuota (es. cursore su un marcatore seguito immediatamente da un altro o da EOF)
	if cell_start_row > cell_end_row then
		return nil, nil
	end

	return cell_start_row, cell_end_row
end

--- Cerca il marcatore di cella Jupytext successivo o precedente.
-- @param bufnr (integer) Il numero del buffer.
-- @param start_row (integer) La riga da cui iniziare la ricerca (0-indexed).
-- @param direction (integer) `1` per cercare in avanti, `-1` per cercare indietro.
-- @return (integer|nil) La riga (0-indexed) del marcatore trovato, o nil.
local function find_cell_marker(bufnr, start_row, direction)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local cell_marker_pattern = "^#%s*%%%%"
	local search_start, search_end, step

	if direction > 0 then
		search_start = start_row + 1
		search_end = line_count - 1
		step = 1
	else
		search_start = start_row - 1
		search_end = 0
		step = -1
	end

	for i = search_start, search_end, step do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(cell_marker_pattern) then
			return i
		end
	end

	return nil
end

--- Cerca di ottenere un kernel attivo. Se non ce n'è uno, ne avvia uno basato
--- sul filetype e poi esegue la callback.
--- @param callback (function) La funzione da eseguire con il nome del kernel.
--- @param kernel_name_override (string|nil) Se fornito, forza l'uso di questo kernel.
local function run_with_kernel(callback, kernel_name_override)
	local active_kernel_name = kernel_name_override or vim.b.jove_active_kernel
	if active_kernel_name then
		if status.get_status(active_kernel_name) == "idle" then
			callback(active_kernel_name)
		elseif not status.get_status(active_kernel_name) then -- Non in esecuzione o in avvio
			log.add(vim.log.levels.INFO, "Avvio del kernel richiesto: '" .. active_kernel_name .. "'...")
			kernel.start(active_kernel_name, function(started_kernel_name)
				if not kernel_name_override then
					vim.b.jove_active_kernel = started_kernel_name
					status.set_active_kernel(started_kernel_name)
				end
				log.add(vim.log.levels.INFO, "Kernel '" .. started_kernel_name .. "' pronto. Esecuzione del comando.")
				callback(started_kernel_name)
			end)
		else
			log.add(
				vim.log.levels.WARN,
				"Kernel '"
					.. active_kernel_name
					.. "' non è pronto (stato: "
					.. (status.get_status(active_kernel_name) or "sconosciuto")
					.. ")."
			)
		end
		return
	end

	-- Nessun kernel attivo per questo buffer e nessun override, cerchiamone uno
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
		log.add(
			vim.log.levels.INFO,
			"Nessun kernel attivo. Avvio di '" .. found_kernel_name .. "' per filetype '" .. filetype .. "'..."
		)
		kernel.start(found_kernel_name, function(started_kernel_name)
			vim.b.jove_active_kernel = started_kernel_name
			status.set_active_kernel(started_kernel_name)
			log.add(vim.log.levels.INFO, "Kernel '" .. started_kernel_name .. "' pronto. Esecuzione del comando.")
			callback(started_kernel_name)
		end)
	else
		log.add(
			vim.log.levels.WARN,
			"Nessun kernel attivo per il buffer e nessun kernel trovato per filetype '" .. filetype .. "'."
		)
	end
end

-- Comando per avviare un kernel
function M.start_kernel_cmd(args)
	local kernel_name = args.fargs[1]
	if not kernel_name or kernel_name == "" then
		log.add(vim.log.levels.ERROR, "Nome del kernel non specificato.")
		return
	end

	local kernels_config = config.get_config().kernels
	if not kernels_config or not kernels_config[kernel_name] then
		local err_msg = "Configurazione non trovata per il kernel: " .. kernel_name
		log.add(vim.log.levels.ERROR, err_msg)
		return
	end

	kernel.start(kernel_name)
	vim.b.jove_active_kernel = kernel_name -- Use buffer-local variable
	status.set_active_kernel(kernel_name)
	log.add(vim.log.levels.INFO, "Kernel '" .. kernel_name .. "' avviato per il buffer corrente.")
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
			log.add(vim.log.levels.INFO, "Nessun codice da eseguire.")
		end
	end)
end

-- Comando per eseguire una cella (Jupytext o Markdown)
function M.execute_jupytext_cell_cmd()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
	local filetype = vim.bo.filetype

	local start_row, end_row, language
	local kernel_name_override

	if filetype == "markdown" then
		start_row, end_row, language = find_markdown_cell_boundaries(bufnr, cursor_row)
		if language then
			kernel_name_override = find_kernel_by_language(language)
			if not kernel_name_override then
				log.add(
					vim.log.levels.WARN,
					string.format(
						"Nessun kernel configurato per il linguaggio: '%s'. Controlla 'languages' nella tua configurazione Jove.",
						language
					)
				)
				return
			end
		end
	else
		-- Per altri filetype, usa la logica Jupytext
		start_row, end_row = find_current_cell_boundaries(bufnr, cursor_row)
	end

	if not start_row then
		local msg = (filetype == "markdown")
				and "Nessun blocco di codice markdown eseguibile trovato alla posizione corrente."
			or "Nessuna cella Jupytext valida trovata alla posizione corrente."
		log.add(vim.log.levels.INFO, msg)
		return
	end

	local function execute(kernel_name)
		local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
		local code_to_execute = table.concat(lines, "\n")
		if code_to_execute and string.gsub(code_to_execute, "%s", "") ~= "" then
			kernel.execute_cell(kernel_name, code_to_execute, bufnr, start_row, end_row)
		else
			log.add(vim.log.levels.INFO, "Cella vuota, nessun codice da eseguire.")
		end
	end

	run_with_kernel(execute, kernel_name_override)
end

-- Comando per muoversi alla cella successiva
function M.next_cell_cmd()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

	local next_marker_row = find_cell_marker(bufnr, cursor_row, 1)

	if next_marker_row then
		vim.api.nvim_win_set_cursor(0, { next_marker_row + 1, 0 }) -- set_cursor è 1-indexed
	else
		log.add(vim.log.levels.INFO, "Nessuna cella successiva trovata.")
	end
end

-- Comando per muoversi alla cella precedente
function M.previous_cell_cmd()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

	local prev_marker_row = find_cell_marker(bufnr, cursor_row, -1)

	if prev_marker_row then
		vim.api.nvim_win_set_cursor(0, { prev_marker_row + 1, 0 }) -- set_cursor è 1-indexed
	else
		log.add(vim.log.levels.INFO, "Nessuna cella precedente trovata.")
	end
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
	log.add(vim.log.levels.INFO, "Invio richiesta di interruzione al kernel '" .. active_kernel_name .. "'...")
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
		log.add(vim.log.levels.INFO, "Riavvio del kernel '" .. active_kernel_name .. "'...")
		kernel.restart(active_kernel_name)
	end
end

-- Comando per visualizzare la cronologia
function M.history_cmd()
	run_with_kernel(function(active_kernel_name)
		kernel.history(active_kernel_name)
	end)
end

-- Comando per pulire l'output di una o più celle.
function M.clear_output_cmd(args)
	local output = require("jove.output")
	local bufnr = vim.api.nvim_get_current_buf()
	local start_row, end_row

	if args.bang then -- Pulisce tutto il buffer
		start_row = 0
		end_row = vim.api.nvim_buf_line_count(bufnr) - 1
		log.add(vim.log.levels.INFO, "Pulizia di tutto l'output nel buffer...")
	elseif args.range > 0 then -- Pulisce il range
		start_row = args.line1 - 1
		end_row = args.line2 - 1
		log.add(vim.log.levels.INFO, "Pulizia dell'output nel range selezionato...")
	else -- Pulisce alla posizione del cursore
		start_row = vim.api.nvim_win_get_cursor(0)[1] - 1
		end_row = start_row
		log.add(vim.log.levels.INFO, "Pulizia dell'output per la cella sotto il cursore...")
	end

	output.clear_output_in_range(bufnr, start_row, end_row)
end

-- Funzione per la statusline
function M.status_text()
	return status.get_status_text()
end

-- Comando per mostrare lo stato pulito dei kernel
function M.status_cmd()
	local status_lines = status.get_full_status()
	log.add(vim.log.levels.INFO, "Stato dei kernel Jove:")
	for _, line in ipairs(status_lines) do
		vim.api.nvim_echo({ { line, "Normal" } }, false, {})
	end
end

-- Comando per elencare i kernel con informazioni di debug
function M.list_kernels_cmd()
	local kernel_list = kernel.list_running_kernels()
	if #kernel_list == 0 or (#kernel_list == 1 and kernel_list[1]:match("Nessun kernel")) then
		log.add(vim.log.levels.INFO, "Nessun kernel Jove gestito.")
	else
		log.add(vim.log.levels.INFO, "Kernel gestiti (info di debug):")
		for _, status_line in ipairs(kernel_list) do
			vim.api.nvim_echo({ { status_line, "Normal" } }, false, {})
		end
	end
end

-- Comando per mostrare i log
function M.show_log_cmd()
	log.show()
end

--- Comando per renderizzare un'immagine inline.
function M.render_image_cmd(args)
	local image_path = args.fargs[1]
	if not image_path or image_path == "" then
		log.add(vim.log.levels.ERROR, "Percorso dell'immagine non specificato.")
		return
	end

	-- Se il percorso non è assoluto, rendilo relativo alla directory di lavoro corrente.
	-- Utilizziamo un controllo manuale per la compatibilità con versioni di Neovim più vecchie.
	local is_abs
	if vim.fn.has("win32") == 1 then
		is_abs = string.match(image_path, "^[a-zA-Z]:[/\\]") or string.match(image_path, "^[/\\][/\\]")
	else
		is_abs = string.match(image_path, "^/")
	end
	if not is_abs then
		image_path = vim.fn.getcwd() .. "/" .. image_path
	end

	local image_renderer = require("jove.image_renderer")
	local bufnr = vim.api.nvim_get_current_buf()
	local lineno = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed

	image_renderer.render_image(bufnr, lineno, image_path)
end

--- Comando per rendere l'output di una cella selezionabile in una finestra flottante.
function M.select_output_cmd()
	local output = require("jove.output")
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
	output.show_selectable_output(bufnr, cursor_row)
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

vim.api.nvim_create_user_command("JoveExecuteCell", M.execute_jupytext_cell_cmd, {
	nargs = 0,
	desc = "Esegue la cella Jupytext corrente (delimitata da '# %%').",
})

vim.api.nvim_create_user_command("JoveNextCell", M.next_cell_cmd, {
	nargs = 0,
	desc = "Sposta il cursore all'inizio della cella Jupytext successiva.",
})

vim.api.nvim_create_user_command("JovePreviousCell", M.previous_cell_cmd, {
	nargs = 0,
	desc = "Sposta il cursore all'inizio della cella Jupytext precedente.",
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

vim.api.nvim_create_user_command("JoveClearOutput", M.clear_output_cmd, {
	range = "%",
	bang = true,
	desc = "Pulisce l'output (cella corrente, selezione, o ! per tutto).",
})

vim.api.nvim_create_user_command("JoveLog", M.show_log_cmd, {
	nargs = 0,
	desc = "Mostra i log di Jove in un nuovo buffer.",
})

vim.api.nvim_create_user_command("JoveRenderImage", M.render_image_cmd, {
	nargs = 1,
	complete = "file",
	desc = "Renderizza un'immagine inline sulla riga corrente (protocollo iTerm2).",
})

vim.api.nvim_create_user_command("JoveSelectOutput", M.select_output_cmd, {
	nargs = 0,
	desc = "Mostra l'output della cella corrente in una finestra per la selezione.",
})

return M
