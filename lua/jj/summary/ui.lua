local M = {
	buf = -1,
	text = {},
	file_line_ranges = {},
	expanded = {},
}

--- @class jj.summary.File
--- @field group jj.summary.Group
--- @field path string
--- @field hunks string[][]

--- @alias jj.summary.Group string
---     |"'modified'"
---     |"'added'"
---     |"'deleted'"
---     |"'renamed'"
---     |"'copied'"

local function jj_short_log()
	local cmd =
		'jj log --quiet --color=never --no-graph --no-pager --reversed -r @- -r @ -T \'change_id.shortest(8) ++ ": " ++ if(description.first_line(), description.first_line(), "(no description set)") ++ "\n"\''

	local out, ok = require("jj.core.runner").execute_command(cmd, nil, nil, true)
	if not ok or not out then
		return {}
	end

	return vim.split(out, "\n")
end

--- @return string[] Lines of jj diff output
local function jj_diff()
	local cmd = "jj diff --quiet --no-pager --git --color=never --summary"
	local out, ok = require("jj.core.runner").execute_command(cmd, nil, nil, true)
	if not ok or not out then
		return {}
	end

	if out:len() == 0 then
		return {}
	end

	return vim.split(out, "\n")
end

--- Parse git diff hunks and populate change_list with hunk information
--- @param diff string[] Lines from git diff output
--- @param change_list jj.summary.File[] List of files to populate with hunks
--- @return jj.summary.File[] The change_list with hunks populated
local function parse_diff_hunks(diff, change_list)
	local current_file = nil
	local current_hunk = nil

	for _, line in ipairs(diff) do
		-- Check for new file diff header
		local b_path = line:match("^diff %-%-git a/.+ b/(.+)$")
		if b_path then
			-- Save the previous hunk if it exists
			if current_hunk and current_file then
				table.insert(current_file.hunks, current_hunk)
				current_hunk = nil
			end

			-- Find matching file in change_list
			for _, file in ipairs(change_list) do
				local file_path = type(file.path) == "table" and file.path[2] or file.path
				if file_path == b_path then
					current_file = file
					break
				end
			end
		-- Check for hunk header
		elseif line:match("^@@") then
			-- Save the previous hunk if it exists
			if current_hunk and current_file then
				table.insert(current_file.hunks, current_hunk)
			end

			-- Start a new hunk with the @@ header line
			current_hunk = { line }
		-- Collect hunk content lines (lines starting with +, -, or space)
		elseif current_hunk then
			-- Only include actual diff content lines
			if line:match("^[+%- ]") then
				table.insert(current_hunk, line)
			end
		end
	end

	-- Save the last hunk if it exists
	if current_hunk and current_file then
		table.insert(current_file.hunks, current_hunk)
	end

	return change_list
end

--- @return jj.summary.File[] Parsed diffs from the output
local function files_from_diff()
	local diff = jj_diff()

	local change_list = {}

	for _, line in ipairs(diff) do
		if line:find("^diff %-%-git") then
			break
		end

		local sigil_map = {
			A = "added",
			M = "modified",
			D = "deleted",
			R = "renamed",
			C = "copied",
		}

		local sigil, path_matched = line:match("^([AMDCR]) (.+)")
		if sigil == "R" or sigil == "C" then
			local base, lhs, rhs = path_matched:match("(.*){(.+) => (.+)}")
			path_matched = { base .. lhs, base .. rhs }
		end

		change_list[#change_list + 1] = {
			group = sigil_map[sigil],
			path = path_matched,
			hunks = {},
		}
	end

	-- Now start parsing the git diff
	diff = vim.list_slice(diff, #change_list + 1)

	-- Parse hunks from the diff and populate change_list
	return parse_diff_hunks(diff, change_list)
end

local function file_under_cursor(row)
	for path, meta in pairs(M.file_line_ranges) do
		local file = meta[1]
		local start_line = meta[2]
		local end_line = start_line

		local expanded = M.expanded[path]

		if expanded then
			end_line = start_line + #expanded
		end

		if row >= start_line and row <= end_line then
			return file, expanded, start_line, end_line
		end
	end

	return nil, nil, -1, -1
end

function M.open()
	if M.buf ~= -1 then
		return
	end

	M.buf = require("jj.core.buffer").create({
		name = "jj://SUMMARY",
		buftype = "nowrite",
		modifiable = false,
		split = "vertical",
		size = math.floor(vim.o.columns / 2),
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
				rhs = function()
					local cursor = vim.api.nvim_win_get_cursor(0)
					local row = cursor[1]
					local col = cursor[2]
					local file, expanded, start_line, end_line = file_under_cursor(row)
					if not file then
						return
					end

					local replacement = {}

					if expanded then
						M.expanded[file.path] = nil
					else
						for _, hunk in ipairs(file.hunks) do
							vim.list_extend(replacement, hunk)
						end
						M.expanded[file.path] = replacement
					end

					if #replacement == 0 then
						vim.api.nvim_win_set_cursor(0, { start_line, col })
					end

					vim.api.nvim_buf_set_lines(M.buf, start_line, end_line, false, replacement)
				end,
			},
		},
	})
end

function M.render()
	local short_log = jj_short_log()
	local change_list = files_from_diff()

	local groups = {
		modified = {},
		added = {},
		deleted = {},
		renamed = {},
		copied = {},
	}

	for _, file in ipairs(change_list) do
		table.insert(groups[file.group], file)
	end

	local text = short_log
	table.insert(text, "Help: g?")

	for _, g in ipairs({ "modified", "added", "deleted", "renamed", "copied" }) do
		local files = groups[g]
		local len = #files
		if len > 0 then
			table.insert(text, "")
			table.insert(text, string.format("%s%s (%d):", string.upper(g:sub(1, 1)), g:sub(2), len))

			for _, file in ipairs(files) do
				local path = ""
				if type(file.path) == "table" then
					path = file.path[2]
				else
					path = file.path
				end

				table.insert(text, path)

				local file_start_line = #text
				M.file_line_ranges[path] = { file, file_start_line }

				local expansion = M.expanded[path]

				if expansion then
					table.insert(text, expansion)
				end
			end
		end
	end

	M.text = text
	vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, M.text)
end
return M
