-- lua/jove/status.lua
local M = {}

-- Icone per un tocco visuale
local icons = {
	idle = "✓",
	busy = "🚀",
	starting = "⏳",
	error = "✗",
	disconnected = "⚪",
}

-- Tabella che conterrà lo stato dei kernel
local state = {
	kernels = {}, -- Esempio: { python = "idle", julia = "busy" }
	active_kernel = nil,
}

-- Funzione per aggiornare lo stato di un kernel specifico
-- Chiamata da kernel.lua quando lo stato cambia.
function M.update_status(kernel_name, status)
	state.kernels[kernel_name] = status or "disconnected"
	vim.cmd("redraws!") -- Forza un ridisegno della statusline
end

-- Funzione per impostare il kernel attivo
-- Chiamata da commands.lua quando si usa :JoveStart
function M.set_active_kernel(kernel_name)
	state.active_kernel = kernel_name
	vim.cmd("redraws!")
end

-- Funzione per rimuovere un kernel quando viene fermato
function M.remove_kernel(kernel_name)
	state.kernels[kernel_name] = nil
	if state.active_kernel == kernel_name then
		state.active_kernel = nil
	end
	vim.cmd("redraws!")
end

-- LA FUNZIONE CHIAVE PER L'UTENTE DELLA STATUSLINE
-- Restituisce una stringa formattata per la statusline.
function M.get_status_text()
	if not state.active_kernel then
		return "Jove: Idle"
	end

	local kernel_name = state.active_kernel
	local kernel_status = state.kernels[kernel_name] or "disconnected"
	local icon = icons[kernel_status] or "❔"

	return string.format("Jove (%s): %s %s", kernel_name, icon, kernel_status)
end

-- Funzione per ottenere lo stato di tutti i kernel (per il comando :JoveStatus)
function M.get_full_status()
	if not next(state.kernels) then
		return { "Nessun kernel Jove attivo." }
	end

	local status_lines = {}

	for name, status in pairs(state.kernels) do
		local line = string.format("Kernel: %s, Stato: %s", name, status)
		if name == state.active_kernel then
			line = line .. " (attivo)"
		end
		table.insert(status_lines, line)
	end
	return status_lines
end

return M
