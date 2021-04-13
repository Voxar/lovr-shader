--- Renderer
-- Handles drawing of objects
-- @classmod Renderer


local class = require('pl.class')
local pp = require('pl.pretty').dump
require 'shader'

Renderer = class.Renderer()
local lovr = lovr -- help vscode lua plugin a bit

function Renderer:_init()
    --- Stores some information of objects
    self.cache = {}

    self.shaderObj = Shader()
    self.shader = self.shaderObj:generate()
    self.cubemapShader = self.shaderObj:generate({stereo = false})
    for _, shader in ipairs{self.shader, self.cubemapShader} do
        shader:send('specularStrength', 0.5)
        shader:send('metallic', 500.0)
        shader:send('viewPos', { 0.0, 0.0, 0.0} )
        shader:send('ambience', { 0.1, 0.1, 0.1, 1.0 })
    end
    self.lightsBlock = self.shaderObj.lightsBlock
end

--- Draws all objects in list `objects`
-- @tparam table objects List of objects to draw
-- @tparam table context Container for options needed between render passes. Leave nil to just draw all objects.
-- object = {
--  id = string
--  type = string -- object (defualt), light, 
--  light = {  -- when type == 'light'
--      type = string -- 'point', 'spot', 'directional'
--      direction = vec3 -- when type == 'spot' or 'directional'
--  }
--  worldTransform = mat4
--  position = vec3
--  AABB = {min = vec3, max = vec3, radius = float}
--  draw = function(object, context)
--  material = {
--      metalness = float,
--      roughness = float,
--  }
-- }
function Renderer:render(objects, context)
    context = context or {
        generatedCubeMapsCount = 0,
        generatedCubeMapsMax = 2
    }
    context.objects = context.objects or objects
    context.cache = context.cache or self.cache
    context.cameraPosition = context.cameraPosition or newVec3(lovr.headset.getPosition())
    
    -- 1. Sort objects into buckets
    local lights, other, transparent = self:sortObjectIntoBuckets(objects, context)

    -- 2. Go collect information needed to prepare the frame
    context.lights = lights.objects

    self:prepareShaderForFrame(self.shader, context)
    self:prepareShaderForFrame(self.cubemapShader, context)

    context.shader = self.shader
    lovr.graphics.setShader(context.shader)


    context.buckets = {lights, other, transparent}
    
    self:renderContext(context)

    lovr.graphics.setShader()
end

function Renderer:renderContext(context)
    -- get matrices
    -- projection_matrix * Matrix4_Transpose(modelview_matrix)
    local projectionMatrix = lovr.math.newMat4()
    local viewMatrix = lovr.math.newMat4()
    lovr.graphics.getProjection(1, projectionMatrix)
    lovr.graphics.getViewPose(1, viewMatrix, false)
    context.projectionMatrix = projectionMatrix
    context.viewMatrix = viewMatrix

    local frustumMatrix = lovr.math.newMat4(projectionMatrix * viewMatrix:invert())
    context.frustum = self:getFrustum(frustumMatrix)


    for _, bucket in ipairs(context.buckets) do
        self:drawBucket(bucket, context)
    end
end

function Renderer:drawBuckets(buckets, context)
    lovr.graphics.flush()
    context.buckets = buckets
    for _, bucket in ipairs(buckets) do
        self:drawBucket(bucket, context)
    end
end

function Renderer:drawBucket(bucket, context)
    local objects = bucket.objects
    assert(objects)
    if bucket.hasLightSources then
        context.lightSources = bucket.objects
        for _, object in ipairs(objects) do
            context.currentObject = object
            self:drawObject(object, context)
        end
    else
        for _, object in ipairs(objects) do
            context.currentObject = object
            self:drawObject(object, context)
        end
    end
    lovr.math.drain()
end

function Renderer:drawObject(object, context)
    assert(object.id)
    assert(object.AABB)
    assert(object.position)
    assert(object.draw)
    -- assert(object.worldTransform)

    if self:cullTest(object, context) then
        print("skipping " .. object.id)
        return
    end
    
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
    local useReflectionMap = useReflection or useRefraction
    
    -- if useReflectionMap and not cached.reflectionMap then 
    if useReflectionMap and not context.generatingReflectionMapForObject and not cached.reflectionMap then
        if (context.generatedCubeMapsCount or 0) < (context.generatedCubeMapsMax or 1) then
            context.generatedCubeMapsCount = (context.generatedCubeMapsCount or 0) + 1
            self:generateCubemap(object, cached, context)
        end
    end
    

    self:prepareShaderForObject(object, context)
    
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
    local transparent = {
        hasTransparency = true,
        backfaceCulling = true,
        depthBuffer = { read = true, write = false },
        objects = {},
    }
    local other = {
        objects = {},
    }
    local lightsource = {
        hasLightSources = true,
        objects = {},
    }

    for _, object in ipairs(objects) do
        if object.type == 'light' then
            table.insert(lightsource.objects, object)
        elseif object.hasTransparency and not context.skipTransparency then 
            table.insert(transparent.objects, object)
        else
            table.insert(other.objects, object)
        end
    end
    self:sortObjectsFurthestToNearest(transparent.objects, context.cameraPosition)
    self:sortObjectsNearestToFurthest(other.objects, context.cameraPosition)
    return lightsource, other, transparent
