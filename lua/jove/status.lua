-- lua/jove/status.lua
-- Questo modulo è ora un wrapper stateless attorno a `jove.state`
-- per la visualizzazione dello stato.
local M = {}
local state = require("jove.state")

local icons = {
	idle = "✓",
	busy = "🚀",
	starting = "⏳",
	error = "✗",
	disconnected = "⚪",
}

--- Aggiorna lo stato di un kernel. Proxy per `state.update_kernel_status`.
function M.update_status(kernel_name, status)
	state.update_kernel_status(kernel_name, status or "disconnected")
end

--- Imposta il kernel attivo. Proxy per `state.set_active_kernel_name`.
function M.set_active_kernel(kernel_name)
	state.set_active_kernel_name(kernel_name)
end

--- Rimuove un kernel. Proxy per `state.remove_kernel`.
function M.remove_kernel(kernel_name)
	state.remove_kernel(kernel_name)
end

--- Ottiene lo stato di un singolo kernel.
function M.get_status(kernel_name)
	local kernel_info = state.get_kernel(kernel_name)
	return kernel_info and kernel_info.status
end

--- Genera il testo per la statusline.
function M.get_status_text()
	local active_kernel_name = state.get_active_kernel_name()
	if not active_kernel_name then
		return "Jove: No kernel"
	end

	local kernel_info = state.get_kernel(active_kernel_name)
	local kernel_status = (kernel_info and kernel_info.status) or "disconnected"
	local icon = icons[kernel_status] or "❔"

	return string.format("Jove (%s): %s %s", active_kernel_name, icon, kernel_status)
end

--- Ottiene una lista formattata dello stato di tutti i kernel.
function M.get_full_status()
	local all_kernels = state.get_all_kernels()
	if not next(all_kernels) then
		return { "Nessun kernel Jove attivo." }
	end

	local active_kernel_name = state.get_active_kernel_name()
	local status_lines = {}
	for name, kernel_info in pairs(all_kernels) do
		local line = string.format("Kernel: %s, Stato: %s", name, kernel_info.status)
		if name == active_kernel_name then
			line = line .. " (attivo)"
		end
		table.insert(status_lines, line)
	end
	return status_lines
end

return M
