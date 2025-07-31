--- Implementa l'iTerm2 Image Protocol, usato anche da WezTerm.
local M = {}

local log = require("jove.log")

--- Crea la sequenza di escape per renderizzare un'immagine da dati base64.
-- @param b64_data (string) I dati dell'immagine codificati in base64.
-- @param opts (table) Opzioni come larghezza, altezza (attualmente non usate).
-- @return (string) La sequenza di escape completa da stampare sul terminale.
function M.create_sequence(b64_data, opts)
	opts = opts or {}

	-- Il protocollo iTerm2 richiede la dimensione dei dati *decodificati*.
	local decoded_data = vim.fn.base64decode(b64_data)
	local size = #decoded_data

	if size == 0 then
		log.add(vim.log.levels.WARN, "[term-image] IIP: Ricevuti dati immagine vuoti dopo la decodifica base64.")
		return ""
	end

	-- Si possono omettere larghezza e altezza; il terminale userà le dimensioni native dell'immagine.
	-- La sintassi è: \x1b]1337;File=[args]:[base64_data]\a
	-- Usiamo \x07 (carattere BEL), che è un terminatore equivalente.
	local sequence = string.format(
		"\x1b]1337;File=inline=1;size=%d;doNotMoveCursor=1:%s\x07",
		size,
		b64_data
	)

	return sequence
end

return M
