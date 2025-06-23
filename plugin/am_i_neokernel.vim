" plugin/am_i_neokernel.vim

" Impedisce il caricamento multiplo del file
if exists("g:loaded_am_i_neokernel")
    finish
endif
let g:loaded_am_i_neokernel = 1

" Esegue il punto di ingresso principale del plugin in Lua.
" Questo script imposta le variabili globali necessarie (come il plugin_root),
" i valori di default e registra i comandi utente.
" Questo garantisce che il plugin sia inizializzato correttamente all'avvio di Neovim.
lua require('am_i_neokernel')
