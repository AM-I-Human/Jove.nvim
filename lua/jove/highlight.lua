vim.api.nvim_command("highlight default link JoveStatusIdle MiniStatuslineInactive")
vim.api.nvim_command("highlight default link JoveStatusRunning DiagnosticInfo")
vim.api.nvim_command("highlight default link JoveStatusDone DiagnosticOk")
vim.api.nvim_command("highlight default link JoveStatusError DiagnosticError")

vim.api.nvim_command("highlight default link JoveOutPrompt DiagnosticInfo")

-- =========================================================================
-- Highlighting per JoveLog
-- =========================================================================
vim.api.nvim_command("highlight default link JoveLogTimestamp Comment")
vim.api.nvim_command("highlight default link JoveLogLevelDebug Comment")
vim.api.nvim_command("highlight default link JoveLogLevelInfo String")
vim.api.nvim_command("highlight default link JoveLogLevelWarn DiagnosticWarn")
vim.api.nvim_command("highlight default link JoveLogLevelError DiagnosticError")

-- =========================================================================
-- Highlighting per JoveList
-- =========================================================================
vim.api.nvim_command("highlight default link JoveKernelLabel Identifier")
vim.api.nvim_command("highlight default link JoveKernelName String")
vim.api.nvim_command("highlight default link JoveKernelStatus Comment")
vim.api.nvim_command("highlight default link JoveKernelJobId Number")

-- Gruppo di autocomandi per applicare la sintassi
local augroup = vim.api.nvim_create_augroup("JoveHighlighting", { clear = true })

-- Sintassi per JoveLog
vim.api.nvim_create_autocmd("FileType", {
	group = augroup,
	pattern = "log",
	callback = function()
		vim.cmd([[syntax match JoveLogTimestamp "^\[.\{-}\]"]])
		vim.cmd([[syntax match JoveLogLevelDebug "\[DEBUG\]"]])
		vim.cmd([[syntax match JoveLogLevelInfo "\[INFO\]"]])
		vim.cmd([[syntax match JoveLogLevelWarn "\[WARN\]"]])
		vim.cmd([[syntax match JoveLogLevelError "\[ERROR\]"]])
	end,
})

-- Sintassi per JoveList
vim.api.nvim_create_autocmd("FileType", {
	group = augroup,
	pattern = "jove_kernels",
	callback = function()
		-- Highlight labels
		vim.cmd([[syntax match JoveKernelLabel "Kernel:"]])
		vim.cmd([[syntax match JoveKernelLabel "Stato:"]])
		vim.cmd([[syntax match JoveKernelLabel "IPYKernel Job ID:"]])
		vim.cmd([[syntax match JoveKernelLabel "PyClient Job ID:"]])
		-- Highlight values
		vim.cmd([[syntax match JoveKernelName "Kernel: \zs[^,]*"]])
		vim.cmd([[syntax match JoveKernelStatus "Stato: \zs[^,]*"]])
		vim.cmd([[syntax match JoveKernelJobId "IPYKernel Job ID: \zs[^,]*"]])
		vim.cmd([[syntax match JoveKernelJobId "PyClient Job ID: \zs.*"]])
	end,
})
