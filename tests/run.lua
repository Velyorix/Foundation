-- Unit test entry point. Run from the repository root with a Lua 5.4 interpreter:
--
--   lua tests/run.lua                 run every tests/unit/**/*_spec.lua
--   lua tests/run.lua scheduler keys  run spec files whose path contains a filter

package.path = "./?.lua;./?/init.lua;" .. package.path

local Runner = require("tests.support.runner")
local expect = require("tests.support.expect")
local Loader = require("tests.support.loader")

local function read_command(command)
	local pipe = assert(io.popen(command, "r"))
	local lines = {}
	for line in pipe:lines() do
		lines[#lines + 1] = line
	end
	pipe:close()
	return lines
end

local function list_specs()
	local windows = package.config:sub(1, 1) == "\\"
	local cwd = Loader.normalize(read_command(windows and "cd" or "pwd")[1] or "")
	local found = read_command(
		windows and 'dir /b /s /a-d "tests\\unit\\*_spec.lua" 2>nul'
			or "find tests/unit -type f -name '*_spec.lua' 2>/dev/null"
	)
	local specs = {}
	for _, line in ipairs(found) do
		local path = Loader.normalize(line)
		if cwd ~= "" and path:sub(1, #cwd + 1) == cwd .. "/" then
			path = path:sub(#cwd + 2)
		end
		specs[#specs + 1] = path
	end
	table.sort(specs)
	return specs
end

local filters = { ... }
local specs = {}
for _, path in ipairs(list_specs()) do
	local selected = #filters == 0
	for _, filter in ipairs(filters) do
		if path:find(filter, 1, true) then
			selected = true
		end
	end
	if selected then
		specs[#specs + 1] = path
	end
end

if #specs == 0 then
	io.stderr:write("no spec files matched\n")
	os.exit(1)
end

local runner = Runner.new(io.stdout)
local globals = { expect = expect, Loader = Loader }
for _, path in ipairs(specs) do
	runner:run_file(path, globals)
end

os.exit(runner:report() and 0 or 1)
