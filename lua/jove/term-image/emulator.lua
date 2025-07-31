local M = {}

M.known_emulators = {
	WEZTERM = "WezTerm",
	-- Aggiungere altri emulatori qui in futuro
}

--- Rileva l'emulatore di terminale corrente.
-- @return (string|nil) Il nome dell'emulatore conosciuto o nil.
function M.detect()
	-- Per ora, ci basiamo su TERM_PROGRAM, che è un approccio comune.
	local term_program = vim.env.TERM_PROGRAM
	if term_program and term_program:match("WezTerm") then
		return M.known_emulators.WEZTERM
	end

	-- Aggiungere qui altre logiche di rilevamento...

	return nil
end

return M
