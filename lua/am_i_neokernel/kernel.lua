-- kernel.lua
local zmq = require("lzmq") -- Or your chosen ZeroMQ library
local M = {}

local kernels = {}

function M.start(kernel_name)
	if kernels[kernel_name] then
		vim.notify("Kernel '" .. kernel_name .. "' is already running.", vim.log.levels.WARN)
		return
	end

	local kernel_config = vim.g.am_i_neokernel_kernels[kernel_name] or {}
	local cmd = kernel_config.cmd or "jupyter-kernel --kernel=" .. kernel_name -- Considera di rendere "jupyter-kernel" configurabile
	local connection_file = vim.fn.tempname() .. ".json"
	cmd = string.gsub(cmd, "{connection_file}", connection_file)

	local job_id = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			vim.notify("Kernel stdout: " .. vim.inspect(data), vim.log.levels.INFO)
		end,
		on_stderr = function(_, data)
			vim.notify("Kernel stderr: " .. vim.inspect(data), vim.log.levels.ERROR)
		end,
		on_exit = function(_, exit_code)
			vim.notify("Kernel exited with code: " .. exit_code, vim.log.levels.INFO)
			kernels[kernel_name] = nil -- Clean up
		end,
	})

	vim.defer_fn(function() -- Use defer_fn to give the kernel time to create the file
		local connection_info = M.parse_connection_file(connection_file)
		if connection_info then
			kernels[kernel_name] = {
				job_id = job_id,
				connection_info = connection_info,
				status = "starting",
				connection_file = connection_file,
			}
			M.connect_to_kernel(kernel_name)
		else
			vim.notify("Failed to parse connection file for kernel: " .. kernel_name, vim.log.levels.ERROR)
		end
	end, 100) -- Delay of 100ms
end

function M.parse_connection_file(filename)
	local file = io.open(filename, "r")
	if not file then
		vim.notify("Could not open connection file: " .. filename, vim.log.levels.ERROR)
		return nil
	end
	local content = file:read("*all")
	file:close()
	local ok, result = pcall(vim.json.decode, content)
	if ok then
		return result
	else
		vim.notify("Could not decode connection file: " .. filename .. "\nError: " .. result, vim.log.levels.ERROR)
		return nil
	end
end

function M.connect_to_kernel(kernel_name)
	local kernel_info = kernels[kernel_name]
	if not kernel_info then
		return
	end

	local connection_info = kernel_info.connection_info
	local context = zmq.context()

	local shell_socket = context:socket(zmq.DEALER)
	shell_socket:connect("tcp://" .. connection_info.ip .. ":" .. connection_info.shell_port)

	local iopub_socket = context:socket(zmq.SUB)
	iopub_socket:connect("tcp://" .. connection_info.ip .. ":" .. connection_info.iopub_port)
	iopub_socket:setsockopt(zmq.SUBSCRIBE, "")

	kernel_info.shell_socket = shell_socket
	kernel_info.iopub_socket = iopub_socket
	kernel_info.status = "idle"

	vim.loop.new_timer():start(
		0,
		100,
		vim.schedule_wrap(function()
			M.handle_iopub_message(kernel_name)
		end)
	)
end

-- Modificato per accettare bufnr e row per il posizionamento dell'output
function M.execute_cell(kernel_name, cell_content, bufnr, row)
	local kernel_info = kernels[kernel_name]
	if not kernel_info then
		vim.notify("Kernel '" .. kernel_name .. "' is not running.", vim.log.levels.WARN)
		return
	end

    if kernel_info.status ~= "idle" then
        vim.notify("Kernel '" .. kernel_name .. "' is not idle (status: " .. kernel_info.status .. "). Attendere.", vim.log.levels.WARN)
        return
    end

	local msg = require("am_i_neokernel.message").create_execute_request(cell_content)
	-- Store bufnr and row in kernel_info so handle_iopub_message can access them
	kernel_info.current_execution_bufnr = bufnr
	kernel_info.current_execution_row = row

	local success, err = kernel_info.shell_socket:send(vim.json.encode(msg))
	if not success then
		vim.notify("Error sending execute request: " .. err, vim.log.levels.ERROR)
        kernel_info.current_execution_bufnr = nil -- Clear on error
        kernel_info.current_execution_row = nil
	end
	-- Non impostare bufnr e row qui, ma usa quelli passati e memorizzati
end

function M.handle_iopub_message(kernel_name)
	local kernel_info = kernels[kernel_name]
	if not kernel_info then
		return
	end

	local msg = kernel_info.iopub_socket:recv(zmq.DONTWAIT)
	if not msg then
		return
	end

	local decoded_msg = vim.json.decode(msg)
	-- print("IOPUB", vim.inspect(decoded_msg)) -- Keep this for debugging

	local msg_type = decoded_msg.header.msg_type
	-- Usa bufnr e row dall'esecuzione corrente, non valori globali del kernel_info
	local bufnr = kernel_info.current_execution_bufnr
	local row = kernel_info.current_execution_row

    if not bufnr or not row then
        -- Potrebbe essere un messaggio non sollecitato o un problema, per ora lo ignoriamo se non abbiamo contesto
        -- vim.notify("IOPUB: Received message without execution context: " .. msg_type, vim.log.levels.DEBUG)
        return
    end

	if msg_type == "stream" then
		require("am_i_neokernel.output").render_stream(bufnr, row, decoded_msg)
	elseif msg_type == "execute_result" then
		require("am_i_neokernel.output").render_execute_result(bufnr, row, decoded_msg)
	elseif msg_type == "error" then
		require("am_i_neokernel.output").render_error(bufnr, row, decoded_msg)
	elseif msg_type == "status" and decoded_msg.content.execution_state == "idle" then
        -- Potremmo voler resettare current_execution_bufnr/row qui se l'esecuzione è considerata conclusa
        -- kernel_info.current_execution_bufnr = nil
        -- kernel_info.current_execution_row = nil
    end
end

return M
