        out vec3 FragmentPos;
        out vec3 Normal;
        out vec3 NormalView;
        out vec3 vCameraPositionWorld;
        out vec3 vViewDir;
        out vec3 vTangent;
        flat out mat3 lovrViewTransposed;
        flat out mat3 lovrNormalMatrixInversed;
        flat out mat3 vTransform;
        
        vec4 position(mat4 projection, mat4 transform, vec4 vertex) {
            lovrNormalMatrixInversed = inverse(lovrNormalMatrix);
            Normal = normalize(lovrNormalMatrix * lovrNormal);
            NormalView = mat3(lovrTransform)*lovrNormal;
            vTransform = mat3(lovrTransform);
            FragmentPos = vec3(lovrModel * vertex);
            vCameraPositionWorld = -lovrView[3].xyz * mat3(lovrView);
            vViewDir = -(transform * vertex).xyz;
            vTangent = lovrTangent.xyz;
            lovrViewTransposed = transpose(mat3(lovrView));
            return projection * transform * vertex;
        }