--- @class jj.summary
local M = {}

local ui = require("jj.summary.ui")

--- For testing purposes only.
function M.entrypoint()
	-- Instantiate the summary buffer
	ui.open()
	ui.render()
end

return M
