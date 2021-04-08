

local class = require 'pl.class'
local lovr = lovr

Shader = class.Shader()

function Shader:_init()
    self.lights = {
        {
            type = 'point', -- point, directional, spot
            position = {0, 0, 0}, -- for point, spot
            direction = {0, 0, -1}, -- for directional, spot
            color = {0.8, 1, 1},
        }
    }
    self.lightsBlock = lovr.graphics.newShaderBlock('uniform', {
        lightCount = 'int',
        lightPositions = { 'vec4', 32 },
        lightColors = { 'vec4', 32 },
    }, { usage = 'stream'})
end

function Shader:get(options)
    options = options or {}
    options.useTransparency = options.useTransparency or true
    options.useTransparency = options.useTransparency or false
    options.useNormalMap = options.useNormalMap or false
    options.useTangentMap = options.useTangentMap or false
    options.useGeneratedNormals = options.useTangentMap or false
    options.useMetalnessMap = options.useMetalnessMap or false
    options.useRoughnessMap = options.useRoughnessMap or false
    options.useSpecularMap = options.useSpecularMap or false
    options.useLights = options.useLights or false
    options.maxLightCount = options.maxLightCount or 128
    options.debugMode = options.debugMode or nil -- transparency, normalmap, metalnessmap, roughnessmap, specularmap, reflections, refractions, lights
end

function Shader:generate(options)
    if self.shader then return self.shader end

    options = options or {}
    local debug = options.debugMode
    local returnvalue = 'result'
    if debug == 'normalmap' then 
        returnvalue = 'vec4(N)'
    end

    local vert = ""
    local frag = ""

    if true or options.useLights then 
        frag = frag .. self.lightsBlock:getShaderCode('Lights')
    end

    if true or options.useGeneratedNormals then 
        frag = frag .. io.open("shader/normals.glsl"):read('*a')
    end

    vert = vert .. io.open("shader/vert.glsl"):read("*a")
    frag = frag .. io.open("shader/frag.glsl"):read("*a")

    local shader = lovr.graphics.newShader(vert, frag, {})

    shader:sendBlock('Lights', lightsBlock)
    self.shader = shader
    return shader
end