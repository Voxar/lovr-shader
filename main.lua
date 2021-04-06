local version = _VERSION:match("%d+%.%d+")
package.path = 'lib/share/lua/' .. version .. '/?.lua;lib/share/lua/' .. version .. '/?/init.lua;' .. package.path
package.cpath = 'lib/lib/lua/' .. version .. '/?.so;' .. package.cpath
local pp = require('pl.pretty').dump

function lovr.load()
    model = lovr.graphics.newModel("bkd_main room_shell.glb")
    torso = lovr.graphics.newModel("torso.glb")
    helmet = lovr.graphics.newModel("helmet.glb")
    lightsBlock = lovr.graphics.newShaderBlock('uniform', {
        lightCount = 'int',
        lightPositions = { 'vec4', 32 },
        lightColors = { 'vec4', 32 },
    }, { usage = 'stream'})
    
    shader = require 'shader'
  shader:send('specularStrength', 0.5)
  shader:send('metallic', 500.0)
  shader:send('viewPos', { 0.0, 0.0, 0.0} )
  shader:send('ambience', { 0.2, 0.2, 0.2, 1.0 })
  
  shader:sendBlock('Lights', lightsBlock)
  
  depthShader = require 'fill_depth_shader'

  lovr.graphics.setBackgroundColor(.18, .18, .20)
  lovr.graphics.setCullingEnabled(true)
  
  local width, height = lovr.headset.getDisplayDimensions()
  canvas = lovr.graphics.newCanvas(width, height, {
      stereo = false,
      depth = { format = 'd16', readable = true },
  })
end

local lights = {
  { color = {1, 0, 0} },
  { color = {0, 1, 0} },
  { color = {0, 0, 1} },
  { color = {1, 1, 1} },
}

function all(k, t)
  local r = {}
  for _, tt in ipairs(t) do
    table.insert(r, tt[k])
  end
  return r
end

local time = 0
function lovr.update(dt)
  time = time + dt
  for i, light in ipairs(lights) do
    local t = time + ((math.pi*2)/#lights) * i
    light.pos = { math.sin(t)*2, 1.7 + math.sin(t * 0.3), math.cos(t) - 3 }
  end
  lightsBlock:send('lightPositions', all('pos', lights) )
  lightsBlock:send('lightColors', all('color', lights) )
  lightsBlock:send('lightCount', #lights)
end
saved = false
function lovr.draw()

        lovr.graphics.clear()
        lovr.graphics.setShader(shader)
        lovr.graphics.sphere(-1.2, 1.7, -3, 0.5, -time * 0.5, 0, 1, 0)
        -- lovr.graphics.sphere(0, 1.7, -3, 0.5)
        torso:draw(0, 1.2, -3, 3, time*0.5, 0, 1, 0)
        helmet:draw(0, 2.6, -3, 0.2, time*0.0, 0, 1, 0)
        lovr.graphics.box("fill", 1.2, 1.7, -3, 0.8, 0.5, 1, -time, 1, 1, 0)
    
        for _, light in ipairs(lights) do
            lovr.graphics.setColor(table.unpack(light.color))
            lovr.graphics.sphere(light.pos[1], light.pos[2], light.pos[3], 0.1)
        end
        model:draw()
end