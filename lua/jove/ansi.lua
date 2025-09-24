-- Modulo per la gestione (semplificata) dei codici di escape ANSI.
local M = {}

-- Mappa i codici colore ANSI di base a gruppi di highlight di Neovim.
local color_map = {
	-- Foreground
	["30"] = { fg = "AnsiColor0" }, -- Black
	["31"] = { fg = "AnsiColor1" }, -- Red
	["32"] = { fg = "AnsiColor2" }, -- Green
	["33"] = { fg = "AnsiColor3" }, -- Yellow
	["34"] = { fg = "AnsiColor4" }, -- Blue
	["35"] = { fg = "AnsiColor5" }, -- Magenta
	["36"] = { fg = "AnsiColor6" }, -- Cyan
	["37"] = { fg = "AnsiColor7" }, -- White
	-- Background
	["40"] = { bg = "AnsiBgColor0" },
	["41"] = { bg = "AnsiBgColor1" },
	["42"] = { bg = "AnsiBgColor2" },
	["43"] = { bg = "AnsiBgColor3" },
	["44"] = { bg = "AnsiBgColor4" },
	["45"] = { bg = "AnsiBgColor5" },
	["46"] = { bg = "AnsiBgColor6" },
	["47"] = { bg = "AnsiBgColor7" },
	-- Bright Foreground
	["90"] = { fg = "AnsiColor8" },
	["91"] = { fg = "AnsiColor9" },
	["92"] = { fg = "AnsiColor10" },
	["93"] = { fg = "AnsiColor11" },
	["94"] = { fg = "AnsiColor12" },
	["95"] = { fg = "AnsiColor13" },
	["96"] = { fg = "AnsiColor14" },
	["97"] = { fg = "AnsiColor15" },
	-- Bright Background
	["100"] = { bg = "AnsiBgColor8" },
	["101"] = { bg = "AnsiBgColor9" },
	["102"] = { bg = "AnsiBgColor10" },
	["103"] = { bg = "AnsiBgColor11" },
	["104"] = { bg = "AnsiBgColor12" },
	["105"] = { bg = "AnsiBgColor13" },
	["106"] = { bg = "AnsiBgColor14" },
	["107"] = { bg = "AnsiBgColor15" },
}

--- Imposta i gruppi di highlight predefiniti per i colori ANSI.
function M.setup_highlights()
	local colors = {
		"#000000",
		"#CD3131",
		"#0DBC79",
		"#E5E510",
		"#2472C8",
		"#BC3FBC",
		"#11A8CD",
		"#E5E5E5",
		"#666666",
		"#F14C4C",
		"#23D186",
		"#F5F543",
		"#3B8EEA",
		"#D670D6",
		"#29B8DB",
		"#E5E5E5",
	}
	for i = 0, 15 do
		vim.api.nvim_command(string.format("highlight default AnsiColor%d guifg=%s", i, colors[i + 1]))
		vim.api.nvim_command(string.format("highlight default AnsiBgColor%d guibg=%s", i, colors[i + 1]))
	end
end

--- Analizza una stringa con codici di escape ANSI e la converte in una lista di "chunk"
--- per la funzione `virt_text` di Neovim.
--- @param text (string) Il testo da analizzare.
--- @param default_hl (string) Il gruppo di highlight da usare come predefinito.
--- @return (table) Una tabella di chunk, es. `{{ "testo1", "hl1" }, { "testo2", "hl2" }}`.
function M.parse(text, default_hl)
	local chunks = {}
	local current_fg = nil
	local current_bg = nil
	local i = 1
	local current_chunk_start = 1

	while true do
		local start, finish, code_str = text:find("\x1b%[([%d;]*)m", i)

		if not start then
			if current_chunk_start <= #text then
				local hl_group = {}
				if current_fg then
					table.insert(hl_group, current_fg)
				end
				if current_bg then
					table.insert(hl_group, current_bg)
				end
				if #hl_group == 0 then
					hl_group = default_hl or "Normal"
				end
				table.insert(chunks, { text:sub(current_chunk_start), hl_group })
			end
			break
		end

		if start > current_chunk_start then
			local hl_group = {}
			if current_fg then
				table.insert(hl_group, current_fg)
			end
			if current_bg then
				table.insert(hl_group, current_bg)
			end
			if #hl_group == 0 then
				hl_group = default_hl or "Normal"
			end
			table.insert(chunks, { text:sub(current_chunk_start, start - 1), hl_group })
		end

		local codes = vim.split(code_str, ";")
		if #codes == 0 or code_str == "" then
			codes = { "0" }
		end

		for _, code in ipairs(codes) do
			if code == "0" then
				current_fg, current_bg = nil, nil
			else
				local color_info = color_map[code]
				if color_info then
					if color_info.fg then
						current_fg = color_info.fg
					end
					if color_info.bg then
						current_bg = color_info.bg
					end
				end
			end
		end

		i = finish + 1
		current_chunk_start = i
	end

	return chunks
end

return M
