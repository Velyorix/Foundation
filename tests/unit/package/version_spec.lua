local function read(path)
	local handle = assert(io.open(path, "rb"))
	local content = handle:read("a")
	handle:close()
	return content
end

describe("package version", function()
	it("is a SemVer core version", function()
		local version = Loader.new():require("foundation/version.lua")
		expect.truthy(version.PRODUCT:match("^%d+%.%d+%.%d+$"), "PRODUCT must be X.Y.Z")
	end)

	it("matches the version declared in Package.toml", function()
		local version = Loader.new():require("foundation/version.lua")
		local manifest_version = read("package/Package.toml"):match('\n%s*version%s*=%s*"([^"]+)"')
		expect.equal(manifest_version, version.PRODUCT)
	end)

	it("loads the shared entry point without engine globals beyond Package", function()
		expect.no_error(function()
			Loader.new():run("../Shared/Index.lua")
		end)
	end)
end)
