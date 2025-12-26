local M = {}

function M.open()
	local buffer = require("jj.core.buffer")
	local parser = require("jj.core.parser")
	local runner = require("jj.core.runner")

	local out, ok = runner.execute_command("jj status", nil, nil, true)
	if not ok or not out then
		return
	end

	local status_result = parser.parse_status(out)
	if not status_result then
		return
	end

	local function format_change_id(label, change_id, default_rev)
		if change_id.desc then
			return string.format("%s: %s %s", label, change_id.id or default_rev, change_id.desc)
		else
			return change_id.id or default_rev
		end
	end

	local initial_text = {
		format_change_id("Change ID", status_result.change_id, "@"),
		format_change_id("Parent Change", status_result.parent_change_id, "@-"),
	}

	table.insert(initial_text, "Help: g?")
	table.insert(initial_text, "")

	local sigils = {
		M = "Modified",
		A = "Added",
		D = "Deleted",
		R = "Renamed",
		C = "Copied",
	}

	for sigil, description in pairs(sigils) do
		local files = status_result[string.lower(description)]
		if files and #files > 0 then
			table.insert(initial_text, string.format("%s (%d)", description, #files))
			for _, file in ipairs(files) do
				table.insert(initial_text, string.format("%s %s", sigil, file))
			end
			table.insert(initial_text, "")
		end
	end

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
