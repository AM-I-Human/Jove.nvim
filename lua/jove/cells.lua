-- Modulo per trovare e gestire i confini delle celle di codice (Jupytext, Markdown, ecc.).
local M = {}

--- Trova i limiti di un blocco di codice markdown e il suo linguaggio.
function M.find_markdown_cell_boundaries(bufnr, cursor_row)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local fence_pattern = "^%s*```"
	local start_fence_pattern = "^%s*```([%w_.-]+)"

	local prev_fence = -1
	for i = cursor_row, 0, -1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(fence_pattern) then
			prev_fence = i
			break
		end
	end

	if prev_fence == -1 then
		return nil
	end

	local line = vim.api.nvim_buf_get_lines(bufnr, prev_fence, prev_fence + 1, false)[1] or ""
	local language = line:match(start_fence_pattern)
	-- Se la riga precedente è una fence ma senza linguaggio, non è un inizio di cella eseguibile
	if not language then
		return nil
	end

	local next_fence = -1
	for i = cursor_row + 1, line_count - 1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(fence_pattern) then
			next_fence = i
			break
		end
	end

	if next_fence == -1 then
		return nil
	end

	local start_cell = prev_fence + 1
	local end_cell = next_fence - 1

	if start_cell > end_cell then
		return nil -- Cella vuota
	end

	return start_cell, end_cell, language
end

--- Trova i limiti della cella Jupytext corrente basata su marcatori '# %%'.
function M.find_jupytext_cell_boundaries(bufnr, cursor_row)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local cell_marker_pattern = "^#%s*%%%%"

	-- Cerca all'indietro dal cursore per trovare il marcatore di inizio della cella corrente
	local start_marker_row = -1
	for i = cursor_row, 0, -1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(cell_marker_pattern) then
			start_marker_row = i
			break
		end
	end

	local cell_start_row = start_marker_row + 1

	-- Cerca in avanti da dopo il marcatore di inizio per trovare il marcatore di fine
	local end_marker_row = -1
	-- Inizia la ricerca dalla riga DOPO il marcatore di inizio
	for i = cell_start_row, line_count - 1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(cell_marker_pattern) then
			end_marker_row = i
			break
		end
	end

	local cell_end_row
	if end_marker_row ~= -1 then
		cell_end_row = end_marker_row - 1
	else
		cell_end_row = line_count - 1
	end

	-- Se la cella è vuota (es. cursore su un marcatore seguito immediatamente da un altro o da EOF)
	if cell_start_row > cell_end_row then
		return nil, nil
	end

	return cell_start_row, cell_end_row
end

--- Cerca il marcatore di cella Jupytext successivo o precedente.
function M.find_cell_marker(bufnr, start_row, direction)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local cell_marker_pattern = "^#%s*%%%%"
	local search_start, search_end, step

	if direction > 0 then
		search_start = start_row + 1
		search_end = line_count - 1
		step = 1
	else
		search_start = start_row - 1
		search_end = 0
		step = -1
	end

	for i = search_start, search_end, step do
		local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
		if line:match(cell_marker_pattern) then
			return i
		end
	end

	return nil
end

return M
