--- @class jj.core.parser
local M = {}

--- @class jj.core.parser.StatusResult
--- @field change_id jj.core.parser.StatusResult.ChangeID The current change ID (@)
--- @field parent_change_id jj.core.parser.StatusResult.ChangeID The change ID of the parent (@-)
--- @field modified string[] List of files that have been modified in the working copy
--- @field added string[] List of files that have been added to the working copy
--- @field deleted string[] List of files that have been deleted from the working copy
--- @field renames string[] List of files that have been moved/renamed in the working copy
--- @field copies string[] List of files that have been copied in the working copy
---
--- @class jj.core.parser.StatusResult.ChangeID
--- @field id string The short change ID hexadecimal string
--- @field desc string|nil The first line of the description (if available)

--- @param status_output string The output from some `jj status` command
--- @return jj.core.parser.StatusResult|nil Result of parsing status output
function M.parse_status(status_output)
	if not status_output or status_output == "" then
		return nil
	end

	local result = {
		change_id = { id = "@", desc = nil },
		parent_change_id = { id = "@-", desc = nil },
		modified = {},
		added = {},
		deleted = {},
		renames = {},
		copies = {},
	}

	-- Sample output:
	--
	-- Working copy changes:
	-- M autoload/fugitive.vim
	-- M doc/fugitive.txt
	-- A new_file
	-- Working copy  (@) : wprqlrtr 08b82958 gobbledee gook
	-- Parent commit (@-): xkwnsnzq 61b51c09 master | Fix race conditions generating sequencer sections
	for line in status_output:gmatch("[^\r\n]+") do
		-- Extract working copy change ID and description
		-- Format: Working copy  (@) : wprqlrtr 08b82958 [bookmarks] | description
		-- or:     Working copy  (@) : wprqlrtr 08b82958 description (no bookmarks)
		local wc_change_id, wc_rest = line:match("Working copy%s+%(@%)%s*:%s*(%w+)%s+%w+%s*(.*)")
		if wc_change_id then
			result.change_id.id = wc_change_id
			-- Check if there's a description after bookmarks (separated by |)
			local wc_desc = wc_rest:match("|%s*(.+)")
			if wc_desc then
				result.change_id.desc = wc_desc
			else
				-- No bookmark separator, the rest is the description
				result.change_id.desc = wc_rest ~= "" and wc_rest or nil
			end
		end

		-- Extract parent change ID and description
		-- Format: Parent commit (@-): xkwnsnzq 61b51c09 master | description
		local parent_change_id, parent_rest = line:match("Parent commit%s+%(@%-%)%s*:%s*(%w+)%s+%w+%s*(.*)")
		if parent_change_id then
			result.parent_change_id.id = parent_change_id
			-- Check if there's a description after bookmarks (separated by |)
			local parent_desc = parent_rest:match("|%s*(.+)")
			if parent_desc then
				result.parent_change_id.desc = parent_desc
			else
				-- No bookmark separator, the rest is the description
				result.parent_change_id.desc = parent_rest ~= "" and parent_rest or nil
			end
		end

		-- Extract file status changes (MADRC)
		local status, file = line:match("^([MADRC])%s+(.+)$")
		if status and file then
			if status == "M" then
				table.insert(result.modified, file)
			elseif status == "A" then
				table.insert(result.added, file)
			elseif status == "D" then
				table.insert(result.deleted, file)
			elseif status == "R" then
				table.insert(result.renames, file)
			elseif status == "C" then
				table.insert(result.copies, file)
			end
		end
	end

	return result
end

--- Parse the default command from jj config
--- @param cmd_output string The output from `jj config get ui.default-command`
--- @return table|nil args Array of command arguments, or nil if parsing fails
function M.parse_default_cmd(cmd_output)
	if not cmd_output or cmd_output == "" then
		return nil
	end

	-- Remove whitespace and parse TOML output
	local trimmed_cmd = vim.trim(cmd_output)

	-- Try to parse as TOML array: ["item1", "item2", ...]
	-- Pattern "%[(.*)%]" captures everything between square brackets
	local array_items = trimmed_cmd:match("%[(.*)%]")
	if array_items then
		local args = {}
		-- Pattern '"([^"]+)"' captures content between double quotes (non-greedy)
		for item in array_items:gmatch('"([^"]+)"') do
			table.insert(args, item)
		end
		return #args > 0 and args or nil
	else
		-- Single string value, remove surrounding quotes if present
		-- Pattern '^"?(.-)"?$' optionally matches quotes at start/end, captures content
		local single_value = trimmed_cmd:match('^"?(.-)"?$')
		return single_value and { single_value } or nil
	end
