-- Modulo per la gestione di elementi UI come finestre flottanti per lo stato.
local M = {}

local spinner_state = {
	win_id = nil,
	buf_id = nil,
	timer = nil,
	frame = 1,
	frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
}

local function update_spinner_content(kernel_name, status)
	if not spinner_state.buf_id or not vim.api.nvim_buf_is_valid(spinner_state.buf_id) then
		return
	end

	local frame_char = spinner_state.frames[spinner_state.frame]
	local text = string.format("%s Jove: Kernel '%s' is %s...", frame_char, kernel_name, status)

	vim.api.nvim_buf_set_lines(spinner_state.buf_id, 0, -1, false, { text })

	-- Ricalcola la larghezza e riposiziona la finestra se il testo cambia
	if spinner_state.win_id and vim.api.nvim_win_is_valid(spinner_state.win_id) then
		local width = vim.fn.strwidth(text) + 2
		local config = vim.api.nvim_win_get_config(spinner_state.win_id)
		config.width = width
		config.col = vim.o.columns - width - 2
		pcall(vim.api.nvim_win_set_config, spinner_state.win_id, config)
	end
end

local function animate_spinner(kernel_name, status)
	spinner_state.frame = (spinner_state.frame % #spinner_state.frames) + 1
	update_spinner_content(kernel_name, status)
end

--- Mostra una finestra flottante con uno spinner per indicare che il kernel è occupato.
function M.show_spinner(kernel_name, status)
	-- Se la finestra esiste già, aggiorna solo il contenuto.
	if spinner_state.win_id and vim.api.nvim_win_is_valid(spinner_state.win_id) then
		update_spinner_content(kernel_name, status)
		return
	end

	-- Crea il buffer
	spinner_state.buf_id = vim.api.nvim_create_buf(false, true)
	vim.bo[spinner_state.buf_id].buftype = "nofile"
	vim.bo[spinner_state.buf_id].bufhidden = "wipe"
	vim.bo[spinner_state.buf_id].swapfile = false
	vim.bo[spinner_state.buf_id].filetype = "jove-spinner"

	local initial_text = string.format("... Jove: Kernel '%s' is %s... ", kernel_name, status)
	local width = vim.fn.strwidth(initial_text) + 2

	-- Crea la finestra
	spinner_state.win_id = vim.api.nvim_open_win(spinner_state.buf_id, true, {
		relative = "editor",
		width = width,
		height = 1,
		row = vim.o.lines - 3, -- Angolo in basso a destra
		col = vim.o.columns - width - 2,
		style = "minimal",
		border = "rounded",
		noautocmd = true,
	})

	vim.wo[spinner_state.win_id].winhighlight = "Normal:StatusLine,FloatBorder:StatusLine"

	-- Avvia il timer per l'animazione
	if spinner_state.timer then
		spinner_state.timer:close()
	end
	spinner_state.timer = vim.loop.new_timer()
	spinner_state.timer:start(0, 100, vim.schedule_wrap(function()
		animate_spinner(kernel_name, status)
	end))

	-- Aggiorna il contenuto iniziale
	update_spinner_content(kernel_name, status)
end

--- Nasconde la finestra dello spinner.
function M.hide_spinner()
	if spinner_state.timer then
		spinner_state.timer:stop()
		spinner_state.timer:close()
		spinner_state.timer = nil
	end

	if spinner_state.win_id and vim.api.nvim_win_is_valid(spinner_state.win_id) then
		vim.api.nvim_win_close(spinner_state.win_id, true)
	end

	spinner_state.win_id = nil
	spinner_state.buf_id = nil -- Il buffer viene eliminato automaticamente
end

return M
