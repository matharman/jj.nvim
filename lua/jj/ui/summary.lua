--- @class jj.ui.summary
--- @field buf? integer
--- @field diffsets jj.ui.summary.DiffSet[]
local M = {
	buf = nil,
	diffsets = {
		{ sigil = "M", label = "Modified", fileset = {}, rendered = {} },
		{ sigil = "A", label = "Added", fileset = {}, rendered = {} },
		{ sigil = "D", label = "Deleted", fileset = {}, rendered = {} },
		{ sigil = "R", label = "Renamed", fileset = {}, rendered = {} },
		{ sigil = "C", label = "Copied", fileset = {}, rendered = {} },
	},
}

--- @class jj.ui.summary.DiffSet
--- @field sigil string MADC
--- @field label string Modified, Added, Deleted, Renamed, Copied
--- @field fileset jj.ui.summary.DiffFile[] Files in the diff set
--- @field rendered jj.ui.summary.DiffFile[] Files in the diff set
--- @field start_line? integer
--- @field end_line? integer

--- @class jj.ui.summary.DiffFile
--- @field path string Path to the file included in the diff
--- @field git_diff string[] Git-formatted diff lines for the file
--- @field rendered boolean Toggle indicating if the diff has been rendered in the UI
--- @field start_line? integer
--- @field end_line? integer

local buffer = require("jj.core.buffer")
local parser = require("jj.core.parser")
local runner = require("jj.core.runner")

local function _fmt(msg, ...)
	if select("#", ...) > 0 then
		return string.format(msg, ...)
	else
		return msg
	end
end

local function debug(msg, ...)
	vim.notify(_fmt(msg, ...), vim.log.levels.DEBUG)
end

--- @param diffset jj.ui.summary.DiffSet
--- @param line_no integer
--- @return jj.ui.summary.DiffFile?
local function file_line_range(diffset, line_no)
	for _, file in pairs(diffset.fileset) do
		if file.start_line and file.end_line then
			debug("Checking file %s lines %d-%d against line %d", file.path, file.start_line, file.end_line, line_no)
			if line_no >= file.start_line and line_no <= file.end_line then
				debug("matched %s", file.path)
				return file
			end
		end
	end
	return nil
end

local function toggle_diff()
	if not M.buf then
		return
	end

	local win = vim.api.nvim_get_current_win()
	local pos = vim.api.nvim_win_get_cursor(win)
	local line_no = pos[1]
	debug("toggling diff at line %d", line_no)

	for _, set in ipairs(M.diffsets) do
		local in_file = file_line_range(set, line_no)
		if in_file then
			in_file.rendered = not in_file.rendered

			if in_file.rendered then
				set.rendered[in_file.path] = in_file
			else
				set.rendered[in_file.path] = nil
				pos[1] = in_file.start_line
			end

			M.draw(win, pos)
			return
		end
	end
end

function M.create()
	if M.buf then
		return
	end

	M.buf = buffer.create({
		name = "jujutsu://SUMMARY",
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
				lhs = "=",
				rhs = toggle_diff,
			},
		},
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = M.buf,
		callback = function()
			M.buf = nil
			for _, set in pairs(M.diffsets) do
				set.fileset = {}
				set.rendered = {}
			end
		end,
	})
end

function M.draw(win, new_cursor_pos)
	if not M.buf then
		return
	end

	local out, ok = runner.execute_command("jj status --quiet --color=never", nil, nil, true)
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

	local text = {
		format_change_id("Change ID", status_result.change_id, "@"),
		format_change_id("Parent Change", status_result.parent_change_id, "@-"),
		"Help: g?",
		"",
	}

	local function fetch_diff(path)
		out, ok = runner.execute_command(
			"jj diff --quiet --no-pager --color=never --git " .. path,
			"failed to render diff:",
			nil,
			false
		)
		if not ok or not out then
			return {}
		end

		return vim.split(out, "\n", { plain = true })
	end

	for _, set in ipairs(M.diffsets) do
		local difftype = string.lower(set.label)
		local status_set = status_result[difftype] or {}

		for _, path in ipairs(status_set) do
			local fset = set.fileset[path]
			if not fset then
				set.fileset[path] = {
					path = path,
					git_diff = fetch_diff(path),
					rendered = set.rendered[path] ~= nil,
				}
				fset = set.fileset[path]
			end

			fset.rendered = set.rendered[path] ~= nil
		end

		local len = vim.tbl_count(set.fileset)
		if len > 0 then
			table.insert(text, string.format("%s (%d)", set.label, len))
			set.start_line = #text

			for _, f in pairs(set.fileset) do
				table.insert(text, string.format("%s %s", set.sigil, f.path))
				f.start_line = #text
				if f.rendered then
					vim.list_extend(text, f.git_diff or {})
				end
				f.end_line = #text
				table.insert(text, "")
			end

			set.end_line = #text
			table.insert(text, "")
		end
	end

	vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, text)

	if win and new_cursor_pos then
		vim.api.nvim_win_set_cursor(win, new_cursor_pos)
	end
end

function M.open()
	M.create()
	M.draw(nil, nil)
end

return M
