local version = _VERSION:match("%d+%.%d+")
package.path = 'lib/share/lua/' .. version .. '/?.lua;lib/share/lua/' .. version .. '/?/init.lua;' .. package.path
package.path = '/sdcard/Android/data/org.lovr.app/files/lib/share/lua/' .. version .. '/?.lua;lib/share/lua/' .. version .. '/?/init.lua;' .. package.path
package.cpath = 'lib/lib/lua/' .. version .. '/?.so;' .. package.cpath
local pp = require('pl.pretty').dump
local tablex = require('pl.tablex')

local lovr = lovr -- help the vscode lua plugin a bit
vec3 = lovr.math.vec3
newVec3 = lovr.math.newVec3
newMat4 = lovr.math.newMat4
require 'renderer'

local cubemap = {}
local cubemapSize = 32
cubemap.textures = {
    lovr.graphics.newTexture(cubemapSize, cubemapSize, { format = "rg11b10f", stereo = false, type = "cube" }),
    lovr.graphics.newTexture(cubemapSize, cubemapSize, { format = "rg11b10f", stereo = false, type = "cube" }),
    index = 2,
}
cubemap.texture = cubemap.textures[cubemap.textures.index]

cubemap.canvases = {
    lovr.graphics.newCanvas(cubemap.textures[1]),
    lovr.graphics.newCanvas(cubemap.textures[2]),
    index = 2,
}
cubemap.canvas = cubemap.canvases[cubemap.canvases.index]

