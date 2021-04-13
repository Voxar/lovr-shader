--- RenderObject
-- An object put into the Renderer

local class = require 'pl.class'

RenderObject = class.RenderObject()

---
-- @tparam type string 'object'(default) or 'light'
function RenderObject:_init(type)
    self.type = type or 'object'
end