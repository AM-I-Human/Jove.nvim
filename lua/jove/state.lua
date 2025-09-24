-- Modulo per la gestione centralizzata dello stato di Jove.
local M = {}

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

return M
