
local is_desktop = lovr.headset.getDriver() == "desktop"

-- Takes a cubemap and outputs it equirectangular
local shader = lovr.graphics.newShader([[
    #define PI    3.141592653589793
    #define TWOPI 6.283185307179587

    out vec2 vUV;

    vec4 position(mat4 projection, mat4 transform, vec4 vertex) {
        vUV = lovrTexCoord.xy * vec2(TWOPI, PI);
        return projection * transform * vertex;
    }
]],
[[
    uniform samplerCube alloEnvironmentMapCube;

    in vec2 vUV;

    vec4 color(vec4 graphicsColor, sampler2D image, vec2 uv) {
        float theta = vUV.y;
        float phi = vUV.x;
        vec3 unit = vec3(0., 0., 0.);

        unit.x = sin(phi) * sin(theta) * -1.;
        unit.y = cos(theta) * -1.;
        unit.z = cos(phi) * sin(theta) * -1.;
        //return vec4(unit, 1.);
        return texture(alloEnvironmentMapCube, unit);
    }
]])


local canvas = lovr.graphics.newCanvas(612, 306, { stereo = not is_desktop })

local function eqmake(cubemap, texture)
    texture = texture or lovr.graphics.newTexture(612, 306, { 
        format = "rg11b10f",
        stereo = not is_desktop
    })
    local view = { lovr.graphics.getViewPose(1) }
	-- local proj = { lovr.graphics.getProjection(1) }
    -- lovr.graphics.setProjection(1, mat4():perspective(0.1, 1000, math.pi/2, 1))
    lovr.graphics.setViewPose(1, 0, 0, 0)
    canvas:setTexture(texture)
    canvas:renderTo(function ()
        lovr.graphics.origin()
        lovr.graphics.clear(0,0,0,1)
        lovr.graphics.setShader(shader)
        shader:send("alloEnvironmentMapCube", cubemap)
        lovr.graphics.skybox(cubemap)
    end)
    -- lovr.graphics.setProjection(1,unpack(proj))
	lovr.graphics.setViewPose(1,unpack(view))

    return texture
end


return eqmake

-- x = 0.5 + atan(dx, -dy) / 2PI


-- y = acos(-dy / |d|) / PI