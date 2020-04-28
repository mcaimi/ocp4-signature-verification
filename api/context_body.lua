-- Body Data Handler
-- Sets the received data body as a context variable

-- read request body
ngx.req.read_body()

-- set context variable
-- if body gets spooled to a file, load its contents from disk
local data = ngx.req.get_body_data()
if data == nil then
    local fD = io.open(ngx.req.get_body_file(), 'r')
    ngx.ctx.bodyData = fD:read("*a")
    fD:close()
else
    ngx.ctx.bodyData = data
end