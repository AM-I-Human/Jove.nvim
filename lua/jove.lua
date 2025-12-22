-- Punto di ingresso principale del plugin

-- 1. Imposta il percorso radice del plugin
-- <sfile> si riferisce a questo file (lua/jove.lua)
-- :p percorso completo
-- :h directory contenente (../lua/)
-- :h directory contenente (root del plugin)
--
--
vim.g.jove_default_python = vim.g.jove_default_python or "python"

local function deep_merge(tbl1, tbl2)
	local result = vim.deepcopy(tbl1)
	for k, v in pairs(tbl2 or {}) do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = deep_merge(result[k], v)
		else
			result[k] = v
		end
	end
	return result
end

-- Questo è necessario affinché matplotlib produca output PNG inline che possiamo catturare.
local python_setup_code = table.concat({
	"from IPython import get_ipython",
	"if get_ipython():",
	"    get_ipython().run_line_magic('matplotlib', 'inline')",
	"    get_ipython().run_line_magic('config', \"InlineBackend.figure_format = 'png'\")",
}, "\n")

local defaults = {
	image_renderer = "iip", -- Renderer per le immagini: "popup", "iip" (inline), "terminal_popup" (re-openable)
	image_width = 80,
	image_max_size = 400, -- Maximum size in pixels for height/width (preserves aspect ratio)
	kernels = {
		python = {
			cmd = "{executable} -m ipykernel_launcher -f {connection_file}",
			filetypes = { "python" },
			languages = { "python", "py" }, -- Per i blocchi di codice markdown
			setup_code = python_setup_code,
		},
	},
}

local config = vim.deepcopy(defaults)

local M = {}
--
local current_file_path = vim.fn.expand("<sfile>:p")
if current_file_path and current_file_path ~= "" and current_file_path ~= "<sfile>:p" then
	vim.g.jove_plugin_root = vim.fn.fnamemodify(current_file_path, ":h:h")
else
	-- Fallback nel caso <sfile> non funzioni come previsto (molto improbabile per un file .lua)
	local path_info_fallback = debug.getinfo(1, "S")
	if path_info_fallback and path_info_fallback.source and path_info_fallback.source:sub(1, 1) == "@" then
		local script_path_fallback = path_info_fallback.source:sub(2)
		local plugin_lua_dir_fallback = vim.fn.fnamemodify(script_path_fallback, ":h")
		vim.g.jove_plugin_root = vim.fn.fnamemodify(plugin_lua_dir_fallback, ":h")
	end
end

-- The main setup function. This will be called from init.lua.
function M.setup(user_opts)
	local log = require("jove.log")
	log.add(vim.log.levels.INFO, "Avvio configurazione Jove...")

	-- Aggiorna la tabella config esistente per non rompere i riferimenti in altri moduli
	local new_config = deep_merge(defaults, user_opts)
	for k, v in pairs(new_config) do
		config[k] = v
	end

	log.add(vim.log.levels.DEBUG, "Configurazione utente applicata: " .. vim.inspect(user_opts))
	log.add(vim.log.levels.DEBUG, "Configurazione finale: " .. vim.inspect(config))

	log.add(vim.log.levels.INFO, "[Jove] setup completato.")

	-- Carica le regole di highlighting
	require("jove.highlight")
	require("jove.ansi").setup_highlights()

	-- Autocmd per mantenere l'allineamento dei prompt e delle immagini durante l'editing e lo scrolling
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "WinScrolled", "VimResized", "WinResized" }, {
		group = vim.api.nvim_create_augroup("JoveSync", { clear = true }),
		callback = function(ev)
			local state = require("jove.state")
			local output = require("jove.output")
			local bufnr = ev.buf

			-- 1. Allineamento Prompt (solo per modifiche testo nella cella corrente)
			if ev.event == "TextChanged" or ev.event == "TextChangedI" then
				local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
				for cell_id, cell_info in pairs(state.get_all_cells()) do
					if cell_info.bufnr == bufnr then
						local pos_start = vim.api.nvim_buf_get_extmark_by_id(bufnr, state.get_namespace_id(), cell_info.start_mark, {})
						local pos_end = vim.api.nvim_buf_get_extmark_by_id(bufnr, state.get_namespace_id(), cell_info.end_mark, {})
						if pos_start and #pos_start > 0 and pos_end and #pos_end > 0 then
							if cursor_row >= pos_start[1] and cursor_row <= pos_end[1] then
								output.redraw_prompt(cell_id)
							end
						end
					end
				end
			end

			-- 2. Refresh Immagini (per ogni evento che sposta o altera il layout)
			-- Usiamo un piccolo delay per evitare di inondare il TTY durante lo scroll veloce
			if _G._jove_refresh_timer then
				vim.fn.timer_stop(_G._jove_refresh_timer)
			end
			_G._jove_refresh_timer = vim.fn.timer_start(20, function()
				output.refresh_images(bufnr)
			end)
		end,
	})
end

function M.get_config()
	return config
end

return M
