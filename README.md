- Neovim 0.7 o superiore (consigliato 0.8+ per una migliore gestione dei job).
- Python 3.x installato e disponibile nel PATH (il comando `python` o `python3` deve funzionare).
- `ipykernel` installato nell'ambiente Python (`pip install ipykernel`).
- `jupyter_client` installato nell'ambiente Python (`pip install jupyter_client`).

Il plugin utilizza uno script Python helper che comunica con il kernel Jupyter tramite la libreria `jupyter_client`.

## Installazione

1. Clona il repository o sposta la cartella del plugin nella tua directory `pack` di Neovim o usa il tuo gestore di plugin preferito (es. lazy.nvim).

   Esempio con lazy.nvim nel tuo `init.lua`:
   ```lua
   require("lazy").setup({
     "your/jove/repo", -- Sostituisci con il percorso o l'URL del repository
     config = function()
       require("jove")
       -- Configurazione opzionale qui
       vim.g.jove_kernels = {
           python = {
               cmd = "python -m ipykernel_launcher -f {connection_file}",
               -- executable = "python" -- Specifica l'eseguibile Python se necessario
           },
       }
     end,
   })
   ```

   Esempio per Linux/macOS con gestione manuale:
   ```bash
   mkdir -p ~/.config/nvim/pack/myplugins/start
   ln -s /path/to/your/jove ~/.config/nvim/pack/myplugins/start/jove
   ```
   Sostituisci `/path/to/your/jove` con il percorso effettivo del tuo plugin.

2. Assicurati che `ipykernel` e `jupyter_client` siano installati nell'ambiente Python che intendi utilizzare. Puoi installarli con pip:
   ```bash
   pip install ipykernel jupyter_client
   ```
   Oppure, se usi ambienti virtuali, assicurati che siano installati nell'ambiente attivo quando Neovim avvia il kernel.
