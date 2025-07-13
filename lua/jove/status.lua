local M = {}

-- Tabella che conterrà lo stato attuale.
-- La rendiamo accessibile all'interno del modulo.
local state = {
	active = false,
	spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	spinner_index = 1,
	timer = nil,
	text = "✓ Idle", -- Testo di default quando non è in esecuzione
}

-- Funzione interna per aggiornare lo spinner
local function update_spinner()
	state.spinner_index = (state.spinner_index % #state.spinner_chars) + 1
	state.text = state.spinner_chars[state.spinner_index] .. " Running"
	-- Forza un ridisegno della statusline
	vim.cmd("redraws!")
end

-- Funzione per avviare lo spinner
function M.start()
	if state.timer and not state.timer:is_closed() then
		return -- Già in esecuzione
	end
	state.active = true
	-- Avvia il timer che chiama update_spinner ogni 80ms
	state.timer = vim.loop.new_timer()
	state.timer:start(0, 80, vim.schedule_wrap(update_spinner))
end

-- Funzione per fermare lo spinner
function M.stop(success)
	if state.timer then
		state.timer:stop()
		state.timer:close()
		state.timer = nil
	end
	state.active = false
	if success == true then
		state.text = "✓ Done"
	elseif success == false then
		state.text = "✗ Error"
	else
		state.text = "✓ Idle"
	end
	vim.cmd("redraws!")

	-- Opzionale: resetta il testo a "Idle" dopo un po'
	vim.defer_fn(function()
		if not state.active then -- Controlla che non sia ripartito nel frattempo
			state.text = "✓ Idle"
			vim.cmd("redraws!")
		end
	end, 2000) -- dopo 2 secondi
end

-- LA FUNZIONE CHIAVE PER L'UTENTE
-- Questa è la funzione che l'utente chiamerà dalla sua statusline.
function M.get_status_text()
	-- Potresti aggiungere qui il nome del kernel o altre info
	return "Jove: " .. state.text
end

return M
