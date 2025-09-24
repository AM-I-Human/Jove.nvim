-- Modulo per la gestione (semplificata) dei codici di escape ANSI.
local M = {}

-- Mappa i codici colore ANSI di base a gruppi di highlight di Neovim.
local color_map = {
	-- Foreground
	["30"] = "AnsiColor0", -- Black
	["31"] = "AnsiColor1", -- Red
	["32"] = "AnsiColor2", -- Green
	["33"] = "AnsiColor3", -- Yellow
	["34"] = "AnsiColor4", -- Blue
	["35"] = "AnsiColor5", -- Magenta
	["36"] = "AnsiColor6", -- Cyan
	["37"] = "AnsiColor7", -- White
	-- Bright Foreground
	["90"] = "AnsiColor8", -- Bright Black
	["91"] = "AnsiColor9", -- Bright Red
	["92"] = "AnsiColor10", -- Bright Green
	["93"] = "AnsiColor11", -- Bright Yellow
	["94"] = "AnsiColor12", -- Bright Blue
	["95"] = "AnsiColor13", -- Bright Magenta
	["96"] = "AnsiColor14", -- Bright Cyan
	["97"] = "AnsiColor15", -- Bright White
}

--- Imposta i gruppi di highlight predefiniti per i colori ANSI.
function M.setup_highlights()
	-- Basic 8 colors
	vim.api.nvim_command("highlight default AnsiColor0 guifg=#000000")
	vim.api.nvim_command("highlight default AnsiColor1 guifg=#CD3131")
	vim.api.nvim_command("highlight default AnsiColor2 guifg=#0DBC79")
	vim.api.nvim_command("highlight default AnsiColor3 guifg=#E5E510")
	vim.api.nvim_command("highlight default AnsiColor4 guifg=#2472C8")
	vim.api.nvim_command("highlight default AnsiColor5 guifg=#BC3FBC")
	vim.api.nvim_command("highlight default AnsiColor6 guifg=#11A8CD")
	vim.api.nvim_command("highlight default AnsiColor7 guifg=#E5E5E5")
	-- Bright 8 colors
	vim.api.nvim_command("highlight default AnsiColor8 guifg=#666666")
	vim.api.nvim_command("highlight default AnsiColor9 guifg=#F14C4C")
	vim.api.nvim_command("highlight default AnsiColor10 guifg=#23D186")
	vim.api.nvim_command("highlight default AnsiColor11 guifg=#F5F543")
	vim.api.nvim_command("highlight default AnsiColor12 guifg=#3B8EEA")
	vim.api.nvim_command("highlight default AnsiColor13 guifg=#D670D6")
	vim.api.nvim_command("highlight default AnsiColor14 guifg=#29B8DB")
	vim.api.nvim_command("highlight default AnsiColor15 guifg=#E5E5E5")
end

--- Analizza una stringa con codici di escape ANSI e la converte in una lista di "chunk"
--- per la funzione `virt_text` di Neovim.
--- @param text (string) Il testo da analizzare.
--- @param default_hl (string) Il gruppo di highlight da usare come predefinito.
--- @return (table) Una tabella di chunk, es. `{{ "testo1", "hl1" }, { "testo2", "hl2" }}`.
function M.parse(text, default_hl)
	local chunks = {}
	local current_hl = default_hl or "Normal"
	local i = 1
	local current_chunk_start = 1

	while true do
		local start, finish, code_str = text:find("\x1b%[([%d;]*)m", i)

		if not start then
			-- Nessun altro codice di escape, aggiunge il resto della stringa
			if current_chunk_start <= #text then
				table.insert(chunks, { text:sub(current_chunk_start), current_hl })
			end
			break
		end

		-- Aggiunge il testo prima di questo codice di escape
		if start > current_chunk_start then
			table.insert(chunks, { text:sub(current_chunk_start, start - 1), current_hl })
		end

		-- Elabora il codice di escape
		if code_str == "" or code_str == "0" then
			current_hl = default_hl or "Normal" -- Reset
		else
			-- Parser molto semplice: prende solo il primo codice. Non gestisce grassetto, ecc.
			local codes = vim.split(code_str, ";")
			local color_code = codes[1]
			current_hl = color_map[color_code] or current_hl
		end

		i = finish + 1
		current_chunk_start = i
	end

	return chunks
end

return M