end


function Renderer:sortObjectsNearestToFurthest(objects, position)
    table.sort(objects, function(a, b)
        local aScore = a.position:distance(position)
        local bScore = b.position:distance(position)
        return aScore < bScore
    end)
end

function Renderer:sortObjectsFurthestToNearest(objects, position)
    table.sort(objects, function(a, b)
        local aScore = a.position:distance(position)
        local bScore = b.position:distance(position)
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
    local cubemapSize = context.cubemapSize or 64

    if not cubemap then
        local texture = lovr.graphics.newTexture(cubemapSize, cubemapSize, { 
            format = "rg11b10f",
            stereo = false,
            type = "cube"
        })
        local canvas = lovr.graphics.newCanvas(texture, { stereo = false })
        cubemap = { texture = texture, canvas = canvas }
        cached.reflectionMap = cubemap
    end
    
	local view = { lovr.graphics.getViewPose(1) }
	local proj = { lovr.graphics.getProjection(1) }
	lovr.graphics.setProjection(1, mat4():perspective(0.1, 1000, math.pi/2, 1))
	local center = object.position
	for i,pose in ipairs{
		lookAt(center, center + vec3(1,0,0), vec3(0,-1,0)),
		lookAt(center, center - vec3(1,0,0), vec3(0,-1,0)),
		lookAt(center, center + vec3(0,1,0), vec3(0,0,1)),
		lookAt(center, center - vec3(0,1,0), vec3(0,0,-1)),
		lookAt(center, center + vec3(0,0,1), vec3(0,-1,0)),
		lookAt(center, center - vec3(0,0,1), vec3(0,-1,0)),
	} do
		local canvas = cubemap.canvas
        context.generatingReflectionMapForObject = object
        context.shader = self.cubemapShader
            lovr.graphics.setShader(context.shader)
		canvas:setTexture(cubemap.texture, i)
        
		canvas:renderTo(function ()
            

            local r,g,b,a = lovr.graphics.getBackgroundColor()
			lovr.graphics.clear(r, g, b, a, 1, 0)
			lovr.graphics.setViewPose(1, pose, true)
			self:drawBuckets(context.buckets, context)

		end)
        context.shader = self.shader
            lovr.graphics.setShader(context.shader)
            lovr.graphics.flush()
        context.generatingReflectionMapForObject = nil
	end
    lovr.graphics.setProjection(1,unpack(proj))
	lovr.graphics.setViewPose(1,unpack(view))
end

function Renderer:prepareShaderForFrame(shader, context)
    local positions = {}
    local colors = {}
    local lights = context.lights or {}
    for _, light in ipairs(lights) do
        local x, y, z = light.position:unpack()
        table.insert(positions, {x, y, z})
        table.insert(colors, light.light.color)
    end
    self.lightsBlock:send('lightCount', #lights)
    self.lightsBlock:send('lightColors', colors)
    self.lightsBlock:send('lightPositions', positions)
end

function Renderer:prepareShaderForObject(object, context)
    local cached = context.cache[object.id]
    if cached.reflectionMap then
        context.shader:send("reflectionStrength", 1)
        context.shader:send("cubemap", cached.reflectionMap.texture)
    else
        context.shader:send("reflectionStrength", 0)
    end
end

function Renderer:cullTest(object, context)
    local frustum = context.frustum
    for i = 1, 6 do
        local p = frustum[i]
        local e = object.position:dot(vec3(p.x, p.y, p.z)) + p.d + object.AABB.radius
        if e < 0 then return true end -- if outside any plane
    end
    return false
end

-- @tparam mat mat4 projection_matrix * Matrix4_Transpose(modelview_matrix)
-- @treturn {{x, y, z, d}} List of planes normal and distance
function Renderer:getFrustum(mat)
    local planes = {}
    local p = {}
    -- local m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34, m41, m42, m43, m44 = mat:unpack(true)
    local m11, m21, m31, m41, m12, m22, m32, m42, m13, m23, m33, m43, m14, m24, m34, m44 = mat:unpack(true)
    
    local function norm(p)
        local len = math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
        p.x = p.x / len
        p.y = p.y / len
        p.z = p.z / len
        p.d = p.d / len
        return p
    end
    -- Left clipping plane
    planes[1] = norm{
        x = m41 + m11;
        y = m42 + m12;
        z = m43 + m13;
        d = m44 + m14;
    }
    -- Right clipping plane
    planes[2] = norm{
        x = m41 - m11;
        y = m42 - m12;
        z = m43 - m13;
        d = m44 - m14;
    }
    -- Top clipping plane
    planes[3] = norm{
        x = m41 - m21,
        y = m42 - m22,
        z = m43 - m23,
        d = m44 - m24,
    }
    -- Bottom clipping plane
    planes[4] = norm{
        x = m41 + m21,
        y = m42 + m22,
        z = m43 + m23,
        d = m44 + m24,
    }
    -- Near clipping plane
    planes[5] = norm{
        x = m41 + m31,
        y = m42 + m32,
        z = m43 + m33,
        d = m44 + m34,
    }
    -- Far clipping plane
    planes[6] = norm{
        x = m41 - m31,
        y = m42 - m32,
        z = m43 - m33,
        d = m44 - m34,
    }

    return planes
end