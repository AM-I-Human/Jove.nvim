if vim.loader then
    vim.loader.enable()
end

require 'functions.os'
require 'options.global'
require 'options.opt'
require 'options.mouse'

local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
    local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
    vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
end ---@diagnostic disable-next-line: undefined-field

vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
    'tpope/vim-sleuth', -- Detect tabstop and shiftwidth automatically
    { 'linrongbin16/commons.nvim', lazy = true },
    -- THIS IS YOUR LOCAL PLUGIN
    {
        dir = IS_WINDOWS and 'C:/Users/andre/Projects/Jove.nvim/' or '~/Projects/Jove.nvim/',
        name = 'jove',
        dev = true,
        keys = {
            { '<Leader>Je', ':JoveExecute<cr>', mode = { 'n', 'x', 'v' }, desc = 'Jove: Execute line/selection' },
            { '<Leader>Js', '<cmd>JoveStart python<cr>', mode = { 'n' }, desc = 'Jove: Start python kernel' },
            { '<Leader>Jst', '<cmd>JoveStatus<cr>', mode = { 'n' }, desc = 'Jove: Show status' },
            { '<Leader>Jl', '<cmd>JoveList<cr>', mode = { 'n' }, desc = 'Jove: List kernels' },
            { '<Leader>Jr', '<cmd>JoveRestart<cr>', mode = { 'n' }, desc = 'Jove: Restart kernel' },
            { '<Leader>Jir', '<cmd>JoveInterrupt<cr>', mode = { 'n' }, desc = 'Jove: Interrupt kernel' },
            { '<Leader>Jh', '<cmd>JoveHistory<cr>', mode = { 'n' }, desc = 'Jove: Show history' },
            { '<Leader>Ji', '<cmd>JoveInspect<cr>', mode = { 'n' }, desc = 'Jove: Inspect object' },
            { '<Leader>Jc', '<cmd>JoveExecuteCell<cr>', mode = { 'n' }, desc = 'Jove: Execute cell' },
            { '<Leader>Jn', '<cmd>JoveNextCell<cr>', mode = { 'n' }, desc = 'Jove: Go to next cell' },
            { '<Leader>Jp', '<cmd>JovePreviousCell<cr>', mode = { 'n' }, desc = 'Jove: Go to previous cell' },
            { '<Leader>Jco', ':JoveClearOutput<cr>', mode = { 'n', 'x', 'v' }, desc = 'Jove: Clear output' },
            { '<Leader>JL', '<cmd>JoveLog<cr>', mode = { 'n' }, desc = 'Jove: Show logs' },
            { '<Leader>Jri', '<cmd>JoveRenderImage ', mode = { 'n' }, desc = 'Jove: Render image' },
            { '<Leader>Jti', '<cmd>JoveTestImage<cr>', mode = { 'n' }, desc = 'Jove: Test immagine popup' },
        },
        config = function()
            -- This is the standard way to set up a plugin
            require('jove').setup {
                -- La configurazione del kernel ora usa un placeholder `{executable}`
                -- per permettere a Jove di usare il python dal venv attivo.
                kernels = {
                    python = { cmd = '{executable} -m ipykernel -f {connection_file}' },
                },
            }
        end,
    },
    { import = 'plugins' },
    { import = 'plugins.jupyter' },
    { import = 'plugins.file' },
    { import = 'plugins.ai' },
    require 'plugins.lsp.java',
    { import = 'plugins.mobile' },
}, {
    ui = {
        -- If you are using a Nerd Font: set icons to an empty table which will use the
        -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
        icons = vim.g.have_nerd_font and {} or {
            cmd = '⌘',
            config = '🛠',
            event = '📅',
            ft = '📂',
            init = '⚙',
            keys = '🗝',
            plugin = '🔌',
            runtime = '💻',
            require = '🌙',
            source = '📄',
            start = '🚀',
            task = '📌',
            lazy = '💤 ',
        },
    },
})

require 'ui.sign'
require 'functions.autocommands'
require 'functions.reload'
require 'keymaps.load_keymaps'
Path = require 'functions.path'
Table = require 'functions.table'

require 'commands'
