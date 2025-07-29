# Jove Development Roadmap

Questo documento delinea le funzionalità e i miglioramenti pianificati per Jove.

## Fase 1: Miglioramento del Rendering dell'Output

L'obiettivo di questa fase è migliorare come Jove gestisce e visualizza l'output dei kernel, includendo la correzione di bug esistenti e l'aggiunta del supporto per media ricchi.

- [x] **Risolvere la Sovrascrittura dell'Output:**
  - [x] Indagare e risolvere il problema per cui l'output di `stream` (es. da `print()`) viene sovrascritto da `execute_result`.
  - [x] Rielaborare la logica di gestione dell'output in `lua/jove/output.lua` per accumulare tutti gli output (stream, result, error) di una singola esecuzione di cella invece di sostituirli.
  - [x] Assicurarsi che tutte le parti dell'output vengano visualizzate nell'ordine corretto.

- [ ] **Aggiungere il Supporto per l'Output HTML (Approccio Ibrido):**
  - [ ] Aggiornare i gestori `iopub` per processare `display_data` e `execute_result` contenenti `text/html`.
  - [ ] Implementare una funzione per controllare se il plugin `markview.nvim` è disponibile.
  - [ ] **Percorso Primario (Markview):**
    - [ ] Se Markview è disponibile, salvare il contenuto HTML in un file Markdown temporaneo (`.md`).
    - [ ] Aprire il file Markdown con Markview per un'anteprima integrata in Neovim.
  - [ ] **Percorso di Fallback/Alternativo (Browser):**
    - [ ] Se Markview non è disponibile (o se configurato dall'utente), salvare il contenuto in un file HTML temporaneo (`.html`).
    - [ ] Implementare una funzione per aprire questo file nel browser web predefinito del sistema.
  - [ ] Aggiungere un'opzione di configurazione per permettere all'utente di scegliere il metodo preferito (es. `html_viewer = "integrated" | "browser"`).

- [ ] **Aggiungere il Supporto per l'Output di Immagini (Plot):**
  - [ ] Aggiornare i gestori `iopub` per processare i tipi MIME `image/png`, `image/jpeg`, ecc.
  - [ ] Implementare la decodifica base64 per i dati delle immagini (usando `vim.fn.base64decode`).
  - [ ] Implementare una funzione per salvare i dati dell'immagine decodificata in un file temporaneo.
  - [ ] Aggiungere un meccanismo per aprire il file immagine nel visualizzatore di immagini predefinito del sistema.
  - [ ] (Opzionale) Studiare il supporto per protocolli grafici del terminale (es. Kitty, Wezterm) come funzionalità avanzata.

- [ ] **Implementare la Pulizia dell'Output:**
  - [ ] Creare un comando utente (es. `:JoveClearOutput`) che possa operare sulla riga corrente, su una selezione o sull'intero buffer.
  - [ ] Implementare una funzione in `lua/jove/output.lua` per rimuovere gli `extmarks` associati a un range di righe specifico o a tutto il buffer.

- [ ] **Aggiungere il Supporto per Input Interattivo (`input_request`):**
  - [ ] Gestire i messaggi `input_request` in arrivo dal kernel.
  - [ ] Implementare una funzione che utilizzi `vim.ui.input()` per richiedere l'input all'utente in modo nativo in Neovim.
  - [ ] Inviare la risposta dell'utente al kernel tramite un messaggio `input_reply`.

## Fase 2: Modalità Interattiva a Celle

Questa fase introduce un nuovo modo più interattivo di lavorare con il codice, ispirato ai notebook Jupyter, utilizzando split verticali per l'output.

- [ ] **Implementare il Rilevamento e la Navigazione tra Celle:**
  - [ ] Creare un nuovo modulo, ad esempio `lua/jove/cells.lua`.
  - [ ] Implementare funzioni per identificare i confini delle celle basandosi su marcatori Jupytext (es. `# %%`).
  - [ ] Creare funzioni o mappature per l'utente per navigare tra le celle (es. `JoveNextCell`, `JovePreviousCell`).

- [ ] **Sviluppare la "Modalità di Esecuzione a Celle":**
  - [ ] Creare un nuovo comando (es. `:JoveExecuteInCell`) che attivi questa modalità.
  - [ ] Durante l'esecuzione, creare automaticamente uno split verticale.
  - [ ] La finestra a destra sarà un "buffer di output" dedicato e temporaneo per la cella eseguita.
  - [ ] Disabilitare il rendering del testo virtuale quando si usa questa modalità e reindirizzare tutto l'output al buffer di output.
  - [ ] Assicurarsi che il buffer di output visualizzi correttamente stream, risultati ed errori.
  - [ ] Definire il comportamento del buffer di output: read-only, `buftype=nofile`, con un filetype specifico (es. `jove_output`) per una possibile sintassi personalizzata.
  - [ ] Stabilire che, all'esecuzione (o riesecuzione) di una cella, il buffer di output associato venga prima pulito per mostrare solo il nuovo risultato.

- [ ] **Integrare gli Output Ricchi nella Modalità a Celle:**
  - [ ] Per output HTML/Immagine, invece di aprirli immediatamente, visualizzare un placeholder/link nel buffer di output (es. `[Output HTML: /tmp/xyz.html]`).
  - [ ] Creare un comando o una mappatura per aprire il file di output ricco collegato dal buffer di output.

## Fase 3: Integrazione con Jupyter Notebook (`.ipynb`)

Questa fase mira a fornire un supporto trasparente per la modifica dei file `.ipynb` convertendoli da e verso un formato di script tramite Jupytext.

- [ ] **Implementare il Flusso di Conversione con Jupytext:**
  - [ ] Considerare se usare jupytext.nvim o no
  - [ ] Aggiungere un'opzione di configurazione per specificare il comando `jupytext`.
  - [ ] Aggiungere un controllo per assicurarsi che `jupytext` sia installato e disponibile nel PATH di sistema.
  - [ ] Creare un gruppo `autocmd` per i file `.ipynb`.

- [ ] **Gestire il Caricamento dei Notebook:**
  - [ ] All'apertura di un file `.ipynb` (evento `BufRead`), convertirlo automaticamente in un formato di script "light" (es. `.py` con `# %%`).
  - [ ] Caricare il contenuto dello script convertito nel buffer.
  - [ ] Tenere traccia del percorso del file `.ipynb` originale associato al nuovo buffer dello script.

- [ ] **Gestire il Salvataggio dei Notebook:**
  - [ ] Al salvataggio del buffer dello script (evento `BufWrite`), riconvertirlo automaticamente nel formato `.ipynb`.
  - [ ] Assicurarsi che il file `.ipynb` originale venga sovrascritto con il nuovo contenuto.

- [ ] **Esperienza Utente e Configurazione:**
  - [ ] Aggiungere opzioni per abilitare/disabilitare la conversione automatica.
  - [ ] Fornire un feedback chiaro all'utente durante il processo di conversione (es. notifiche).

## Fase 4: Miglioramenti di Usabilità e Gestione Kernel

- [ ] **UI per la Selezione del Kernel:**
  - [ ] Migliorare `:JoveStart`: se invocato senza argomenti, deve mostrare un'interfaccia di selezione (usando `vim.ui.select`) per scegliere tra i kernel definiti nella configurazione.

- [ ] **Comando per Cambiare Kernel Attivo:**
  - [ ] Creare un comando `:JoveSwitchKernel` che permetta di associare il buffer corrente a un altro kernel già in esecuzione, scegliendo da una lista.

- [ ] **Persistenza e Riconnessione (Avanzato):**
  - [ ] Studiare la possibilità di non terminare i kernel alla chiusura di Neovim (magari tramite un'opzione).
  - [ ] Aggiungere un comando `:JoveConnect` per potersi ricollegare a un kernel già in esecuzione tramite il suo file di connessione.
