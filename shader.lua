return lovr.graphics.newShader(
    lightsBlock:getShaderCode('Lights') .. 
    io.open("shader/vert.glsl"):read("*a"),
    lightsBlock:getShaderCode('Lights') .. 
    io.open("shader/frag.glsl"):read("*a"), 
    {})