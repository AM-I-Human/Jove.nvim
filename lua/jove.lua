-- Punto di ingresso principale del plugin

-- 1. Imposta il percorso radice del plugin
-- <sfile> si riferisce a questo file (lua/jove.lua)
-- :p percorso completo
-- :h directory contenente (../lua/)
-- :h directory contenente (root del plugin)
--
vim.g.jove_default_python = vim.g.jove_default_python or "python"
local config = {}
--
local current_file_path = vim.fn.expand("<sfile>:p")
if current_file_path and current_file_path ~= "" and current_file_path ~= "<sfile>:p" then
	vim.g.jove_plugin_root = vim.fn.fnamemodify(current_file_path, ":h:h")
	vim.notify("[Jove] Plugin root impostato su: " .. vim.g.jove_plugin_root, vim.log.levels.INFO)
else
	-- Fallback nel caso <sfile> non funzioni come previsto (molto improbabile per un file .lua)
	local path_info_fallback = debug.getinfo(1, "S")
	if path_info_fallback and path_info_fallback.source and path_info_fallback.source:sub(1, 1) == "@" then
		local script_path_fallback = path_info_fallback.source:sub(2)
		local plugin_lua_dir_fallback = vim.fn.fnamemodify(script_path_fallback, ":h")
		vim.g.jove_plugin_root = vim.fn.fnamemodify(plugin_lua_dir_fallback, ":h")
		vim.notify("[Jove] Plugin root (fallback debug.getinfo): " .. vim.g.jove_plugin_root, vim.log.levels.INFO)
	else
		vim.notify(
			"[Jove] CRITICO: Impossibile determinare il percorso radice del plugin. <sfile> ha restituito: "
				.. current_file_path
				.. ", debug.getinfo().source: "
				.. vim.inspect(path_info_fallback and path_info_fallback.source or "nil"),
			vim.log.levels.ERROR
		)
	end
end

-- A helper to merge user options with defaults.
local function merge_opts(defaults, user_opts)
	user_opts = user_opts or {}
	local merged = vim.deepcopy(defaults)
	for k, v in pairs(user_opts) do
		merged[k] = v
	end
	return merged
end

-- The main setup function. This will be called from init.lua.
function M.setup(user_opts)
	-- 1. Define the default configuration
	local defaults = {
		kernels = {
			python = {
				cmd = "python -m ipykernel_launcher -f {connection_file}",
				python_executable = "python",
			},
		},
	}

	-- 2. Merge user's configuration into the defaults
	config = merge_opts(defaults, user_opts)

	-- 3. Store the configuration in a global variable for now for compatibility
	--    with other modules. The best practice would be to have other modules
	--    call `require('jove').get_config()` instead.
	vim.g.jove_kernels = config.kernels

	-- 4. Set the plugin root path
	local current_file_path = vim.fn.expand("<sfile>:p")
	vim.g.jove_plugin_root = vim.fn.fnamemodify(current_file_path, ":h:h")
	vim.notify("[Jove] Plugin root set to: " .. vim.g.jove_plugin_root, vim.log.levels.INFO)

	-- 5. Load the commands AFTER configuration is complete.
	require("jove.commands")
	vim.notify("[Jove] setup complete.", vim.log.levels.INFO)
end

-- (Optional but recommended) A getter function for other modules
function M.get_config()
	return config
end

-- 3. Carica i comandi del plugin per renderli disponibili.
-- Questo semplifica la configurazione per l'utente, che dovrà solo fare `require('jove')`.
require("jove.commands")
