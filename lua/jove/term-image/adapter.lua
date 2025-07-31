local M = {}

local emulator = require("jove.term-image.emulator")
local log = require("jove.log")

-- Tipi di adattatori
M.adapters = {
	IIP = "IIP",
	-- Sixel, Kitty, etc. verranno aggiunti qui
	NONE = "NONE",
}

-- Mappa da emulatore ad adattatore
local emulator_map = {
	[emulator.known_emulators.WEZTERM] = M.adapters.IIP,
}

-- Implementazioni dei driver
local drivers = {
	[M.adapters.IIP] = require("jove.term-image.drivers.iip"),
}

local active_adapter = nil

--- Rileva e configura l'adattatore attivo in base al terminale.
function M.setup()
	local detected_term = emulator.detect()
	if detected_term and emulator_map[detected_term] then
		active_adapter = emulator_map[detected_term]
		log.add(
			vim.log.levels.INFO,
			string.format("[term-image] Rilevato terminale '%s', uso l'adattatore '%s'.", detected_term, active_adapter)
		)
	else
		active_adapter = M.adapters.NONE
		if detected_term then
			log.add(
				vim.log.levels.WARN,
				string.format(
					"[term-image] Rilevato terminale '%s' ma nessun adattatore supportato trovato.",
					detected_term
				)
			)
		else
			log.add(vim.log.levels.INFO, "[term-image] Nessun terminale conosciuto rilevato, supporto immagini disabilitato.")
		end
	end
end

--- Renderizza un'immagine usando l'adattatore attivo.
-- @param b64_data (string) Dati immagine codificati in base64.
-- @param opts (table) Opzioni per il rendering.
-- @return (string|nil) La sequenza di escape per l'immagine, o nil se non supportato.
function M.render(b64_data, opts)
	if not active_adapter then
		M.setup() -- Configurazione automatica alla prima chiamata
	end

	local driver = drivers[active_adapter]
	if driver and driver.create_sequence then
		return driver.create_sequence(b64_data, opts)
	end

	return nil
end

return M
