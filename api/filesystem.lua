-- filesystem access api
-- handles accesses to the filesystem of the sigstore server

local ffi = require("ffi")

-- constants
local SEPARATOR = "/"

-- module declaration
local filesystem_mod = {}

-- import native function sigs
ffi.cdef[[
    int mkdir(const char *pathname, int mode);
    int access(const char *path, int amode);
    char *strerror(int errnum);
]]

-- module functions
local function assert_exists(pathSpec)
    return 0 == ffi.C.access(pathSpec, 0)
end

local function string_join(separator, ...)
    return table.concat(table.pack(...), separator)
end

local function split_string(sourceString, separator)
    if (type(sourceString) == "string") == false then
        return nil
    else
        sourceString = sourceString:gsub("^/", ""):gsub("/$", "")
        local chunks = {}
        local startOfWord = 0
        for index = 0, sourceString:len() do
            if sourceString:sub(index, index) == separator then
                table.insert(chunks, sourceString:sub(startOfWord, index - 1))
                startOfWord = index + 1
            end
        end
        table.insert(chunks, sourceString:sub(startOfWord))
        return chunks
    end
end

local function  make_dir(remoteName)
    local result = ffi.C.mkdir(remoteName, tonumber("755", 8))
    if result ~= 0 then
        return nil, ffi.string(ffi.C.strerror(ffi.errno()))
    end
    return 0, nil
end

local function create_pathspec(pathSpec)
    local pathChunks = split_string(pathSpec, SEPARATOR)
    if pathChunks == nil then
        return nil, "create_pathspec(): expected string parameter, got: " .. type(pathSpec)
    end

    local pathFragment = SEPARATOR .. pathChunks[1]
    for i = 2, #pathChunks do
        if assert_exists(pathFragment) == false then
            local result, error = make_dir(pathFragment)
            if result == nil then
                return nil, error
            end            
        end
        pathFragment = pathFragment .. SEPARATOR .. pathChunks[i]
    end
    if assert_exists(pathSpec) == false then
        local result, error = make_dir(pathSpec)
        if  result == nil then
            return nil, error
        end
    end
    return 0, nil
end

-- register functions
filesystem_mod.create_pathspec = create_pathspec
filesystem_mod.make_dir = make_dir
filesystem_mod.split_string = split_string
filesystem_mod.string_join = string_join
filesystem_mod.assert_exists = assert_exists
filesystem_mod.path_separator = SEPARATOR

-- return module
return filesystem_mod