--- Implementa l'iTerm2 Image Protocol, usato anche da WezTerm.
local M = {}

local log = require("jove.log")

-- Fallback in puro Lua per la decodifica base64.
local function lua_b64_decode(data)
	log.add(
		vim.log.levels.WARN,
		"[term-image] Funzione nativa 'base64decode' fallita o non trovata. Uso il fallback in Lua."
	)
	local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
	data = string.gsub(data, "[^" .. b64 .. "]", "")
	local out = {}
	for i = 1, #data, 4 do
		local c1, c2, c3, c4 = string.sub(data, i, i + 3):byte(1, 4)
		c1 = b64:find(string.char(c1), 1, true) - 1
		c2 = b64:find(string.char(c2), 1, true) - 1
		table.insert(out, string.char(bit.bor(bit.lshift(c1, 2), bit.rshift(c2, 4))))
		c3 = b64:find(string.char(c3), 1, true)
		if c3 then
			c3 = c3 - 1
			table.insert(out, string.char(bit.bor(bit.lshift(bit.band(c2, 0x0F), 4), bit.rshift(c3, 2))))
			c4 = b64:find(string.char(c4), 1, true)
			if c4 then
				c4 = c4 - 1
				table.insert(out, string.char(bit.bor(bit.lshift(bit.band(c3, 0x03), 6), c4)))
			end
		end
	end
	return table.concat(out)
end

--- Tenta di usare la funzione nativa di Neovim, altrimenti usa il fallback.
-- @param b64_data (string)
-- @return (string) Dati decodificati.
local function b64_decode(b64_data)
	local ok, decoded = pcall(vim.fn.base64decode, b64_data)
	if ok and decoded then
		return decoded
	end
	return lua_b64_decode(b64_data)
end

--- Crea la sequenza di escape per renderizzare un'immagine da dati base64.
-- @param b64_data (string) I dati dell'immagine codificati in base64.
-- @param opts (table) Opzioni come larghezza, altezza (attualmente non usate).
-- @return (string) La sequenza di escape completa da stampare sul terminale.
function M.create_sequence(b64_data, opts)
	opts = opts or {}

	-- Il protocollo iTerm2 richiede la dimensione dei dati *decodificati*.
	local decoded_data = b64_decode(b64_data)
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
