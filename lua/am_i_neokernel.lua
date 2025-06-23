-- Punto di ingresso principale del plugin

-- 1. Imposta il percorso radice del plugin
local path_info = debug.getinfo(1, "S")
if path_info and path_info.source and path_info.source:sub(1,1) == "@" then
    local script_path = path_info.source:sub(2) -- Rimuove '@'
    local plugin_lua_dir = vim.fn.fnamemodify(script_path, ":h") -- .../lua/
    vim.g.am_i_neokernel_plugin_root = vim.fn.fnamemodify(plugin_lua_dir, ":h") -- .../
    -- vim.notify("[AmINeoKernel] Plugin root: " .. vim.g.am_i_neokernel_plugin_root, vim.log.levels.INFO)
else
    vim.notify("[AmINeoKernel] Impossibile determinare il percorso radice del plugin.", vim.log.levels.ERROR)
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