local function switcheroo()
	cubemap.last_texture = cubemap.texture
	cubemap.textures.index = ((cubemap.textures.index + 1) % #cubemap.textures) + 1
	cubemap.texture = cubemap.textures[cubemap.textures.index]
	
	cubemap.last_canvas = cubemap.canvas
	cubemap.canvases.index = ((cubemap.canvases.index + 1) % #cubemap.canvases) + 1
	cubemap.canvas = cubemap.canvases[cubemap.canvases.index]
end

renderer = nil

function lovr.load()
    renderer = Renderer()
    if not model then 
        model = lovr.graphics.newModel("bkd_main room_shell.glb")
        torso = lovr.graphics.newModel("torso.glb")
        helmet = lovr.graphics.newModel("helmet.glb")
        lightsBlock = lovr.graphics.newShaderBlock('uniform', {
            lightCount = 'int',
            lightPositions = { 'vec4', 32 },
            lightColors = { 'vec4', 32 },
        }, { usage = 'stream'})
    end

    require 'shader'
    shader = Shader():generate()
    shader:send('specularStrength', 0.5)
    shader:send('metallic', 500.0)
    shader:send('viewPos', { 0.0, 0.0, 0.0} )
    shader:send('ambience', { 0.1, 0.1, 0.1, 1.0 })
    -- shader:send('ambience', { 1, 1, 1, 1.0 })

    depthShader = require 'fill_depth_shader'

    lovr.graphics.setBackgroundColor(.18, .18, .20)
    lovr.graphics.setCullingEnabled(true)

    local width, height = lovr.headset.getDisplayDimensions()
    local size = math.max(width, height)
    canvas = lovr.graphics.newCanvas(size, size, {
        stereo = false,
        depth = { format = 'd16', readable = true },
    })
    
    -- cube = {
    --     left   = lovr.graphics.newTexture(size, size, 1, {}),
    --     right  = lovr.graphics.newTexture(size, size, 1, {}),
    --     top    = lovr.graphics.newTexture(size, size, 1, {}),
    --     bottom = lovr.graphics.newTexture(size, size, 1, {}),
    --     front  = lovr.graphics.newTexture(size, size, 1, {}),
    --     back   = lovr.graphics.newTexture(size, size, 1, {}),
    -- }
    -- cube.map = lovr.graphics.newTexture(cube)


end

local lights = {
  { color = {1, 0, 0}, pos = {0, 0, 0} },
  { color = {0, 1, 0}, pos = {0, 0, 0} },
  { color = {0, 0, 1}, pos = {0, 0, 0} },
  { color = {1, 1, 1}, pos = {0, 0, 0} },
}

function all(k, t)
  local r = {}
  for _, tt in ipairs(t) do
    table.insert(r, tt[k])
  end
  return r
end

if not time then 
    paused = true
    time = 0
end
function lovr.update(dt)
    if not paused then 
        time = time + dt
    end
    for i, light in ipairs(lights) do
        local t = time + ((math.pi*2)/#lights) * i
        light.pos = { math.sin(t)*2, 1.7 + math.sin(t * 0.3), math.cos(t) - 3 }
    end
    lightsBlock:send('lightPositions', all('pos', lights) )
    lightsBlock:send('lightColors', all('color', lights) )
    lightsBlock:send('lightCount', #lights)
    -- lightsBlock:send('lightCount', 0)
    shader:send('time', time)
    -- makeCube()

    if lovr.headset.wasPressed("right", "a") then 
        paused = not paused
    end
end
saved = false

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

function render(makingCubemap)
    lovr.graphics.setColor(1, 1, 1, 1)
    shader:send("reflectionStrength", makingCubemap and 0 or 1)
    lovr.graphics.setBlendMode("alpha", "premultiplied")
    lovr.graphics.clear()
    lovr.graphics.setColor(1, 1, 1, 0.1)
    lovr.graphics.setShader(shader)
    lovr.graphics.sphere(-1.2, 1.7, -3, 0.5, -time * 0.5, 0, 1, 0)
    -- lovr.graphics.sphere(0, 1.7, -3, 0.5)
    torso:draw(0, 1.2, -3, 3, time*0.5, 0, 1, 0)

    lovr.graphics.box("fill", 1.1, 2.4, -3, 0.8, 0.5, 1, -time, 1, 1, 0)
    
    lovr.graphics.setColor(0.3, 0.3, 0.7, 0.1)
    shader:send("metallic", 1)
    lovr.graphics.sphere(-0.9, math.sin(time*0.9) + 1.7, 5, 0.5, -time * 0.5, 0, 1, 0)
    lovr.graphics.sphere(0, math.sin(time) + 1.7, 5.8, 0.5, -time * 0.5, 0, 1, 0)
    lovr.graphics.sphere(0.9, math.sin(time*1.1) + 1.7, 5, 0.5, -time * 0.5, 0, 1, 0)
    lovr.graphics.setColor(1, 1, 1, 1)
    shader:send("metallic", 500)    
    if not makingCubemap then 
        lovr.graphics.setColor(1, 1, 1, 1)
        lovr.graphics.setShader(shader)
        helmet:draw(0, 2.6, -3, 0.2, time*0.0, 0, 1, 0)
    end

    for _, light in ipairs(lights) do
        lovr.graphics.setColor(table.unpack(light.color))
        lovr.graphics.sphere(light.pos[1], light.pos[2], light.pos[3], 0.1)
    end
    model:draw()
end


objects = {
    sphere1 = {
        id = "sphere1",
        position = newVec3(-1.2, 1.7, -3),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            lovr.graphics.setColor(1, 0.5, 0.5, 1)
            local x, y, z = object.position:unpack()
            lovr.graphics.sphere(x, y, z, object.AABB.radius)
        end,
        hasTransparency = true,
        hasReflection = true,
    },
    sphere2 = {
        id = "sphere2",
        position = newVec3(0, 1.7, -3),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            lovr.graphics.setColor(1, 1, 1, 0)
            local x, y, z = object.position:unpack()
            lovr.graphics.sphere(x, y, z, object.AABB.radius)
        end,
        hasTransparency = true,
        hasReflection = true,
    },
    sphere3 = {
        id = "sphere3",
        position = newVec3(1.2, 1.7, -3),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            lovr.graphics.setColor(0.5, 0.5, 1, 1)
            local x, y, z = object.position:unpack()
            lovr.graphics.sphere(x, y, z, object.AABB.radius)
        end,
        hasTransparency = false,
        hasReflection = false,
    },
    helmet = {
        id = "helmet",
        position = newVec3(0, 3.6, -3),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            lovr.graphics.setColor(1, 1, 1, 1)
            local x, y, z = object.position:unpack()
            helmet:draw(x, y, z, 0.2, time*0.5, 0, 1, 0)
        end,
        hasTransparency = true,
        hasReflection = true,
    }
}
    

objects = {}
for metalness = 1, 10 do
    for roughness = 1, 10 do
        local helm = metalness == 5 and roughness == 5
        local shiny = helm or (metalness == 6 and roughness < 6)
        local zero = metalness == 0 and roughness == 0
        
        objects["ball " .. metalness .. roughness] = {
            id = "ball " .. metalness .. roughness,
            position = newVec3(metalness - 5, roughness - 5, -3),
            AABB = {
                min = newVec3(-0.4, -0.4, -0.4), 
                max = newVec3(0.4, 0.4, 0.4), 
            },
            material = {
                metalness = metalness / 10,
                roughness = roughness / 10,
            },
            draw = function(object, context)
                local x, y, z = object.position:unpack()
                if helm then 
                    lovr.graphics.setColor(1, 1, 1, 1)
                    helmet:draw(x, y, z, 0.4)
                else
                    if zero then 
                        lovr.graphics.setColor(1, 1, 1, 1)
                    else
                        lovr.graphics.setColor(shiny and 0.3 or 1.0, 0.8, 0.8, shiny and 0.8 or 1.0)
                    end
                    lovr.graphics.sphere(x, y, z, 0.4)
                end
            end,
            hasTransparency = shiny,
            hasReflection = shiny,
        }
    end
end

function lovr.draw()
    -- add lights to the object list if needed

    local proj = lovr.math.mat4():perspective(0.1, 10, 60 * math.pi/180, 1)
    -- lovr.graphics.setProjection(1, proj)
    -- lovr.graphics.setProjection(2, proj)
    
    for i, light in ipairs(lights) do
        local id = 'light ' .. i
        local object = objects[id]
        if object then
            object.position:set(table.unpack(light.pos))
        else
            objects[id] = {
                id = 'light ' .. i,
                type = 'light',
                position = newVec3(table.unpack(light.pos)),
                AABB = {
                    min = newVec3(-0.1, -0.1, -0.1), 
                    max = newVec3(0.1, 0.1, 0.1), 
                },
                draw = function (object, context)
                    local x, y, z = object.position:unpack()
                    lovr.graphics.setColor(table.unpack(object.light.color))
                    lovr.graphics.sphere(x, y, z, 0.1)
                end,
                light = light,
            }
        end
    end
    renderer:render(tablex.values(objects), {drawAABB = true})
    
    -- lovr.graphics.sphere(0,0,0,0.2)
end

function lovr.draw2()
    local view={lovr.graphics.getViewPose(1)}
	local proj={lovr.graphics.getProjection(1)}
	lovr.graphics.setProjection(1,mat4():perspective(0.1,1000,math.pi/2,1))
	local center=vec3(0, 2.6, -3)
	switcheroo()

	for i,view in ipairs{
		lookAt(center,center+vec3(1,0,0),vec3(0,-1,0)),
		lookAt(center,center-vec3(1,0,0),vec3(0,-1,0)),
		lookAt(center,center+vec3(0,1,0),vec3(0,0,1)),
		lookAt(center,center-vec3(0,1,0),vec3(0,0,-1)),
		lookAt(center,center+vec3(0,0,1),vec3(0,-1,0)),
		lookAt(center,center-vec3(0,0,1),vec3(0,-1,0)),
	} do
		local face=cubemap.canvas
		face:setTexture(cubemap.texture,i)
		face:renderTo(function ()
			local r,g,b,a=lovr.graphics.getBackgroundColor()
            -- shader:send("cubemap", cubemap.last_texture)
			lovr.graphics.clear(r,g,b,a,1,0)
			lovr.graphics.setViewPose(1,view,true)
            render(true)
--    			draw_objects(cubemap.last_texture, true)
		end)
	end
	lovr.graphics.setProjection(1,unpack(proj))
	lovr.graphics.setViewPose(1,unpack(view))
    shader:send("cubemap", cubemap.texture)
    render()
    if cubemap.texture then 
        lovr.graphics.setShader()
        -- lovr.graphics.skybox(cubemap.texture)
    end
end

function lovr.keypressed(key, scancode, repeated)
    if repeated then return end
    if key == 'm' then 
        print("making")
        makeCube()
    end
    if key == 'p' then 
        paused = not paused
    end
end
