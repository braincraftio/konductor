local M = {}
local directions = { h = "left", j = "down", k = "up", l = "right", p = "previous" }

local function report(message)
	vim.schedule(function()
		vim.notify("OpenCode navigation: " .. message, vim.log.levels.ERROR)
	end)
end

local function send(direction)
	local socket = vim.env.OPENCODE_PTY_CONTROL_SOCKET
	local token = vim.env.OPENCODE_PTY_CONTROL_TOKEN
	local id = tonumber(vim.env.OPENCODE_PTY_ID)
	if not socket or not token or not id then
		report("terminal control environment is unavailable")
		return
	end
	local pipe, pipe_error = vim.uv.new_pipe(false)
	if not pipe then
		return report(pipe_error)
	end
	local timer, timer_error = vim.uv.new_timer()
	if not timer then
		pipe:close()
		return report(timer_error)
	end
	local finished = false
	local function finish(err)
		if finished then
			return
		end
		finished = true
		timer:stop()
		timer:close()
		pipe:close()
		if err then
			report(err)
		end
	end
	local payload = vim.json.encode({
		token = token,
		request = { op = "notify_controller", id = id, message = "pane.focus." .. directions[direction] },
	})
	local length = #payload
	local frame = string.char(
		math.floor(length / 16777216) % 256,
		math.floor(length / 65536) % 256,
		math.floor(length / 256) % 256,
		length % 256
	) .. payload
	local pending = ""
	timer:start(1000, 0, function()
		finish("controller request timed out")
	end)
	local request, connect_error = pipe:connect(socket, function(err)
		if finished then
			return
		end
		if err then
			return finish(err)
		end
		local reading, read_error = pipe:read_start(function(read_err, chunk)
			if finished then
				return
			end
			if read_err then
				return finish(read_err)
			end
			if not chunk then
				return finish("controller closed without a response")
			end
			pending = pending .. chunk
			if #pending < 4 then
				return
			end
			local a, b, c, d = pending:byte(1, 4)
			local size = ((a * 256 + b) * 256 + c) * 256 + d
			if size > 65536 then
				return finish("invalid controller response size")
			end
			if #pending < size + 4 then
				return
			end
			local ok, response = pcall(vim.json.decode, pending:sub(5, size + 4))
			if not ok or type(response) ~= "table" then
				return finish("invalid controller response")
			end
			if response.type == "ok" then
				return finish()
			end
			finish(response.message or "controller rejected request")
		end)
		if not reading then
			return finish(read_error)
		end
		local writing, write_error = pipe:write(frame, function(write_err)
			if write_err then
				finish(write_err)
			end
		end)
		if not writing then
			finish(write_error)
		end
	end)
	if not request then
		finish(connect_error)
	end
end

function M.navigate(direction)
	if not directions[direction] then
		error("direction must be h, j, k, l, or p")
	end
	local before = vim.api.nvim_get_current_win()
	if direction == "p" and vim.fn.winnr("#") == 0 then
		send(direction)
		return
	end
	vim.cmd("wincmd " .. direction)
	if vim.api.nvim_get_current_win() == before then
		send(direction)
	end
end

function M.setup()
	if not vim.env.OPENCODE_PTY_CONTROL_SOCKET then
		return
	end
	for _, direction in ipairs({ "h", "j", "k", "l", "p" }) do
		local key = direction == "p" and "\\" or direction
		local modes = direction == "p" and { "n" } or { "n", "i", "t" }
		vim.keymap.set(modes, "<C-" .. key .. ">", function()
			M.navigate(direction)
		end, { desc = "Navigate " .. directions[direction] .. " window/pane", silent = true })
	end
end

return M
