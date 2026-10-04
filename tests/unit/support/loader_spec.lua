describe("test loader", function()
	local loader

	before_each(function()
		loader = Loader.new({ root = "tests/fixtures/loader", side = "Server" })
	end)

	it("resolves side, shared and current-file relative paths like Package.Require", function()
		local result = loader:run("Index.lua")
		expect.same(result, { shared = "shared:nested-relative", sibling = "server-sibling", side = "server" })
	end)

	it("executes a file once and returns the cached result afterwards", function()
		loader:require("sibling.lua")
		loader:require("sibling.lua")
		expect.equal(loader.env.LOAD_COUNT, 1)
	end)

	it("re-executes a file when force_load is set", function()
		loader:require("sibling.lua")
		loader:require("sibling.lua", true)
		expect.equal(loader.env.LOAD_COUNT, 2)
	end)

	it("shares one environment between files of the same package", function()
		loader:require("sibling.lua")
		expect.equal(loader.env.LOAD_COUNT, 1)
		expect.is_nil(rawget(_G, "LOAD_COUNT"), "package globals must not leak into the runner")
	end)

	it("fails on undeclared globals instead of falling back to the runner environment", function()
		expect.raises(function()
			loader:require("uses_global.lua")
		end, "UndeclaredEngineGlobal")
	end)

	it("exposes injected engine globals", function()
		local engine_loader = Loader.new({
			root = "tests/fixtures/loader",
			globals = { UndeclaredEngineGlobal = { Value = 42 } },
		})
		expect.equal(engine_loader:require("uses_global.lua"), 42)
	end)

	it("reports missing files with the requested path", function()
		expect.raises(function()
			loader:require("does/not/exist.lua")
		end, "does/not/exist.lua")
	end)

	it("reports the configured package name through Package.GetName", function()
		local named = Loader.new({ root = "tests/fixtures/loader", name = "my-package" })
		expect.equal(named.env.Package.GetName(), "my-package")
	end)

	it("normalizes separators and dot segments", function()
		expect.equal(Loader.normalize("a\\b/./c/../d.lua"), "a/b/d.lua")
		expect.equal(Loader.normalize("../x/y.lua"), "../x/y.lua")
	end)
end)
