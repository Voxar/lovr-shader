local class = require('pl.class')

Renderer = class.Renderer()

function Renderer:_init()
    --- Stores some information of objects
    self.cache = {}
end

--- Draws all objects in list `objects`
-- @tparam table objects List of objects to draw
-- @tparam table context Container for options needed between render passes. Leave nil to just draw all objects.
-- object = {
--  id = string
--  worldTransform = mat4
--  position = vec3
--  AABB = {min = vec3, max = vec3, radius = float}
--  draw = function(object, context)
--  
-- }
function Renderer:render(objects, context)
    context = context or {}
    context.objects = context.objects or objects
    context.cache = context.cache or self.cache
    context.cameraPosition = context.cameraPosition or newVec3(lovr.headset.getPosition())
    
    local buckets = self:sortObjectIntoBuckets(objects, context)
    
    self:drawBuckets(buckets, context)
end

function Renderer:drawBuckets(buckets, context)
    context.buckets = buckets
    for _, bucket in ipairs(buckets) do
        self:drawBucket(bucket, context)
    end
end

function Renderer:drawBucket(bucket, context)
    local objects = bucket.objects
    for _, object in ipairs(objects) do
        context.currentObject = object
        self:drawObject(object, context)
    end        
end

function Renderer:drawObject(object, context)
    assert(object.id)
    assert(object.AABB)
    assert(object.position)
    assert(object.draw)
    assert(object.worldTransform)
    
    if context.generatingReflectionMapForObject == object then 
        return
    end
    
    local cached = context.cache[object.id]
    if not cached then 
        cached = { id = object.id }
        context.cache[object.id] = cached
    end
    
    local useTransparency = object.hasTransparency and not context.skipTransparency
    local useRefraction = object.hasRefraction and not context.skipRefraction
    local useReflection = object.hasReflection and not context.skipReflection
    local useReflectionMap = useReflection or useReflection
    
    if useReflectionMap and not cached.reflectionMap then 
        self:generateCubemap(object, cached, context)
    end
    
    if not cached.shader then 

    end
    
    object:draw(object, context)
    
    if context.drawAABB then 
        local bb = object.AABB
        local size = bb.max - bb.min
        local x, y, z = object.position:unpack()
        lovr.graphics.box("line", x, y, z, math.abs(size.x), math.abs(size.y), math.abs(size.z))
    end
end

--- Takes all objects and splits them into buckets for rendering
function Renderer:sortObjectIntoBuckets(objects, context)
    transparentObjects = {
        hasTransparency = true,
        backfaceCulling = true,
        depthBuffer = { read = true, write = false },
        objects = {},
    }
    otherObjects = {
        objects = {},
    }
    
    for _, object in ipairs(objects) do
        if object.hasTransparency and not context.skipTransparency then 
            table.insert(transparentObjects.objects, object)
        else
            table.insert(otherObjects.objects, object)
        end
    end
    self:sortObjectsByAABBCenterToCameraPosition(transparentObjects.objects, context)
    return {
        otherObjects,
        transparentObjects, -- always draw transparent last
    }
end


function Renderer:sortObjectsByAABBCenterToCameraPosition(objects, context)
    local cameraPosition = context.cameraPosition
    table.sort(objects, function(a, b)
        local aScore = a.position:distance(cameraPosition)
        local bScore = b.position:distance(cameraPosition)
        return aScore > bScore
    end)
end

-- this function is broken in lovr 0.14.0
local function lookAt(eye, at, up)
	local z_axis=vec3(eye-at):normalize()
	local x_axis=vec3(up):cross(z_axis):normalize()
	local y_axis=vec3(z_axis):cross(x_axis)
	return lovr.math.newMat4(
		x_axis.x,y_axis.x,z_axis.x,0,
		x_axis.y,y_axis.y,z_axis.y,0,
		x_axis.z,y_axis.z,z_axis.z,0,
		-x_axis:dot(eye),-y_axis:dot(eye),-z_axis:dot(eye),1
	)
end

--- Generates a cube map from the point of object
function Renderer:generateCubemap(object, cached, context)
    local cubemap = cached.reflectionMap
    if not cubemap then
        cubemap = {
            texture = lovr.graphics.newTexture(cubemapSize,cubemapSize,{format="rg11b10f",stereo=false,type="cube"}),
            canvas = lovr.graphics.newCanvas(cubemap.textures[1]),
        }
        cached.reflectionMap = cubemap
    end
    
	local view={lovr.graphics.getViewPose(1)}
	local proj={lovr.graphics.getProjection(1)}
	lovr.graphics.setProjection(1,mat4():perspective(0.1,1000,math.pi/2,1))
	local center = object.position
	for i,pose in ipairs{
		lookAt(center,center+vec3(1,0,0),vec3(0,-1,0)),
		lookAt(center,center-vec3(1,0,0),vec3(0,-1,0)),
		lookAt(center,center+vec3(0,1,0),vec3(0,0,1)),
		lookAt(center,center-vec3(0,1,0),vec3(0,0,-1)),
		lookAt(center,center+vec3(0,0,1),vec3(0,-1,0)),
		lookAt(center,center-vec3(0,0,1),vec3(0,-1,0)),
	} do
		local canvas = cubemap.canvas
		canvas:setTexture(cubemap.texture, i)
        context.generatingReflectionMapForObject = object
		canvas:renderTo(function ()
			local r,g,b,a = lovr.graphics.getBackgroundColor()
			lovr.graphics.clear(r, g, b, a, 1, 0)
			lovr.graphics.setViewPose(1, pose, true)
			self:drawBuckets(context.objects, context)
		end)
        context.generatingReflectionMapForObject = nil
	end
end