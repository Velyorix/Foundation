-- Unit test entry point. Run from the repository root with a Lua 5.4 interpreter:
--
--   lua tests/run.lua                 run every tests/unit/**/*_spec.lua
--   lua tests/run.lua scheduler keys  run spec files whose path contains a filter

package.path = "./?.lua;./?/init.lua;" .. package.path

local Runner = require("tests.support.runner")
local expect = require("tests.support.expect")
local Loader = require("tests.support.loader")
local files = require("tests.support.files")

local filters = { ... }
local specs = {}
for _, path in ipairs(files.list("tests/unit", "*_spec.lua")) do
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
