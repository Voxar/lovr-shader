local version = _VERSION:match("%d+%.%d+")
package.path = 'lib/share/lua/' .. version .. '/?.lua;lib/share/lua/' .. version .. '/?/init.lua;' .. package.path
package.path = '/sdcard/Android/data/org.lovr.app/files/lib/share/lua/' .. version .. '/?.lua;lib/share/lua/' .. version .. '/?/init.lua;' .. package.path
package.cpath = 'lib/lib/lua/' .. version .. '/?.so;' .. package.cpath
local pp = require('pl.pretty').dump
local tablex = require('pl.tablex')
local stringx = require('pl.stringx')

local lovr = lovr -- help the vscode lua plugin a bit
vec3 = lovr.math.vec3
newVec3 = lovr.math.newVec3
newMat4 = lovr.math.newMat4
require 'renderer'

renderer = nil
local drawAABBs = false

environmentMaps = {
    "equirectangular.png",
    "alien.jpg",
    "beach.jpg",
    "bright.jpg",
    "cave.jpg",
    "city.jpg",
    "cool.jpg",
    "dark.jpg",
    "factory.jpg",
    "forest.jpg",
    "home.jpg",
    "museum.jpg",
    "studio.jpg",
    "thratre.jpg",
    "underwater.jpg",
}
selectedEnvironmentMap = 1

local font = lovr.graphics.newFont(128)  -- Font appropriate for screen-space usage
font:setFlipEnabled(true)
font:setPixelDensity(1)

function lovr.load()
    renderer = Renderer()
    if not model then 
        model = lovr.graphics.newModel("bkd_main room_shell.glb")
        torso = lovr.graphics.newModel("torso.glb")
        helmet = lovr.graphics.newModel("helmet.glb")
    end

    lovr.graphics.setBackgroundColor(.18, .18, .20)
    lovr.graphics.setCullingEnabled(true)

    renderer.defaultEnvironmentMap = lovr.graphics.newTexture(environmentMaps[selectedEnvironmentMap], {mipmaps = true})
    scene = scenes[selectedScene]
end

local lightMult = 1
local lights = {
  { color = {1, 0, 0}, pos = {0, 0, 0} },
  { color = {0, 1, 0}, pos = {0, 0, 0} },
  { color = {0, 0, 1}, pos = {0, 0, 0} },
  { color = {1, 1, 1}, pos = {0, 0, 0} },
  { color = {3, 3, 3}, pos = {0, 0, 0} },
}

function all(k, t)
  local r = {}
  for _, tt in ipairs(t) do
    table.insert(r, tt[k])
  end
  return r
end

time = 0


house = {
    id = "house",
    visible = true,
    position = newVec3(0,0,0),
    AABB = {
        min = newVec3(-10, -10, -10), 
        max = newVec3(10, 10, 10), 
    },
    draw = function(object, context)
        lovr.graphics.setColor(1, 1, 1, 1)
        model:draw(0,-6,0,2.5)
    end,
    hasTransparency = true,
    hasReflection = true,
}

scenes = {}
selectedScene = "helm"
scenes.helm = {
    house = house,
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
            lovr.graphics.sphere(x, y, z, 0.5)
        end,
        update = function (object, time)
            object.position.x = math.sin(time)*2
            object.position.z = -3 + math.cos(time)*2
        end,
        material = {
            metalness = 1,
            roughness = 0
        },
        hasTransparency = true,
        hasReflection = true,
    },
    helmet = {
        id = "helmet",
        position = newVec3(0, 1.7, -3),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            lovr.graphics.setColor(1, 1, 1, 1)
            local x, y, z = object.position:unpack()
            helmet:draw(x, y, z, 0.8, -time*0.5, 0, 1, 0)
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
            lovr.graphics.sphere(x, y, z, 0.5)
        end,
        update = function (object, time)
            object.position.x = math.sin(time+math.pi)*2
            object.position.z = -3 + math.cos(time+math.pi)*2
        end,
        material = {
            metalness = 0,
            roughness = 1
        },
        hasTransparency = false,
        hasReflection = false,
    },
}

