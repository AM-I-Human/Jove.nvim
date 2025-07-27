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

local defaults = {
	kernels = {
		python = {
			cmd = "python -m ipykernel_launcher -f {connection_file}",
			executable = "python",
			filetypes = { "python" },
		},
	},
}

local config = vim.deepcopy(defaults)

local M = {}
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

-- The main setup function. This will be called from init.lua.
function M.setup(user_opts)
	vim.notify("SetUp method")
	config = deep_merge(defaults, user_opts)

	vim.notify("New config" .. vim.inspect(config))

	-- 4. Set the plugin root path
	local current_file_path = vim.fn.expand("<sfile>:p")
	vim.g.jove_plugin_root = vim.fn.fnamemodify(current_file_path, ":h:h")
	vim.notify("[Jove] Plugin root set to: " .. vim.g.jove_plugin_root, vim.log.levels.INFO)

	vim.notify("[Jove] setup complete.", vim.log.levels.INFO)
end

function M.get_config()
	return config
end

return M