end

--- Get a list of files with their status in the current jj repository.
--- @type string status_output The output from `jj status` command
--- @return table[] A list of tables with {status = string, file = string}
function M.get_status_files(status_output)
	if not status_output then
		return {}
	end

	local files = {}
	-- Parse jj status output: "M filename", "A filename", "D filename", "R old => new"
	for line in status_output:gmatch("[^\r\n]+") do
		local status, file = line:match("^([MADRC])%s+(.+)$")
		if status and file then
			table.insert(files, { status = status, file = file })
		end
	end

	return files
end

--- Parse the current line in the jj status buffer to extract file information.
--- Handles renamed files and regular status lines.
--- @return table|nil A table with {old_path = string, new_path = string, is_rename = boolean}, or nil if parsing fails
function M.parse_file_info_from_status_line(line)
	-- Handle renamed files: "R path/{old_name => new_name}" or "R old_path => new_path"
	local rename_pattern_curly = "^R (.*)/{(.*) => ([^}]+)}"
	local dir_path, old_name, new_name = line:match(rename_pattern_curly)

	if dir_path and old_name and new_name then
		return {
			old_path = dir_path .. "/" .. old_name,
			new_path = dir_path .. "/" .. new_name,
			is_rename = true,
		}
	else
		-- Try simple rename pattern: "R old_path => new_path"
		local rename_pattern_simple = "^R (.*) => (.+)$"
		local old_path, new_path = line:match(rename_pattern_simple)
		if old_path and new_path then
			return {
				old_path = old_path,
				new_path = new_path,
				is_rename = true,
			}
		end
	end

	-- Not a rename, try regular status patterns
	local filepath
	-- Handle renamed files: "R path/{old_name => new_name}" or "R old_path => new_path"
	local rename_pattern_curly_new = "^R (.*)/{.* => ([^}]+)}"
	local dir_path_new, renamed_file = line:match(rename_pattern_curly_new)

	if dir_path_new and renamed_file then
		filepath = dir_path_new .. "/" .. renamed_file
	else
		-- Try simple rename pattern: "R old_path => new_path"
		local rename_pattern_simple_new = "^R .* => (.+)$"
		filepath = line:match(rename_pattern_simple_new)
	end

	if not filepath then
		-- jj status format: "M filename" or "A filename"
		-- Match lines that start with status letter followed by space and filename
		local pattern = "^[MAD?!] (.+)$"
		filepath = line:match(pattern)
	end

	if filepath then
		return {
			old_path = filepath,
			new_path = filepath,
			is_rename = false,
		}
	end

	return nil
end

--- Extract revision ID from a jujutsu log line
--- @param line string The log line to parse
--- @return string|nil The revision ID if found, nil otherwise
function M.get_rev_from_log_line(line)
	-- Build pattern to match graph characters and symbols at start of line
	-- Include: box-drawing chars, whitespace, jujutsu UTF-8 symbols, and ASCII markers
	local graph_chars = "│┃┆┇┊┋╭╮╰╯├┤┬┴┼─└┘┌┐%s" -- box-drawing + whitespace

	-- Jujutsu UTF-8 symbols (with their byte sequences)
	local utf8_symbols = {
		"\226\151\134", -- ◆ U+25C6 (diamond)
		"\226\151\139", -- ○ U+25CB (circle)
		"\195\151", -- × U+00D7 (conflict)
	}

	-- ASCII markers (escaped for pattern matching)
	local ascii_markers = { "@", "%*", "/", "\\", "%-", "%+", "|" }

	-- Build character class for allowed prefix
	local allowed_prefix = "[" .. graph_chars
	for _, symbol in ipairs(utf8_symbols) do
		allowed_prefix = allowed_prefix .. symbol
	end
	for _, marker in ipairs(ascii_markers) do
		allowed_prefix = allowed_prefix .. marker
	end
	allowed_prefix = allowed_prefix .. "]+" -- close class, match one or more (not zero)

	-- Match first alphanumeric sequence after graph prefix
	-- Only match if it's followed by whitespace or end of string (not part of text)
	local revset = line:match("^" .. allowed_prefix .. "(%w+)%s")
	if not revset then
		-- Try matching at end of line without trailing whitespace
		revset = line:match("^" .. allowed_prefix .. "(%w+)$")
	end
	return revset
end

return M
