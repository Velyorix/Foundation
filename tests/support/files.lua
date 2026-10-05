-- File discovery for the test runner and specs, using the platform shell because
-- standalone Lua has no directory listing.

local Loader = require("tests.support.loader")

local files = {}

local WINDOWS = package.config:sub(1, 1) == "\\"

local function read_command(command)
	local pipe = assert(io.popen(command, "r"))
	local lines = {}
	for line in pipe:lines() do
		lines[#lines + 1] = line
	end
	pipe:close()
	return lines
end

local current_directory = Loader.normalize(read_command(WINDOWS and "cd" or "pwd")[1] or "")

--- Lists files under `directory` (relative to the repository root) whose name matches
-- the shell wildcard `name_pattern`, as sorted repository-relative paths.
function files.list(directory, name_pattern)
	local found
	if WINDOWS then
		found = read_command(string.format('dir /b /s /a-d "%s\\%s" 2>nul', (directory:gsub("/", "\\")), name_pattern))
	else
		found = read_command(string.format("find '%s' -type f -name '%s' 2>/dev/null", directory, name_pattern))
	end
	local paths = {}
	for _, line in ipairs(found) do
		local path = Loader.normalize(line)
		if current_directory ~= "" and path:sub(1, #current_directory + 1) == current_directory .. "/" then
			path = path:sub(#current_directory + 2)
		end
		paths[#paths + 1] = path
	end
	table.sort(paths)
	return paths
end

return files
