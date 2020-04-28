-- Upload API Endpoint
-- Handles API Requests in JSon form
-- Body payload is expected in this form:
--  {
--  "repoName": "base64-encoded name of the repo on the remote docker registry",
--  "layerId": "base64-encoded sha digest of the signed container layer",
--  "signatureData": "<base64-encoded signature of the image layer>"
--  }
-- signature is saved in a path of this kind:
--  destinationPath..<layerId>../signature-1 (which contains the base64-decoded signature)

local cjson = require("cjson.safe")
local ffi = require("ffi")
local table = require("table")

-- import native function sigs
ffi.cdef[[
    int mkdir(const char *pathname, int mode);
    int access(const char *path, int amode);
    char *strerror(int errnum);
]]

-- constants
local SEPARATOR = "/"
local destinationPath = global_sigstore_path
local payloadKeys = { "repoName", "layerId", "signatureData" }
local parsedParams = {}

-- helpers
local function validate_json_input(jsonPayload) 
    for i, v in ipairs(payloadKeys) do
        if jsonPayload[v] == nil then
            ngx.log(ngx.ERR, "Missing required field in json payload: ", v)
            return false
        end
    end

    return true
end

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

local function make_dir(remoteName)
    ngx.log(ngx.ERR, "MAKING: "..remoteName)
    local result = ffi.C.mkdir(remoteName, tonumber("755", 8))
    if result ~= 0 then
        ngx.log(ngx.ERR, ffi.string(ffi.C.strerror(ffi.errno())))
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

local function create_pathspec(pathSpec)
    local pathChunks = split_string(pathSpec, SEPARATOR)
    local pathFragment = "/"..pathChunks[1]
    for i = 2, #pathChunks do
        if assert_exists(pathFragment) == false then
            make_dir(pathFragment)
        end
        pathFragment = pathFragment .. SEPARATOR .. pathChunks[i]
    end
    if assert_exists(pathSpec) == false then
        make_dir(pathSpec)
    end
end

local function save_signature(remoteName, imageHash, base64Payload)
    local sigFullPath = destinationPath .. SEPARATOR .. remoteName .. SEPARATOR ..imageHash
    if type(sigFullPath) == "string" then
        create_pathspec(sigFullPath)

        local saveDescriptor, error = io.open(sigFullPath.."/signature-1", "w")
        if saveDescriptor == nil then
            ngx.log(ngx.ERR, "Failed to open destination file: ", error)
            ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end

        saveDescriptor:write(ngx.decode_base64(base64Payload))
        saveDescriptor:flush()
        saveDescriptor:close()
    else
        ngx.log(ngx.ERR, "Malformed input")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

-- decode the body payload from API request call
local decodedBody, error = cjson.decode(ngx.ctx.bodyData)
if decodedBody ~= nil and validate_json_input(decodedBody) then
    for i, v in ipairs(payloadKeys) do
        parsedParams[v] = decodedBody[v]
    end
else
    ngx.log(ngx.ERR, "Failed to parse API call body in signature_upload. ", error)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- save signature to disk and send response to caller
save_signature(parsedParams.repoName, parsedParams.layerId, parsedParams.signatureData)

-- return
ngx.exit(ngx.HTTP_CREATED)