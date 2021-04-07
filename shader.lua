return lovr.graphics.newShader(
    lightsBlock:getShaderCode('Lights') ..
    [[
        out vec3 FragmentPos;
        out vec3 Normal;
        out vec3 NormalView;
        out vec3 vCameraPositionWorld;
        out vec3 vViewDir;
        out vec3 vTangent;
        out mat3 lovrViewTransposed;
        
        vec4 position(mat4 projection, mat4 transform, vec4 vertex) {
            Normal = normalize(lovrNormalMatrix * lovrNormal);
            NormalView = mat3(lovrView)*lovrNormal;
            FragmentPos = vec3(lovrModel * vertex);
            vCameraPositionWorld = -lovrView[3].xyz * mat3(lovrView);
            vViewDir = -(transform * vertex).xyz;
            vTangent = lovrTangent.xyz;
            lovrViewTransposed = transpose(mat3(lovrView));
            return projection * transform * vertex;
        }
    ]],  
    lightsBlock:getShaderCode('Lights') .. 
    [[
        uniform vec4 ambience;
  
        in vec3 Normal;
        in vec3 FragmentPos;
        in vec3 vCameraPositionWorld;
        in vec3 vTangent;
        in mat3 lovrViewTransposed;
        in vec3 vViewDir;
        in vec3 NormalView;
        
        uniform vec3 viewPos;
        uniform float specularStrength;
        uniform int metallic;
        uniform samplerCube cubemap;
        
        mat3 cotangent_frame( vec3 N, vec3 p, vec2 uv )
        {
            // get edge vec­tors of the pix­el tri­an­gle
            vec3 dp1 = dFdx( p );
            vec3 dp2 = dFdy( p );
            vec2 duv1 = dFdx( uv );
            vec2 duv2 = dFdy( uv );

            // solve the lin­ear sys­tem
            vec3 dp2perp = cross( dp2, N );
            vec3 dp1perp = cross( N, dp1 );
            vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
            vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

            // con­struct a scale-invari­ant frame
            float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
            return mat3( T * invmax, B * invmax, N );
        }
        
        vec3 perturb_normal( vec3 N, vec3 V, vec2 texcoord ) {
            vec3 map = texture( lovrNormalTexture, texcoord ).xyz;
            map = map * 255./127. - 128./127.;
            //map.y = -map.y;
            mat3 TBN = cotangent_frame( N, V, texcoord );
            return normalize( TBN * map );
        }
        
        vec4 color(vec4 graphicsColor, sampler2D image, vec2 uv) {
            vec3 viewDir = normalize(vCameraPositionWorld - FragmentPos);
            vec4 lighting = ambience;
            vec4 Nmap = texture(lovrNormalTexture, uv);
            vec3 N = normalize(Normal);
            if (Nmap != vec4(1) ) {
                N = perturb_normal(N, vCameraPositionWorld - FragmentPos, uv);
//                N = normalize(Normal + (Nmap.rgb * 2. - 1.));
            }
            

            for(int i_light = 0; i_light < lightCount; i_light++) {
                vec3 lightPos = lightPositions[i_light].xyz;
                vec4 lightColor = lightColors[i_light];
                
                //diffuse
                vec3 norm = normalize(N);
                vec3 lightDir = normalize(lightPos - FragmentPos);
                float diff = max(dot(norm, lightDir), 0.);
                vec4 diffuse = lightColor * diff;
                
                // specular
                vec3 reflectDir = reflect(-lightDir, norm);
                float spec = pow(max(dot(viewDir, reflectDir), 0.0), metallic);
                vec4 specular = specularStrength * spec * lightColor;
                
                // emissive
                vec4 emissive = texture(lovrEmissiveTexture, uv);
                
                lighting += diffuse + specular + emissive * lovrEmissiveColor;
            } 
            //object color
            vec4 baseColor = graphicsColor * texture(image, uv);
            
            // cubemap reflection and refractions
    		vec3 n_ws=N;
    		vec3 n_vs=normalize(NormalView);
    		vec3 i_vs=normalize(N);
            float ndi=0.04+0.96*(1.0-sqrt(max(0.0,dot(n_vs,i_vs))));
    		vec3 refl=texture(cubemap, N, -0.5).rgb * ndi * 0.25;
    		vec3 refr=texture(cubemap, lovrViewTransposed * refract(-i_vs, n_vs, 0.66)).rgb * (1.0 - baseColor.a);
            vec4 reflections = vec4(refl, 1.) + vec4(refr, 1.);
            
            //float fresnel = clamp(0., 1., 1 - dot(N, viewDir));
//            return texture(lovrRoughnessTexture, uv).rrra;
//            return texture(lovrMetalnessTexture, uv);
//            return texture(lovrDiffuseTexture, uv);
//            return texture(lovrNormalTexture, uv);
//            return texture(lovrOcclusionTexture, uv);
//            return texture(lovrEmissiveTexture, uv);
         
                if (lovrViewID == 1)             return vec4(N, 1);
            return (baseColor + reflections) * lighting;
            return vec4(N, 1);
        }
  ]], {})