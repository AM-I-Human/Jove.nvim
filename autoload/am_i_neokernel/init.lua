-- init.lua
-- Questo file inizializza il plugin am_i_neokernel.

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
require("am_i_neokernel.commands")

-- Nota: I vecchi comandi JupyterStart e JupyterExecute sono stati rimossi da qui
-- e spostati in lua/am_i_neokernel/commands.lua con i nomi AmINeoKernelStart e AmINeoKernelExecute.
