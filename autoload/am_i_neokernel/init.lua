-- init.lua
-- Questo file è ora utilizzato principalmente per funzioni autoload che potrebbero
-- essere chiamate da altre parti del plugin o dall'utente, se necessario.
-- L'inizializzazione principale (impostazione di variabili globali e default)
-- è stata spostata in lua/am_i_neokernel.lua per assicurare che venga eseguita
-- correttamente da lazy.nvim.

-- Puoi lasciare questo file vuoto o aggiungere funzioni specifiche di autoload qui.
-- Ad esempio, una funzione per ottenere la configurazione:
--
-- local M = {}
-- function M.get_config()
--   return vim.g.am_i_neokernel_kernels
-- end
-- return M

-- Per ora, lo lasciamo vuoto poiché non ci sono funzioni autoload esplicite necessarie.
