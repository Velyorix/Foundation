-- Helpers over the engine File API. `raw` provides Open(path, truncate), Exists(path),
-- CreateDirectory(path), IsDirectory(path) and Rename(from, to).
local Files = {}
Files.__index = Files

function Files.new(raw)
	return setmetatable({ raw = raw }, Files)
end

local function parent(path)
	return path:match("^(.*)/[^/]+$")
end

function Files:EnsureDirectory(directory)
	if not directory or self.raw.IsDirectory(directory) then
		return true
	end
	-- Raises when a file already occupies the path (server 1.156).
	local ok, err = pcall(self.raw.CreateDirectory, directory)
	if self.raw.IsDirectory(directory) then
		return true
	end
	return false, ok and directory or tostring(err)
end

-- Returns the content, nil when the file does not exist, or false and a reason.
-- Opening a missing file for reading would create it, hence the Exists check.
function Files:ReadText(path)
	if not self.raw.Exists(path) then
		return nil
	end
	local ok, result = pcall(function()
		local file = self.raw.Open(path, false)
		local text = file:Read(0)
		file:Close()
		return text
	end)
	if not ok then
		return false, tostring(result)
	end
	return result
end

-- Writes next to the target and renames, so readers never see a partial file. The
-- temporary name keeps the extension because File only opens allowed extensions.
function Files:WriteAtomic(path, text)
	local ready, reason = self:EnsureDirectory(parent(path))
	if not ready then
		return false, reason
	end
	local temporary = path:gsub("(%.[^./]+)$", ".tmp%1")
	local ok, err = pcall(function()
		local file = self.raw.Open(temporary, true)
		file:Write(text)
		file:Flush()
		local failed = file:HasFailed()
		file:Close()
		if failed then
			error(temporary)
		end
		if not self.raw.Rename(temporary, path) then
			error(path)
		end
	end)
	if not ok then
		return false, tostring(err)
	end
	return true
end

function Files:Append(path, text)
	local ready, reason = self:EnsureDirectory(parent(path))
	if not ready then
		return false, reason
	end
	local ok, result = pcall(function()
		local file = self.raw.Open(path, false)
		if not file:IsGood() then
			file:Close()
			return false
		end
		file:Seek(file:Size())
		file:Write(text)
		file:Flush()
		local good = not file:HasFailed()
		file:Close()
		return good
	end)
	if not ok then
		return false, tostring(result)
	end
	if not result then
		return false, path
	end
	return true
end

return Files
