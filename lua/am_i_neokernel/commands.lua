
local kernel = require("am_i_neokernel.kernel")
-- local util = require("am_i_neokernel.util") -- Non ancora utilizzato, ma potrebbe servire in futuro

local M = {}

local active_kernel_name = nil -- Traccia il nome del kernel attualmente attivo

-- Comando per avviare un kernel
-- Prende il nome del kernel come argomento
function M.start_kernel_cmd(args)
    local kernel_name = args.fargs[1]
    if not kernel_name or kernel_name == "" then
        vim.notify("Nome del kernel non specificato.", vim.log.levels.ERROR)
        vim.api.nvim_err_writeln("Errore: specificare un nome per il kernel. Esempio: :AmINeoKernelStart python")
        return
    end

    -- Verifica se il kernel_name esiste nella configurazione globale
    if not vim.g.am_i_neokernel_kernels or not vim.g.am_i_neokernel_kernels[kernel_name] then
        local err_msg = "Configurazione non trovata per il kernel: " .. kernel_name ..
                        ". Verificare vim.g.am_i_neokernel_kernels."
        vim.notify(err_msg, vim.log.levels.ERROR)
        vim.api.nvim_err_writeln("Errore: " .. err_msg)
        return
    end

    kernel.start(kernel_name)
    active_kernel_name = kernel_name -- Imposta questo come kernel attivo
    vim.notify("Avvio del kernel '" .. kernel_name .. "' richiesto.", vim.log.levels.INFO)
end

-- Comando per eseguire codice
-- Usa il kernel attivo
function M.execute_code_cmd(args)
    if not active_kernel_name then
        vim.notify("Nessun kernel attivo. Avviare un kernel con :AmINeoKernelStart <nome_kernel>", vim.log.levels.WARN)
        return
    end

    local code_to_execute
    if args.range == 0 then -- Nessuna selezione visuale, esegui riga corrente
        local current_line_nr = vim.api.nvim_win_get_cursor(0)[1]
        code_to_execute = vim.api.nvim_buf_get_lines(0, current_line_nr - 1, current_line_nr, false)[1]
    else -- Selezione visuale
        local first_line = args.line1
        local last_line = args.line2
        local lines = vim.api.nvim_buf_get_lines(0, first_line - 1, last_line, false)
        code_to_execute = table.concat(lines, "\n")
    end

    if code_to_execute and string.gsub(code_to_execute, "%s", "") ~= "" then
        -- Passa il bufnr e la riga iniziale della selezione/cursore a kernel.execute_cell
        -- La riga è 0-indexed per le API, ma args.line1/cursor[1] sono 1-indexed
        local bufnr = vim.api.nvim_get_current_buf()
        local row
        if args.range == 0 then
            row = vim.api.nvim_win_get_cursor(0)[1] -1
        else
            row = args.line1 - 1
        end
        kernel.execute_cell(active_kernel_name, code_to_execute, bufnr, row)
    else
        vim.notify("Nessun codice da eseguire.", vim.log.levels.INFO)
    end
end

vim.api.nvim_create_user_command(
    "AmINeoKernelStart",
    M.start_kernel_cmd,
    {
        nargs = 1,
        complete = function(arglead, cmdline, cursorpos)
            if vim.g.am_i_neokernel_kernels then
                local completions = {}
                for name, _ in pairs(vim.g.am_i_neokernel_kernels) do
                    if string.sub(name, 1, #arglead) == arglead then
                        table.insert(completions, name)
                    end
                end
                return completions
            end
            return {}
        end,
        desc = "Avvia un kernel Jupyter specificato (es. python).",
    }
)

vim.api.nvim_create_user_command(
    "AmINeoKernelExecute",
    M.execute_code_cmd,
    {
        range = "%", -- Consente di gestire sia la riga corrente (senza range) sia un range (selezione visuale)
        desc = "Esegue la riga corrente o la selezione visuale nel kernel attivo.",
    }
)

return M
