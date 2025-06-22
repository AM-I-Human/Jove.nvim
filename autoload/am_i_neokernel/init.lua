-- init.lua
-- Questo file inizializza il plugin am_i_neokernel.

-- Determina e salva il percorso radice del plugin
-- <sfile>:p -> percorso completo di questo file (autoload/am_i_neokernel/init.lua)
-- :h -> rimuove /init.lua -> autoload/am_i_neokernel
-- :h -> rimuove /am_i_neokernel -> autoload
-- :h -> rimuove /autoload -> directory radice del plugin
vim.g.am_i_neokernel_plugin_root = vim.fn.expand("<sfile>:p:h:h:h")

-- Configurazione di esempio per i kernel.
-- Questa variabile globale può essere sovrascritta dall'utente nel suo init.lua.
vim.g.am_i_neokernel_kernels = {
	python = {
		cmd = "python -m ipykernel_launcher -f {connection_file}",
		-- Puoi aggiungere altre configurazioni qui, es. display_name
	},
	-- Aggiungi altri kernel se necessario
}

-- Carica i comandi utente definiti per il plugin.
-- Questi comandi sono ora definiti in lua/am_i_neokernel/commands.lua

-- Nota: I vecchi comandi JupyterStart e JupyterExecute sono stati rimossi da qui
-- e spostati in lua/am_i_neokernel/commands.lua con i nomi AmINeoKernelStart e AmINeoKernelExecute.
