        out vec3 vFragmentPos;
        out vec3 vNormal;
        out vec3 vNormalView;
        out vec3 vCameraPositionWorld;
        out vec3 vViewDir;
        out vec3 vTangent;
        
        

        // move to frag uniforms
        flat out mat3 vLovrTransform;
        flat out mat3 vLovrViewTransposed;
        flat out mat3 vLovrNormalMatrixInversed;
        
        vec4 position(mat4 projection, mat4 transform, vec4 vertex) {
            vNormal = normalize(lovrNormalMatrix * lovrNormal);
            vNormalView = mat3(lovrTransform) * lovrNormal;
            vFragmentPos = vec3(lovrModel * vertex);
            vCameraPositionWorld = -lovrView[3].xyz * mat3(lovrView);
            vViewDir = -(transform * vertex).xyz;
            vTangent = lovrTangent.xyz;

            vLovrTransform = mat3(lovrTransform);
            vLovrViewTransposed = transpose(mat3(lovrView)); //todo move to uniform
            vLovrNormalMatrixInversed = inverse(lovrNormalMatrix); // todo: move to uniform
            return projection * transform * vertex;
        }