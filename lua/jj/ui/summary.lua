local M = {}

local buffer = require("jj.core.buffer")

function M.open()
	local initial_text = {
		"Head:" .. " <change id>:" .. "<description>",
		"Help: g?",
	}

	local buf = buffer.create({
		name = "jujutsu:////SUMMARY",
		split = "vertical",
		size = math.floor(vim.o.columns / 2),
		buftype = "nowrite",
		modifiable = false,
		keymaps = {
			{
				mode = "n",
				lhs = "g?",
				rhs = function()
					vim.notify("You hit the help key, congrats!", vim.log.levels.INFO)
				end,
			},
			{
				mode = "n",
				lhs = "gd",
				rhs = "<cmd>J describe<CR>",
			},
		},
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_text)
end

return M
