-- Modulo per la gestione centralizzata dello stato di Jove.
local M = {}

local NS_ID = vim.api.nvim_create_namespace("jove_output")

local state = {
	-- Tiene traccia di tutti i kernel gestiti.
	-- La chiave è il nome del kernel (es. "python").
	kernels = {},
	-- {
	--   [kernel_name] = {
	--     name = "python",
	--     status = "idle", -- "starting", "idle", "busy", "error", "disconnected"
	--     config = { ... }, -- La configurazione statica del kernel
	--     ipykernel_job_id = nil,
	--     py_client_job_id = nil,
	--     on_ready_callback = nil,
	--     current_execution_cell_id = nil,
	--   }
	-- }

	-- Il nome del kernel attualmente attivo per la UI (es. statusline).
	active_kernel_name = nil,

	-- Struttura per memorizzare le celle. La chiave è un ID univoco (extmark ID).
	cells = {},
}

-- =========================================================================
-- FUNZIONI PER I KERNEL
-- =========================================================================

--- Aggiunge un nuovo kernel allo stato o lo resetta se esiste già.
function M.add_kernel(kernel_name, kernel_config)
	state.kernels[kernel_name] = {
		name = kernel_name,
		status = "starting",
		config = kernel_config,
		ipykernel_job_id = nil,
		py_client_job_id = nil,
		on_ready_callback = nil,
		current_execution_cell_id = nil,
	}
	vim.cmd("redraws!") -- Aggiorna la statusline
end

--- Rimuove un kernel dallo stato.
function M.remove_kernel(kernel_name)
	state.kernels[kernel_name] = nil
	if state.active_kernel_name == kernel_name then
		state.active_kernel_name = nil
	end
	vim.cmd("redraws!")
end

--- Ottiene i dati di un kernel.
function M.get_kernel(kernel_name)
	return state.kernels[kernel_name]
end

--- Ottiene tutti i kernel in esecuzione.
function M.get_all_kernels()
	return state.kernels
end

--- Aggiorna lo stato di un kernel (es. 'idle', 'busy').
function M.update_kernel_status(kernel_name, status)
	if state.kernels[kernel_name] then
		state.kernels[kernel_name].status = status
		vim.cmd("redraws!")
	end
end

--- Imposta una proprietà specifica per un kernel.
function M.set_kernel_property(kernel_name, key, value)
	if state.kernels[kernel_name] then
		state.kernels[kernel_name][key] = value
	end
end

--- Ottiene il nome del kernel attivo.
function M.get_active_kernel_name()
	return state.active_kernel_name
end

--- Imposta il nome del kernel attivo.
function M.set_active_kernel_name(kernel_name)
	state.active_kernel_name = kernel_name
	vim.cmd("redraws!")
end

-- =========================================================================
-- FUNZIONI PER LE CELLE
-- =========================================================================

--- Ottiene l'ID dello namespace per gli extmarks di Jove.
function M.get_namespace_id()
	return NS_ID
end

--- Crea i marcatori per una nuova cella e la aggiunge allo stato.
function M.add_cell(bufnr, start_row, end_row)
	local start_mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, start_row, 0, { right_gravity = false })
	local end_mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS_ID, end_row, -1, { right_gravity = true })
	local cell_id = start_mark_id -- Usiamo l'ID del marcatore di inizio come ID della cella

	state.cells[cell_id] = {
		id = cell_id,
		bufnr = bufnr,
		start_mark = start_mark_id,
		end_mark = end_mark_id,
		output_marks = {}, -- Marcatori extmark visuali
		prompt_marks = {},
		outputs = {}, -- Struttura dati per gli output
		pending_clear = false, -- Per `clear_output(wait=true)`
	}
	return cell_id
end

--- Ottiene i dati di una cella.
function M.get_cell(cell_id)
	return state.cells[cell_id]
end

--- Ottiene tutte le celle.
function M.get_all_cells()
	return state.cells
end

--- Aggiunge un nuovo output alla struttura dati di una cella.
function M.add_output_to_cell(cell_id, output_data)
	if state.cells[cell_id] then
		table.insert(state.cells[cell_id].outputs, output_data)
		return true
	end
	return false
end

--- Pulisce i dati di output di una cella.
function M.clear_cell_outputs(cell_id)
	local cell_info = state.cells[cell_id]
	if cell_info then
		if cell_info.image_output_info then
			require("jove.image_renderer").clear_image_area(cell_info.image_output_info, cell_id)
			cell_info.image_output_info = nil
		end
		cell_info.outputs = {}
	end
end

--- Rimuove una cella e tutti i suoi marcatori.
function M.remove_cell(cell_id)
	local cell_info = state.cells[cell_id]
	if cell_info then
		if cell_info.image_output_info then
			require("jove.image_renderer").clear_image_area(cell_info.image_output_info, cell_id)
		end
		-- Rimuove tutti i marcatori associati
		for _, mark_id in ipairs(cell_info.output_marks) do
			pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, mark_id)
		end
		for _, mark_id in ipairs(cell_info.prompt_marks) do
			pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, mark_id)
		end
		pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, cell_info.start_mark)
		pcall(vim.api.nvim_buf_del_extmark, cell_info.bufnr, NS_ID, cell_info.end_mark)

		state.cells[cell_id] = nil
	end
end

--- Trova le celle esistenti contenute in un range e le rimuove.
function M.find_and_remove_cells_in_range(bufnr, start_row, end_row)
	local cells_to_remove = {}
	for cell_id, cell_info in pairs(state.cells) do
		if cell_info.bufnr == bufnr then
			local pos_start = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.start_mark, {})
			local pos_end = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS_ID, cell_info.end_mark, {})

			if pos_start and #pos_start > 0 and pos_end and #pos_end > 0 then
				local cell_start_row = pos_start[1]
				local cell_end_row = pos_end[1]
				if cell_start_row >= start_row and cell_end_row <= end_row then
					table.insert(cells_to_remove, cell_id)
				end
			end
		end
	end
	for _, cell_id in ipairs(cells_to_remove) do
		M.remove_cell(cell_id)
	end
end

return M
