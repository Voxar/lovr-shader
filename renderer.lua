--- Renderer
-- Handles drawing of objects
-- @classmod Renderer


local class = require('pl.class')
local pp = require('pl.pretty').dump
local tablex = require('pl.tablex')
local OrderedMap = require('pl.OrderedMap')

require 'shader'

Renderer = class.Renderer()
local lovr = lovr -- help vscode lua plugin a bit

function Renderer:_init()
    --- Stores some information of objects
    self.cache = {}

    self.shaderObj = Shader()
    self.shader = self.shaderObj:generate()
    self.cubemapShader = self.shaderObj:generate({stereo = false})

    self.standardShaders = {
        self.shader, 
        self.cubemapShader
    }
    
    self.lightsBlock = self.shaderObj.lightsBlock
    for _, shader in ipairs(self.standardShaders) do
        shader:send('specularStrength', 0.5)
        shader:send('metallic', 500.0)
        shader:send('viewPos', { 0.0, 0.0, 0.0} )
        shader:send('ambience', { 0.1, 0.1, 0.1, 1.0 })
    end

    self.frameCount = 0
    self.viewCount = 0

    self.drawLayer = {
        names = {
            "albedo",
            "metalness",
            "roughness",
            "diffuseEnv",
            "specularEnv",
            "diffuseLight",
            "specularLight",
            "occlusion",
            "lights",
            "ambient",
            "emissive",
        },
        values = {
            1,1,1,1,1,1,1,1,1,1,1,
        }
    }

    self.defaultEnvironmentMap = nil
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
--  position = vec3
--  rotation = quat
--  scale = vec3
--  AABB = {min = vec3, max = vec3} -- local to object position
--  draw = function(object, context)
--  material = {
--      metalness = float,
--      roughness = float,
--  }
-- }
function Renderer:render(objects, options)
    local context = options or {}
    context.objects = objects
    context.stats = {
        views = 0,
        drawnObjects = 0,
        culledObjects = 0,
        generatedCubemaps = 0,
        maxReflectionDepth = 0
    }

    context.cubemapFarPlane = context.cubemapFarPlane or 10

    context.views = context.views or {}

    self:renderView(context)

    local stats = context.stats
    print(
        "Views: " .. stats.views .. 
        ", Objects: " .. stats.drawnObjects .. 
        ", Culled: " .. stats.culledObjects .. 
        ", lights: " .. stats.lights .. 
        ", Cubemaps: " .. stats.generatedCubemaps .. "("..stats.maxReflectionDepth..")"
    )
end

function Renderer:layerVisibility(layer, on)
    if on ~= nil then
        self.drawLayer.values[layer] = on and 1 or 0
    end
    return self.drawLayer.values[layer] == 1
end

