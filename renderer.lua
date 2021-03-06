--- Renderer
-- Handles drawing of objects
-- @classmod Renderer


local class = require('pl.class')
local pp = require('pl.pretty').dump
local tablex = require('pl.tablex')
local OrderedMap = require('pl.OrderedMap')

require 'shader'

local is_desktop = lovr.headset.getDriver() == "desktop"

Renderer = class.Renderer()
local lovr = lovr -- help vscode lua plugin a bit

function Renderer:_init()
    --- Stores some information of objects
    self.cache = {}

    self.shaderObj = Shader()
    self.shader = self.shaderObj:generate({lights = true, debug = is_desktop})
    self.cubemapShader = self.shaderObj:generate({stereo = false, lights = false})

    self.standardShaders = {
        self.shader, 
        self.cubemapShader
    }
    
    self.lightsBlock = self.shaderObj.lightsBlock

    self.frameCount = 0
    self.viewCount = 0
    self.lastFrameNumber = 0

    self.cubemapPool = {}

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
            "normalMap",
            "tonemap",
        },
        values = { 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
        only   = nil,
    }

    -- self.debug = "distance"
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
    context.sourceObjects = objects
    context.stats = {
        views = 0, -- number of passes rendered
        drawnObjects = 0, -- number of objects drawn (counts same object each pass)
        culledObjects = 0, -- number of objects that was not drawn (counts same object each pass)
        generatedCubemaps = 0, -- number of cubemaps generated
        maxReflectionDepth = 0, -- max reached depth (cubemap gen triggers a cubemap gen. This should not happen.)
        cubemapTargets = {}, -- object id's that got a cubemap generated this frame
        debugText = {}, -- just strings the renderer would like to output to the screen
    }

    context.cubemapFarPlane = context.cubemapFarPlane or 10

    context.views = context.views or {}

    self:renderView(context)

    self.lastFrameNumber = context.frame.nr

    return context.stats
end

function Renderer:layerVisibility(layer, on, only)
    if on ~= nil then
        self.drawLayer.values[layer] = on and 1 or 0
        if only or only == nil then
            self.drawLayer.only = only and layer or nil
        end
    end
    return self.drawLayer.values[layer] == 1, self.drawLayer.only == layer
end

-- Push a new view to render
function Renderer:renderView(context, newView)
    newView = newView or {}
    newView.nr = #context.views + 1

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

    frame.nr = self.lastFrameNumber + 1
    frame.cubemapDepth = 0
    frame.cubemapLimit = { 
        count = 0, 
        max = is_desktop and 2 or 0,
        maxDepth = is_desktop and 1 or 1,
    }

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

    
    if view.nr == 1 then 
        -- viewModel is not equal to camera position. 
        -- Use it for the subpasses for now but use headset pose for frame
        local x, y, z = lovr.headset.getPose()
        view.cameraPosition = lovr.math.newVec3(x, y, z)
    elseif not view.cameraPosition then
        local x, y, z = view.modelView:unpack()
        view.cameraPosition = lovr.math.newVec3(-x, -y, -z)
    end
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


    -- .objects : table of sorted tables of objects to include in the render
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
            culled = OrderedMap(), -- objects not drawn this view
            needsCubemap = OrderedMap(), -- objects that needs a fresh cubemap
        }
    end

    -- Objects that we pick from are either
    --  view.sourceObjects: a previous pass has pre-culled renderObjects to work with
    --  frame.sourceObjects: there was a culling pass at frame level. These are source objects
    --  context.sourceObjects: all the source objects passed to self:render
    local renderObjects = nil
    if view.renderObjects then
        renderObjects = view.renderObjects
    elseif frame.renderObjects then
        renderObjects = frame.renderObjects
    end

    if renderObjects then
        for i, renderObject in ipairs(renderObjects) do
            -- Precalculate object vector and distance to camera
            local vectorToCamera = view.cameraPosition - renderObject.AABB.center
            local distanceToCamera = vectorToCamera:length()
            view.objectToCamera[renderObject.id] = {
                vector = vectorToCamera,
                distance = distanceToCamera
            }

            self:prepareObject(renderObject, context, prepareFrameObjects, prepareViewObjects)
        end    
    else
        for i, object in ipairs(context.sourceObjects) do
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

            -- TODO: smarts based on changes in material
            if object.material then
                renderObject.material = {}
                renderObject.material.roughness = object.material.roughness or 1
                renderObject.material.metalness = object.material.metalness or 1
            else
                renderObject.material = {
                    roughness = 1,
                    metalness = 1,
                }
            end
            
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

            self:prepareObject(renderObject, context, prepareFrameObjects, prepareViewObjects)
        end
    end

    
    if prepareFrameObjects then
        assert(view.nr == 1)
    end

    if prepareViewObjects then
        local list = view.objectToCamera
        view.objects.transparent:sort(function(a, b)
            return view.objectToCamera[a].distance < view.objectToCamera[b].distance
        end)

        view.objects.opaque:sort(function(a, b)
            return view.objectToCamera[a].distance > view.objectToCamera[b].distance
        end)

        if context.frame.cubemapDepth >= context.frame.cubemapLimit.maxDepth then
            view.objects.needsCubemap = OrderedMap()
        else
            -- Sort the list of objects needing cubemaps
            local list = view.objects.needsCubemap
            local scores = {}
            local getScore = self.objectCubemapScore
            view.objects.needsCubemap:sort(function(aid, bid)
                local a = list[aid]
                local b = list[bid]
                assert(a and b)
                local a_score = scores[aid] or getScore(self, a, context)
                local b_score = scores[bid] or getScore(self, b, context)
                
                scores[aid] = a_score
                scores[bid] = b_score
                return a_score > b_score
            end)
        end
    end
