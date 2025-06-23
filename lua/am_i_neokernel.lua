-- Punto di ingresso principale del plugin

-- 1. Imposta il percorso radice del plugin
-- <sfile> si riferisce a questo file (lua/am_i_neokernel.lua)
-- :p percorso completo
-- :h directory contenente (../lua/)
-- :h directory contenente (root del plugin)
local current_file_path = vim.fn.expand("<sfile>:p")
if current_file_path and current_file_path ~= "" and current_file_path ~= "<sfile>:p" then
    vim.g.am_i_neokernel_plugin_root = vim.fn.fnamemodify(current_file_path, ":h:h")
    vim.notify("[AmINeoKernel] Plugin root impostato su: " .. vim.g.am_i_neokernel_plugin_root, vim.log.levels.INFO)
else
    -- Fallback nel caso <sfile> non funzioni come previsto (molto improbabile per un file .lua)
    local path_info_fallback = debug.getinfo(1, "S")
    if path_info_fallback and path_info_fallback.source and path_info_fallback.source:sub(1,1) == "@" then
        local script_path_fallback = path_info_fallback.source:sub(2)
        local plugin_lua_dir_fallback = vim.fn.fnamemodify(script_path_fallback, ":h")
        vim.g.am_i_neokernel_plugin_root = vim.fn.fnamemodify(plugin_lua_dir_fallback, ":h")
        vim.notify("[AmINeoKernel] Plugin root (fallback debug.getinfo): " .. vim.g.am_i_neokernel_plugin_root, vim.log.levels.INFO)
    else
        vim.notify("[AmINeoKernel] CRITICO: Impossibile determinare il percorso radice del plugin. <sfile> ha restituito: " .. current_file_path .. ", debug.getinfo().source: " .. vim.inspect(path_info_fallback and path_info_fallback.source or "nil"), vim.log.levels.ERROR)
    end
end

-- 2. Imposta la configurazione di default per i kernel se non già definita dall'utente
if vim.g.am_i_neokernel_kernels == nil then
    vim.g.am_i_neokernel_kernels = {
        python = {
            cmd = "python -m ipykernel_launcher -f {connection_file}",
            -- python_executable = "python" -- L'utente può sovrascrivere per specificare python3, etc.
        },
    }
    -- vim.notify("[AmINeoKernel] Configurazione kernel di default impostata.", vim.log.levels.INFO)
end

-- Eventuali altre inizializzazioni del plugin possono andare qui.
-- Ad esempio, caricare i comandi se non si vuole che l'utente lo faccia esplicitamente.
-- Tuttavia, per ora, lasciamo che l'utente carichi i comandi come da documentazione.
-- require("am_i_neokernel.commands") -- Scommentare se si vuole caricare automaticamente