-- Push a new view to render
function Renderer:renderView(context)
    local newView = { nr = #context.views + 1}
    context.view = newView
    context.views[#context.views + 1] = newView

    self:renderContext(context)

    context.views[#context.views] = nil
    context.view = context.views[#context.views]
end

--- Prepares and draws a context
-- Context may already be partially prepared so parts can be reused
function Renderer:renderContext(context)
    local prepareFrame = (context.frame == nil) or not context.frame.prepared
    local prepareView = (context.view == nil) or not context.view.prepared

    if prepareFrame then
        self:prepareFrame(context)
    end

    if prepareView then
        self:prepareView(context)
    end

    -- Sorts objects into lists for frame and view
    self:prepareObjects(context)

    for i, shader in ipairs(self.standardShaders) do
        if prepareFrame then
            self:prepareShaderForFrame(shader, context)
        end
        if prepareView then
            self:prepareShaderForView(shader, context)
        end
    end

    self:drawContext(context)
end

-- Running once per frame
function Renderer:prepareFrame(context)
    -- Setup for this frame. Split objects for exampel?
    local frame = context.frame or {}

    frame.cubemapDepth = 0

    frame.prepared = true
    context.frame = frame
end

-- Running once per view
function Renderer:prepareView(context)
    -- Setup for a render pass from a specific view
    -- distance to view etc. 
    -- Needed once for player, once for the 6 cubemap sides
    -- make distance lists
    
    local view = context.view
    assert(view)

    -- Determine the modelView and projection matrices
    if not view.modelView then
        local modelView = lovr.math.newMat4()
        lovr.graphics.getViewPose(1, modelView, true)
        view.modelView = modelView
    else
        -- lovr.graphics.setViewPose(1, view.modelView, true)
        -- lovr.graphics.setViewPose(2, view.modelView, true)
    end

    if not view.projection then
        local projection = lovr.math.newMat4()
        lovr.graphics.getProjection(1, projection)
        view.projection = projection
    else
        -- lovr.graphics.setProjection(1, view.projection)
        -- lovr.graphics.setProjection(2, view.projection)
    end

    
    local x, y, z = view.modelView:unpack()
    view.cameraPosition = lovr.math.newVec3(x, y, z)
    view.modelViewProjection = lovr.math.newMat4(view.projection * view.modelView)
    view.frustum = self:getFrustum(view.modelViewProjection)

    view.objectToCamera = {}

    view.prepared = true
    context.view = view
    context.stats.views = context.stats.views + 1
end

--- Running once per view
function Renderer:prepareObjects(context)
    local frame = context.frame
    local view = context.view

    local prepareFrameObjects = frame.objects == nil
    local prepareViewObjects = view.objects == nil

    if prepareFrameObjects then
        frame.objects = {
            lights = OrderedMap(),
            needsCubemap = OrderedMap(),
        }
    end

    if prepareViewObjects then
        view.objects = {
            opaque = OrderedMap(),
            transparent = OrderedMap(),-- ordered furthest to nearest from camera
        }
    end

    for i, object in ipairs(context.objects) do
        local renderObject = self.cache[object.id]
        if not renderObject then 
            renderObject = { 
                id = object.id,
                position = lovr.math.newVec3(),
                lastPosition = lovr.math.newVec3(999999, 9999999),
            }
            self.cache[object.id] = renderObject
        end
        renderObject.source = object

        --TODO: find a quicker way
        renderObject.hasTransformed = not renderObject.position or renderObject.position:distance(object.position) > 0.0001
        renderObject.lastPosition:set(renderObject.position)
        renderObject.position:set(object.position)
        
        -- AABB derivates
        local AABB = object.AABB
        local minmaxdiv2 = (AABB.max - AABB.min) / 2
        renderObject.AABB = {
            min = lovr.math.newVec3(AABB.min),
            max = lovr.math.newVec3(AABB.max),
            center = lovr.math.newVec3(object.position + AABB.min + minmaxdiv2),
            radius = minmaxdiv2:length(),
        }

        -- Precalculate object vector and distance to camera
        local vectorToCamera = view.cameraPosition - renderObject.AABB.center
        local distanceToCamera = vectorToCamera:length()
        view.objectToCamera[object.id] = {
            vector = vectorToCamera,
            distance = distanceToCamera
        }

        if self:cullTest(renderObject, context) then
            -- object skipped for this pass
            context.stats.culledObjects = context.stats.culledObjects + 1
        else
            renderObject.culledLastFrame = false
            self:prepareObject(renderObject, context, prepareFrameObjects, prepareViewObjects)
        end
    end

    
    if prepareFrameObjects then
        
    end

    if prepareViewObjects then
        local list = view.objectToCamera
        view.objects.transparent:sort(function(a, b)
            return view.objectToCamera[a].distance < view.objectToCamera[b].distance
        end)

        -- Get a sorted list of need cubemaps
        view.objects.needsCubemap = OrderedMap(frame.objects.needsCubemap)
        list = view.objects.needsCubemap
        view.objects.needsCubemap:sort(function(a, b)
            return view.objectToCamera[a].distance > view.objectToCamera[b].distance
        end)
    end
end


function Renderer:prepareObject(renderObject, context, prepareFrameObjects, prepareViewObjects)
    local object = renderObject.source

    local view = context.view
    local frame = context.frame

    local function insert(list, object)
        list[object.id] = object
    end

    if prepareFrameObjects then
        if object.type == 'light' then
            insert(frame.objects.lights, renderObject)
        end

        if object.hasReflection or object.hasRefraction then
            renderObject.needsCubemap = true
            insert(frame.objects.needsCubemap, renderObject)
        end
    end
    
    if prepareViewObjects then
        if object.hasTransparency then
            -- print("Adding to transp " .. object.id)
            insert(view.objects.transparent, renderObject)
        else
            insert(view.objects.opaque, renderObject)
        end
    end
end

function Renderer:drawContext(context)
    local frame = context.frame
    local view = context.view

    if self.defaultEnvironmentMap then 
        lovr.graphics.setShader()
        lovr.graphics.setColor(1,1,1,1)
        lovr.graphics.skybox(self.defaultEnvironmentMap)
    end

    lovr.graphics.setShader(self.shader)

    -- Generate cubemaps where needed
    if not context.generatingReflectionMapForObject then 
        for id, object in view.objects.needsCubemap:iter() do
            if object.needsCubemap and not object.reflectionMap then 
                self:generateCubemap(object, context)
            end
        end
    end

    -- Draw normal objects
    for id, object in context.view.objects.opaque:iter() do
        self:drawObject(object, context)
    end

    -- Draw transparent objects
    for id, object in context.view.objects.transparent:iter() do
        self:drawObject(object, context)
    end

    -- Draw where we think camera is
    -- lovr.graphics.setColor(1, 0, 1, 1)
    -- local x, y, z = context.view.cameraPosition:unpack()
    -- lovr.graphics.box('fill', 0, 0, 0, 0.1, 0.1, 0.1)
end

function Renderer:drawObject(object, context)
    -- local useTransparency = object.hasTransparency and not context.skipTransparency
    -- local useRefraction = object.hasRefraction and not context.skipRefraction
    -- local useReflection = object.hasReflection and not context.skipReflection
    -- local useReflectionMap = useReflection or useRefraction
    
    -- -- if useReflectionMap and not cached.reflectionMap then 
    -- if useReflectionMap and not context.generatingReflectionMapForObject and not cached.reflectionMap then
    --     if (context.generatedCubeMapsCount or 0) < (context.generatedCubeMapsMax or 1) then
    --         context.generatedCubeMapsCount = (context.generatedCubeMapsCount or 0) + 1
    --         self:generateCubemap(object, cached, context)
    --     end
    -- end
    
    self:prepareShaderForObject(object, context)
    
    context.stats.drawnObjects = context.stats.drawnObjects + 1
    object.source:draw(object, context)
    
    if context.drawAABB then
        local bb = object.AABB
        local w, h, d = (bb.max - bb.min):unpack()
        local x, y, z = bb.center:unpack()
        lovr.graphics.box("line", x, y, z, math.abs(w), math.abs(h), math.abs(d))
    end
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
function Renderer:generateCubemap(renderObject, context)

    if context.generatingReflectionMapForObject == renderObject then
        assert(false)
    end

    local cubemap = renderObject.reflectionMap
    local cubemapSize = context.cubemapSize or 1024

    if not cubemap then
        local texture = lovr.graphics.newTexture(cubemapSize, cubemapSize, { 
            format = "rg11b10f",
            stereo = false,
            type = "cube"
        })
        local canvas = lovr.graphics.newCanvas(texture, { stereo = false })
        cubemap = { texture = texture, canvas = canvas }
        renderObject.reflectionMap = cubemap
    end

    context.stats.generatedCubemaps = context.stats.generatedCubemaps + 1
    context.frame.cubemapDepth = context.frame.cubemapDepth + 1
    context.stats.maxReflectionDepth = math.max(context.stats.maxReflectionDepth, context.frame.cubemapDepth)

    -- remove this object from needing cubemaps
    context.frame.objects.needsCubemap[renderObject.id] = nil
    context.view.objects.needsCubemap[renderObject.id] = nil
    renderObject.needsCubemap = false
    
	local view = { lovr.graphics.getViewPose(1) }
	local proj = { lovr.graphics.getProjection(1) }
    local farPlane = self:dynamicCubemapFarPlane(renderObject, context)
	lovr.graphics.setProjection(1, mat4():perspective(0.1, farPlane, math.pi/2, 1))
    lovr.graphics.setShader(self.cubemapShader)
    
	local center = renderObject.AABB.center
	for i,pose in ipairs{
		lookAt(center, center + vec3(1,0,0), vec3(0,-1,0)),
		lookAt(center, center - vec3(1,0,0), vec3(0,-1,0)),
		lookAt(center, center + vec3(0,1,0), vec3(0,0,1)),
		lookAt(center, center - vec3(0,1,0), vec3(0,0,-1)),
		lookAt(center, center + vec3(0,0,1), vec3(0,-1,0)),
		lookAt(center, center - vec3(0,0,1), vec3(0,-1,0)),
	} do
		local canvas = cubemap.canvas

        context.generatingReflectionMapForObject = renderObject
        
		canvas:setTexture(cubemap.texture, i)
		canvas:renderTo(function ()
            local r,g,b,a = lovr.graphics.getBackgroundColor()
			lovr.graphics.clear(r, g, b, a, 1, 0)
			lovr.graphics.setViewPose(1, pose, true)
            self:renderView(context)
		end)
        lovr.math.drain()
	end
    context.generatingReflectionMapForObject = nil
    lovr.graphics.setProjection(1,unpack(proj))
	lovr.graphics.setViewPose(1,unpack(view))
    lovr.graphics.setShader(self.shader)

    context.frame.cubemapDepth = context.frame.cubemapDepth - 1
end

function Renderer:prepareShaderForFrame(shader, context)
    local positions = {}
    local colors = {}
    local lights = context.frame.objects.lights
    for id, light in lights:iter() do
        local x, y, z = light.source.position:unpack()
        table.insert(positions, {x, y, z})
        table.insert(colors, light.source.light.color)
    end
    self.lightsBlock:send('lightCount', #positions)
    self.lightsBlock:send('lightColors', colors)
    self.lightsBlock:send('lightPositions', positions)

    for i, name in ipairs(self.drawLayer.names) do
        shader:send("draw_"..name, self.drawLayer.values[i])
    end

    context.stats.lights = #lights
end

function Renderer:prepareShaderForView(shader, context)
    
end

function Renderer:prepareShaderForObject(object, context)
    local shader = lovr.graphics.getShader()
    if not shader then return end
    local material = object.source.material or {}
    shader:send("alloMetalness", material.metalness or 1)
    shader:send("alloRoughness", material.roughness or 1)

    local envMap = object.reflectionMap and object.reflectionMap.texture or self.defaultEnvironmentMap
    if not envMap then 
        shader:send("alloEnvironmentMapType", 0)
    elseif envMap:getType() == "cube" then
        shader:send("alloEnvironmentMapType", 1);
        shader:send("alloEnvironmentMapCube", envMap)
    else
        shader:send("alloEnvironmentMapType", 2);
        shader:send("alloEnvironmentMapSpherical", envMap)
    end
end

function Renderer:cullTest(renderObject, context)
    -- never cull some types
    if renderObject.source.light then 
        return false
    end

    -- test frustrum
    local AABB = renderObject.AABB

    -- local farPlaneDistance = 10
    -- if renderObject.distanceToCamera - AABB.radius > farPlaneDistance then
    --     return true
    -- end

    -- print(renderObject.distanceToCamera)
    
    local frustum = context.view.frustum
    for i = 1, 6 do -- 5 because skipping far plane as handled above
        local p = frustum[i]
        local e = renderObject.AABB.center:dot(vec3(p.x, p.y, p.z)) + p.d + renderObject.AABB.radius
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

function Renderer:dynamicCubemapFarPlane(object, context)
    -- TODO: something exponential so detail near max creep up slowly and near min faster
    local min = object.AABB.radius
    local max = object.AABB.radius + context.cubemapFarPlane
    local distanceToCamera = context.views[1].objectToCamera[object.id].distance
    local factor = 1 - (distanceToCamera / max)
    local k = min + max * factor
    local result = math.min(math.max(min, k), max)
    return result
end