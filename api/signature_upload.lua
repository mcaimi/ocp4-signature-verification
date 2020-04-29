-- Upload API Endpoint
-- Handles API Requests in JSon form
-- Body payload is expected in this form:
--  {
--  "repoName": "base64-encoded name of the repo on the remote docker registry",
--  "layerId": "base64-encoded sha digest of the signed container layer",
--  "signatureData": "<base64-encoded signature of the image layer>"
--  }
-- signature is saved in a path of this kind:
--  destinationPath..<repoName>..<layerId>../signature-1 (which contains the base64-decoded signature)

local cjson = require("cjson.safe")
local table = require("table")
local filesystem = require("filesystem")

-- constants
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

local function save_signature(remoteName, imageHash, signaturePayload)
    local sigFullPath = destinationPath .. filesystem.path_separator .. ngx.decode_base64(remoteName) .. filesystem.path_separator .. ngx.decode_base64(imageHash)
    if type(sigFullPath) == "string" then
        local result, error = filesystem.create_pathspec(sigFullPath)
        if result == nil then
            ngx.log(ngx.ERR, "create_pathspec() failed: " .. error)
            ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end

        local saveDescriptor, error = io.open(sigFullPath.."/signature-1", "w")
        if saveDescriptor == nil then
            ngx.log(ngx.ERR, "Failed to open destination file: ", error)
            ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end

        saveDescriptor:write(ngx.decode_base64(signaturePayload))
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