scenes.ballgrid = {house = house}
local count = {x = 5, y = 5}
for roughness = 1, count.x do
    for metalness = 1, count.y do
        local helm = metalness == 5 and roughness == 5
        local shiny = true
        local zero = metalness == 0 and roughness == 0
        
        scenes.ballgrid["ball " .. metalness .. roughness] = {
            id = "ball " .. metalness .. roughness,
            position = newVec3(roughness - count.x/2, metalness - count.y/2, -3),
            AABB = {
                min = newVec3(-0.4, -0.4, -0.4), 
                max = newVec3(0.4, 0.4, 0.4), 
            },
            material = {
                metalness = helm and 1 or (metalness-1) / 4,
                roughness = helm and 1 or (roughness-1) / 4,
            },
            draw = function(object, context)
                lovr.graphics.setColor(1, 1, 1, 1)
                local x, y, z = object.position:unpack()
                if helm then 
                    torso:draw(x, y-0.3, z, 2, time*0.5, 0, 1)
                    -- helmet:draw(x, y, z, 0.4, time*0.5, 0, 1, 0)
                else
                    if zero then 
                        lovr.graphics.setColor(1, 1, 1, 1)
                    else
                        -- lovr.graphics.setColor(1, 0.0, 0.0, 1)
                    end
                    lovr.graphics.sphere(x, y, z, 0.4)
                end
            end,
            hasTransparency = shiny,
            hasReflection = shiny,
        }
    end
end

avatar = {
    torso = lovr.graphics.newModel("torso.glb"),
    left = lovr.graphics.newModel("left-hand.glb"),
    right = lovr.graphics.newModel("right-hand.glb"),
    head = lovr.graphics.newModel("head.glb"),
}
scenes.avatar = {
    torso = {
        id = "torso",
        position = newVec3(0, 1.2, -1),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            local x, y, z = object.position:unpack()
            avatar.torso:draw(x, y, z)
        end,
        update = function (object, time)
        end,
        hasTransparency = true,
        hasReflection = true,
    },
    head = {
        id = "head",
        position = newVec3(0, 1.7, -1),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            local x, y, z = object.position:unpack()
            avatar.head:draw(x, y, z)
        end,
        update = function (object, time)
            
        end,
        hasTransparency = true,
        hasReflection = true,
    },

    left = {
        id = "left",
        position = newVec3(0.2, 1.4, -0.8),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            local x, y, z = object.position:unpack()
            avatar.left:draw(x, y, z)
        end,
        update = function (object, time)
            
        end,
        hasTransparency = true,
        hasReflection = true,
    },

    right = {
        id = "right",
        position = newVec3(-0.2, 1.4, -0.8),
        AABB = {
            min = newVec3(-0.5, -0.5, -0.5), 
            max = newVec3(0.5, 0.5, 0.5), 
        },
        draw = function(object, context)
            local x, y, z = object.position:unpack()
            avatar.right:draw(x, y, z)
        end,
        update = function (object, time)
            
        end,
        hasTransparency = true,
        hasReflection = true,
    },
    house = house,
}
selectedScene = "avatar"