end

function Renderer:objectCubemapScore(object, context)
    local distanceToCamera = context.view.objectToCamera[object.id].distance - object.AABB.radius
    local frameNr = context.frame.nr
    return  1/(distanceToCamera * distanceToCamera) -- smaller is better
            * (object.reflectionMap and (frameNr - object.reflectionMap.source.frameNr) or frameNr) -- larger is better
            * (1.1 - object.material.roughness)
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

        frame.renderObjects = frame.renderObjects or {}
        table.insert(frame.renderObjects, renderObject)
    end
    
    if prepareViewObjects then
        if self:cullTest(renderObject, context) then
            -- object skipped for this pass
            context.stats.culledObjects = context.stats.culledObjects + 1
            insert(view.objects.culled, renderObject)
        else
            if renderObject.needsCubemap then
                insert(view.objects.needsCubemap, renderObject)
            end
            if object.hasTransparency then
                insert(view.objects.transparent, renderObject)
            else
                insert(view.objects.opaque, renderObject)
            end
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
    for id, object in view.objects.needsCubemap:iter() do
        if self:shouldGenerateCubemap(object, context) then 
            self:generateCubemap(object, context)
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


function Renderer:shouldGenerateCubemap(object, context)
    return
        context.frame.cubemapLimit.count < context.frame.cubemapLimit.max and
        object.needsCubemap and 
        context.frame.cubemapDepth < context.frame.cubemapLimit.maxDepth
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
    lovr.graphics.setColor(1,1,1,1)
    context.stats.drawnObjects = context.stats.drawnObjects + 1

    if self.debug == "distance" then
        lovr.graphics.setShader()
        local d = context.views[1].objectToCamera[object.id].distance/10
        lovr.graphics.setColor(d, d, d, 1)
    end

    object.source.draw(object, context)
    
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


function Renderer:findCubemap(renderObject, context)
    if renderObject.reflectionMap then
        return renderObject.reflectionMap
    end
    -- Objects that were in last frame and are culled in this frame
    for id, object in context.view.objects.culled:iter() do
        if object.reflectionMap then
            local map = object.reflectionMap
            object.reflectionMap = nil
            return map
        end
    end
end

