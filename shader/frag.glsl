        uniform vec4 ambience;
  
        in vec3 Normal;
        in vec3 FragmentPos;
        in vec3 vCameraPositionWorld;
        in vec3 vTangent;
        flat in mat3 lovrViewTransposed;
        flat in mat3 lovrNormalMatrixInversed;
        in vec3 vViewDir;
        in vec3 NormalView;
        flat in mat3 vTransform;
        
        uniform vec3 viewPos;
        uniform float specularStrength;
        uniform int metallic;
        uniform samplerCube cubemap;
        uniform float reflectionStrength;
        uniform float time;
        
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
            vec3 lighting = ambience.rgb;
            vec4 Nmap = texture(lovrNormalTexture, uv);
            vec3 N = normalize(Normal);
            if (Nmap != vec4(1) ) {
                N = perturb_normal(N, vCameraPositionWorld - FragmentPos, uv);
//                N = normalize(Normal + (Nmap.rgb * 2. - 1.));
            }
            
            
            //Metallness
            float metalness = texture(lovrMetalnessTexture, lovrTexCoord).b * lovrMetalness;
            float roughness = max(texture(lovrRoughnessTexture, lovrTexCoord).g * lovrRoughness, .05);


            for(int i_light = 0; i_light < lightCount; i_light++) {
                vec3 lightPos = lightPositions[i_light].xyz;
                vec3 lightColor = lightColors[i_light].rgb;
                
                //diffuse
                vec3 norm = normalize(N);
                vec3 lightDir = normalize(lightPos - FragmentPos);
                float diff = max(dot(norm, lightDir), 0.);
                vec3 diffuse = lightColor * diff;
                
                // specular
                vec3 reflectDir = reflect(-lightDir, norm);
                float spec = pow(max(dot(viewDir, reflectDir), 0.0), metallic) * metalness;
                vec3 specular = specularStrength * spec * lightColor;
                
                lighting += diffuse + specular;
            }

            //object color
            vec4 baseColor = graphicsColor * texture(lovrDiffuseTexture, uv);
            vec4 emissive = texture(lovrEmissiveTexture, uv) * lovrEmissiveColor;
            
            // cubemap reflection and refractions
    		vec3 n_ws=normalize(N);
            vec3 n_vs=normalize(NormalView);
            n_vs=normalize(vTransform * (lovrNormalMatrixInversed * N));
    		vec3 i_vs=normalize(vViewDir);
            float ndi=0.04+0.96*(1.0-sqrt(max(0.0,dot(n_vs,i_vs))));
            vec3 ref = reflect(normalize(-viewDir), N).xyz;
    		vec3 refl=texture(cubemap, ref, -0.5).rgb * ndi * metalness * graphicsColor.rgb;
            vec3 r = refract(-i_vs, n_vs, 0.66);
    		vec3 refr=texture(cubemap, lovrViewTransposed * r).rgb * (1. - baseColor.a);
            vec4 reflections = vec4(refl + refr, 1.) * reflectionStrength * metalness;
            
            //float fresnel = clamp(0., 1., 1 - dot(N, viewDir));
//            return texture(lovrRoughnessTexture, uv).rrra;
//            return texture(lovrMetalnessTexture, uv);
//            return texture(lovrDiffuseTexture, uv);
//            return texture(lovrNormalTexture, uv);
//            return texture(lovrOcclusionTexture, uv);
//            return texture(lovrEmissiveTexture, uv);
         
                if (lovrViewID == 1)             
                    //return vec4(vec3(roughness), 1.0);
                    return vec4(vec3(time), 1.);
                //else return vec4(N, 1);
            return (baseColor + emissive + reflections) * vec4(lighting, 1.);
        }