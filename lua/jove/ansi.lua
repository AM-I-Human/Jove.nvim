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

	-- Helper to create the highlight group
	local function get_hl_group()
		if not current_fg and not current_bg then
			return default_hl or "Normal"
		end
		local group = {}
		if current_fg then
			table.insert(group, current_fg)
		end
		if current_bg then
			table.insert(group, current_bg)
		end
		return group
	end

	while true do
		local start, finish, code_str = text:find("\x1b%[([%d;]*)m", i)

		if not start then
			if current_chunk_start <= #text then
				table.insert(chunks, { text:sub(current_chunk_start), get_hl_group() })
			end
			break
		end

		if start > current_chunk_start then
			table.insert(chunks, { text:sub(current_chunk_start, start - 1), get_hl_group() })
		end

		local codes = vim.split(code_str, ";")
		if #codes == 0 or code_str == "" then
			codes = { "0" }
		end

		local code_idx = 1
		while code_idx <= #codes do
			local code = codes[code_idx]
			if code == "0" or code == "" then
				current_fg, current_bg = nil, nil
			elseif code == "38" then -- Extended foreground color
				code_idx = code_idx + 1
				local next_code = codes[code_idx]
				if next_code == "5" then -- 256 color
					code_idx = code_idx + 1
					local color_index = tonumber(codes[code_idx])
					if color_index then
						local hl_name = "AnsiFg256_" .. color_index
						pcall(
							vim.api.nvim_command,
							string.format("highlight default %s ctermfg=%s guifg=NONE", hl_name, color_index)
						)
						current_fg = hl_name
					end
				elseif next_code == "2" then -- True color
					local r, g, b = tonumber(codes[code_idx + 1]), tonumber(codes[code_idx + 2]), tonumber(codes[code_idx + 3])
					if r and g and b then
						local hex = string.format("#%02x%02x%02x", r, g, b)
						local hl_name = "AnsiFgTrue_" .. r .. "_" .. g .. "_" .. b
						pcall(vim.api.nvim_command, string.format("highlight default %s guifg=%s", hl_name, hex))
						current_fg = hl_name
					end
					code_idx = code_idx + 3
				end
			elseif code == "48" then -- Extended background color
				local next_code = codes[code_idx]
				if next_code == "5" then -- 256 color
					code_idx = code_idx + 1
					local color_index = tonumber(codes[code_idx])
					if color_index then
						local hl_name = "AnsiBg256_" .. color_index
						pcall(
							vim.api.nvim_command,
							string.format("highlight default %s ctermbg=%s guibg=NONE", hl_name, color_index)
						)
						current_bg = hl_name
					end
				elseif next_code == "2" then -- True color
					local r, g, b = tonumber(codes[code_idx + 1]), tonumber(codes[code_idx + 2]), tonumber(codes[code_idx + 3])
					if r and g and b then
						local hex = string.format("#%02x%02x%02x", r, g, b)
						local hl_name = "AnsiBgTrue_" .. r .. "_" .. g .. "_" .. b
						pcall(vim.api.nvim_command, string.format("highlight default %s guibg=%s", hl_name, hex))
						current_bg = hl_name
					end
					code_idx = code_idx + 3
				end
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
			code_idx = code_idx + 1
		end

		i = finish + 1
		current_chunk_start = i
	end

	return chunks
end

return M