--- Generates a cube map from the point of object
function Renderer:generateCubemap(renderObject, context)

    if context.generatingReflectionMapForObject == renderObject then
        assert(false)
    end

    local cubemap = renderObject.reflectionMap or self:findCubemap(renderObject, context)
    local cubemapSize = context.cubemapSize or 1024


    if not cubemap then
        print("New cm for " .. renderObject.id .. " in frame " .. context.frame.nr, cubemapSize .. "x" .. cubemapSize)
        local texture = lovr.graphics.newTexture(cubemapSize, cubemapSize, { 
            format = "rg11b10f",
            stereo = not is_desktop,
            type = "cube"
        })
        cubemap = { 
            texture = texture,
            source = {}
        }
        renderObject.reflectionMap = cubemap
    end
    local canvas = self.cubemapCanvas
    if not canvas then
        canvas = lovr.graphics.newCanvas(cubemap.texture, { stereo = not is_desktop })
        self.cubemapCanvas = canvas
    end

    cubemap.source.frameNr = context.frame.nr

    context.stats.generatedCubemaps = context.stats.generatedCubemaps + 1
    context.frame.cubemapDepth = context.frame.cubemapDepth + 1
    context.frame.cubemapLimit.count = context.frame.cubemapLimit.count + 1
    context.stats.maxReflectionDepth = math.max(context.stats.maxReflectionDepth, context.frame.cubemapDepth)
    table.insert(context.stats.cubemapTargets, renderObject.id)
    -- remove this object from needing cubemaps
    context.frame.objects.needsCubemap[renderObject.id] = nil
    context.view.objects.needsCubemap[renderObject.id] = nil
    renderObject.needsCubemap = false
    
	local view = { lovr.graphics.getViewPose(1) }
	local proj = { lovr.graphics.getProjection(1) }
    -- local farPlane = self:dynamicCubemapFarPlane(renderObject, context)
    -- TODO: dynamic farplane did not work when you are INSIDE models as they will be clipped
    -- Need to adjust it to `if inside an AABB set farplane to furthest corner of its
    -- and then only include x number of objects in draw instead. Or just do that instead of clipping
    local farPlane = 1000
    cubemap.source.lod = farPlane
	lovr.graphics.setProjection(1, mat4():perspective(0.1, farPlane, math.pi/2, 1))

    lovr.graphics.setShader(self.cubemapShader)

    
	local center = renderObject.AABB.center
    -- Get a list of objects that are within a distance based on cm quality

    local maxDistance = 10 - context.views[1].objectToCamera[renderObject.id].distance-- self:dynamicCubemapFarPlane(renderObject, context)
    local maxDistance = self:dynamicCubemapFarPlane(renderObject, context)

    local objects = self:objectsWithinDistanceOf(context.frame.renderObjects, center, maxDistance, context)
	for i,pose in ipairs{
		lookAt(center, center + vec3(1,0,0), vec3(0,-1,0)),
		lookAt(center, center - vec3(1,0,0), vec3(0,-1,0)),
		lookAt(center, center + vec3(0,1,0), vec3(0,0,1)),
		lookAt(center, center - vec3(0,1,0), vec3(0,0,-1)),
		lookAt(center, center + vec3(0,0,1), vec3(0,-1,0)),
		lookAt(center, center - vec3(0,0,1), vec3(0,-1,0)),
	} do
		canvas:setTexture(cubemap.texture, i)
		canvas:renderTo(function ()
            local r,g,b,a = lovr.graphics.getBackgroundColor()
			lovr.graphics.clear(r, g, b, a, 1, 0)
			lovr.graphics.setViewPose(1, pose, true)
            self:renderView(context, {
                generatingReflectionMapForObject = renderObject,
                cameraPosition = center,
                renderObjects = objects
            })
		end)
        lovr.math.drain()
	end
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
        shader:send("only_"..name, self.drawLayer.only == i and 1 or 0)
    end

    context.stats.lights = #lights
end

function Renderer:prepareShaderForView(shader, context)
    
end

function Renderer:prepareShaderForObject(object, context)
    local shader = lovr.graphics.getShader()
    if not shader then return end
    local material = object.material
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

function Renderer:pointInAABB(point, aabb)
    local px, py, pz = point:unpack()
    local minx, miny, minz = (aabb.center + aabb.min):unpack()
    local maxx, maxy, maxz = (aabb.center + aabb.max):unpack()
    return (px > minx and py > miny and pz > minz) and (px < maxx and py < maxy and pz < maxz)
end

-- Returns a new list of renderObjects from `renderObjects` that are within `distance` of `position`
function Renderer:objectsWithinDistanceOf(renderObjects, position, distance, context)
    local result = {}
    if distance < 0 then return result end
    for i, object in ipairs(renderObjects) do
        local length = position:distance(object.AABB.center) - object.AABB.radius
        if (length < distance) then
            table.insert(result, object)
        end
    end
    return result
end

-- returning true means the object is culled and not rendered.
function Renderer:cullTest(renderObject, context)

    -- never cull some types
    if renderObject.source.light then
        return false
    end

    -- always cull some
    
    if renderObject.source.visible == false then
        return true
    end

    -- test frustrum
    local AABB = renderObject.AABB

    -- local farPlaneDistance = 10
    -- if renderObject.distanceToCamera - AABB.radius > farPlaneDistance then
    --     return true
    -- end

    
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


function Renderer:distanceToObject(object, fromPosition, context)
    local aabb = object.AABB
    return fromPosition:distance(aabb.center) - aabb.radius
end

function Renderer:dynamicCubemapFarPlane(object, context)
    -- TODO: something exponential so detail near max creep up slowly and near min faster
    local min = object.AABB.radius
    local max = object.AABB.radius + context.cubemapFarPlane
    local distanceToCamera = context.views[1].objectToCamera[object.id].distance
    local factor = (1 - (distanceToCamera / (max-min))) * object.material.roughness
    local k = min + max * factor
    local result = math.min(math.max(min, k), max)
    return result
end

function Renderer:borrowCubemap(lod, context)
    local best = nil
    local bestDistance = nil
    local bestIndex = nil
    local frame = context.frame
    local pool = frame.cubemapPool

    for i, map in ipairs(pool) do
        if map.lod == lod then
            best = map
            bestIndex = i
            goto done
        elseif not best then
            best = map
            bestIndex = i
            bestDistance = math.abs(map.lod - lod)
        else
            local dist = math.abs(map.lod - lod)
            if dist < bestDistance then
                best = map
                bestDistance = dist
            end
        end
        ::done::
        if best then
            table.remove(pool, bestIndex)
        end
        return best
    end
end