function lovr.update(dt)
    if not paused then 
        time = time + dt
    end
    for i, light in ipairs(lights) do
        local t = time*0.2 + ((math.pi*2)/#lights) * i
        light.pos = {
            math.sin(t)*3,
            2 + math.sin(t),
            -1 + math.cos(t)*3,
        }
    end

    for i, object in ipairs(tablex.values(scene)) do
        if object.update then object.update(object, time) end
    end

    if lovr.headset.wasPressed("right", "a") then 
        paused = not paused
    end
end

function lovr.draw()
    lovr.graphics.setDepthTest('lequal', true) 
    -- add lights to the object list if needed

    local proj = lovr.math.mat4():perspective(0.1, 10, 60 * math.pi/180, 1)
    -- lovr.graphics.setProjection(1, proj)
    -- lovr.graphics.setProjection(2, proj)
    
    for i, light in ipairs(lights) do
        local id = 'light ' .. i
        local object = scene[id]
        if object then
            object.position:set(table.unpack(light.pos))
            object.light.color = {
                light.color[1] * lightMult,
                light.color[2] * lightMult,
                light.color[3] * lightMult,
            }
        else
            scene[id] = {
                id = 'light ' .. i,
                type = 'light',
                position = newVec3(table.unpack(light.pos)),
                AABB = {
                    min = newVec3(-0.1, -0.1, -0.1), 
                    max = newVec3(0.1, 0.1, 0.1), 
                },
                draw = function (object, context)
                    local x, y, z = object.position:unpack()
                    -- lovr.graphics.setColor(table.unpack(object.light.color))
                    -- lovr.graphics.sphere(x, y, z, 0.1)
                end,
                light = {
                    color = light.color,
                    position = light.position
                },
            }
        end
    end
    local stats = renderer:render(tablex.values(scene), {drawAABB = drawAABBs})

    
    -- Screen-space coordinate system
    local pixwidth = lovr.graphics.getWidth()/2   -- Window pixel width and height
    local pixheight = lovr.graphics.getHeight()
    local aspect = pixwidth/pixheight           -- Window aspect ratio
    local height = pixheight                            -- Window width and height in screen coordinates
    local width = pixwidth                      -- ( We will pick the coordinate system [[-1,1],[-aspect,aspect]] )
    local screenProjection = lovr.math.newMat4():orthographic(-aspect, aspect, -1, 1, -64, 64)

    lovr.graphics.setShader(nil)
	lovr.graphics.setDepthTest(nil)
    lovr.graphics.origin()
    lovr.graphics.setViewPose(1, mat4())
    lovr.graphics.setViewPose(2, mat4():scale(0,0,0))
    lovr.graphics.setProjection(1, screenProjection)
    lovr.graphics.setFont(font)
    local fontscale = 0.5/lovr.graphics.getHeight()
    lovr.graphics.translate(-0.8, -0.9, 0)
    lovr.graphics.setColor(1,1,1,1)
    
    local info = ""
    for i, name in ipairs(renderer.drawLayer.names) do
        local show, only = renderer:layerVisibility(i)
        info = info .. keys[i] .. ": " .. name .. ": " .. (show and "on" or "off") .. (only and " only" or "") .. "\n"
    end
    info = info .. "\n"
    info = info .. "p: pause animations\n"
    info = info .. "m: switch environment\n"
    info = info .. "b: switch scene\n"
    info = info .. "h: toggle indoor\n"

    info = info .. "\n"
    info = info .. "Views: " .. stats.views .. "\n"
    info = info .. "Objects: " .. stats.drawnObjects .. "\n"
    info = info .. "Culled: " .. stats.culledObjects .. "\n"
    info = info .. "Lights: " .. stats.lights .. "\n"
    info = info .. "Cubemaps: " .. stats.generatedCubemaps .. "("..stats.maxReflectionDepth..")\n"
    info = info .. stringx.join(", ", stats.cubemapTargets) .. "\n"
    if stats.debugText then 
        info = info .. stringx.join("\n", stats.debugText) .. "\n"
    end
    lovr.graphics.print(info, 0, 0, 0, fontscale, 0, 0, 0, 0, 0, 'left', 'top')
    
    
    
    local ls = lovr.graphics.getStats()
    local info2 = ""
    info2 = info2 .. "drawcalls: " .. ls.drawcalls .. "\n"
    info2 = info2 .. "renderpasses: " .. ls.renderpasses .. "\n"
    info2 = info2 .. "shaderswitches: " .. ls.shaderswitches .. "\n"
    info2 = info2 .. "buffers: " .. ls.buffers .. "\n"
    info2 = info2 .. "textures: " .. ls.textures .. "\n"
    info2 = info2 .. "buffermemory: " .. ls.buffermemory .. "\n"
    info2 = info2 .. "texturememory: " .. ls.texturememory .. "\n"
    lovr.graphics.print(info2, 1.6, 1.85, 0, fontscale, 0, 0, 0, 0, 0, 'right', 'bottom')
end


keys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "t", "y", "u", "i", "o", "p"}

altDown = false
function lovr.keypressed(key, scancode, repeated)
    if repeated then return end
    if key == 'm' then 
        selectedEnvironmentMap = selectedEnvironmentMap + 1
        if selectedEnvironmentMap > #environmentMaps then selectedEnvironmentMap = 1 end
        print(selectedEnvironmentMap)
        renderer.defaultEnvironmentMap = lovr.graphics.newTexture(environmentMaps[selectedEnvironmentMap], {mipmaps = true})        
    end
    if key == 'p' then 
        paused = not paused
    end

    if key == 'lalt' or key == 'ralt' then
        altDown = true
    end

    print(key)
    for i = 1, #keys do
        if key == keys[i] then
            local name = renderer.drawLayer[i]
            local show, only = renderer:layerVisibility(i)
            print(only)
            if altDown and only then only = nil
            elseif altDown then only = i
            else show = not show end
            renderer:layerVisibility(i, show, only)
        end
    end
    if key == 'h' then
        house.visible = not house.visible
    end

    if key == 'z' then 
        drawAABBs = not drawAABBs
    end

    if key == 'l' then 
        lightMult = lightMult + 1
        if lightMult > 5 then lightMult = 1 end
    end

    if key == 'b' then 
        local names = tablex.keys(scenes)
        local i = tablex.find(names, selectedScene) + 1
        if i > #names then i = 1 end
        selectedScene = names[i]
        scene = scenes[selectedScene]
    end
end

function lovr.keyreleased(key)

    if key == 'lalt' or key == 'ralt' then
        altDown = false
    end
    
end
