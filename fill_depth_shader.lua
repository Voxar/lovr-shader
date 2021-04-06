return lovr.graphics.newShader(
    [[
        vec4 position(mat4 projection, mat4 transform, vec4 vertex) {
          return lovrVertex;
        }
    ]],
    [[
        vec4 color(vec4 graphicsColor, sampler2D image, vec2 uv) {
            vec4 c = texture(image, uv);
            return vec4(c.r, 0, 0, 1);
        }
    ]])