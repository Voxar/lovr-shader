
#define PI 3.141592653589

uniform vec4 ambience;
in vec3 vNormal;
in vec3 vFragmentPos;
in vec3 vCameraPositionWorld;
in vec3 vTangent;
in vec3 vViewDir;
in vec3 vNormalView;

// move mat3's to uniforms
flat in mat3 vLovrTransform; 
flat in mat3 vLovrViewTransposed; 
flat in mat3 vLovrNormalMatrixInversed;

uniform float specularStrength;
uniform int metallic;
uniform samplerCube cubemap;
uniform float reflectionStrength;
uniform float time;
//50

float distributionGGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    denom = PI * denom * denom;
    return a2 / max(denom, 0.0000001);
}

float geometrySmith(float NdotV, float NdotL, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    float ggx1 = NdotV / (NdotV * (1.0 - k) + k); // Schlick GGX
    float ggx2 = NdotL / (NdotL * (1.0 - k) + k);
    return ggx1 * ggx2;
}

// fresnel: light bouncing at a large (approaching 180) reflect more easily
vec3 fresnelSchlick(float HdotV, vec3 baseReflectivity) {
    // baseRef. 0...1
    // returns baseRef...1
    return baseReflectivity + (1.0 - baseReflectivity) * pow(1.0 - HdotV, 5.0);
}

vec4 color(vec4 graphicsColor, sampler2D image, vec2 uv) {
    vec3 viewDir = normalize(vCameraPositionWorld - vFragmentPos);
    vec3 V = viewDir;
    vec3 lighting = ambience.rgb;
    vec4 Nmap = texture(lovrNormalTexture, uv);
    vec3 N = normalize(vNormal);
    if (Nmap != vec4(1) ) {
        N = perturb_normal(N, vCameraPositionWorld - vFragmentPos, uv);
//                N = normalize(vNormal + (Nmap.rgb * 2. - 1.));
    }
    
    // mapped values
    vec4 tex = graphicsColor * texture(lovrDiffuseTexture, uv);
    vec4 emissive = texture(lovrEmissiveTexture, uv) * lovrEmissiveColor;
//91
    vec3 albedo = texture(lovrDiffuseTexture, lovrTexCoord).rgb * graphicsColor.rgb;
    float metalness = texture(lovrMetalnessTexture, lovrTexCoord).b * lovrMetalness;
    float roughness = max(texture(lovrRoughnessTexture, lovrTexCoord).g * lovrRoughness, .05);
    float occlusion = texture(lovrOcclusionTexture, lovrTexCoord).r;
    // Reflectance at normal incidence. F0.
    // dia-electric use 0.04 and if it's metal then use the albedo color
    vec3 baseReflectivity = mix(vec3(0.04), albedo, metalness);

    vec3 luminence = vec3(0.0); // luminence
    vec3 diffuse = vec3(0.), specular = vec3(0.);
    for(int i_light = 0; i_light < lightCount; i_light++) {
        vec3 lightPos = lightPositions[i_light].xyz;
        vec3 lightColor = lightColors[i_light].rgb;
        lightColor = vec3(1.0);

        vec3 L = normalize(lightPos - vFragmentPos);
        vec3 H = normalize(V + L);
        float distance = length(lightPos - vFragmentPos);
        float attenuation = 1.0 / (distance * distance);
        vec3 radiance = lightColor * attenuation;

        // Cook-Torrence BRDF
        float NdotV = max(dot(N, V), 0.0000001);
        float NdotL = max(dot(N, L), 0.0000001);
        float HdotV = max(dot(H, V), 0.0);
        float NdotH = max(dot(N, H), 0.0);
        
        float D = distributionGGX(NdotH, roughness); // statistical amount of light rays reflected by micro facets
        float G = geometrySmith(NdotV, NdotL, roughness); // statistical amount of light rays not shadowed by micro facets
        vec3 F = fresnelSchlick(HdotV, baseReflectivity); // fresnel - less light rays reflect at direct angles

        vec3 spec = D * G * F;
        spec /= NdotV * NdotL;
        specular += spec;
        // Diffuse is all light not reflected as specular because the equal amount of enery coming in has to come out somewhere
        vec3 diff = vec3(1.0) - F;

        // But metallic materials absorb anything not bounced of as specular so subtract that energy
        diff *= 1.0 - metalness;
        diffuse += diff;

        // diffuse * albedo because diffuse is the wavelengths (colors) not absorbed while refracting(?)
        // divided by PI ??
        // NdotL ??
        luminence += (diff * albedo / PI + spec) * radiance * NdotL;
        

        // lightColor = vec3(1.);
        
        // //diffuse
        // vec3 lightDir = normalize(lightPos - vFragmentPos);
        // float diff = max(dot(norm, lightDir), 0.);
        // diffuse += lightColor * diff * ;
        
        // // specular
        // vec3 reflectDir = reflect(-lightDir, norm);
        // float spec = pow(float(max(dot(viewDir, reflectDir), 0.0)), float(metallic)) * metalness;
        // specular += specularStrength * spec * lightColor;
        
    }
    vec3 ambient = ambience.rgb * albedo;

    vec3 result = ambient + luminence;

    // HDR tonemapping
    result = result / (result + vec3(1.0));
    // gamma correction
    result = pow(result, vec3(1.0/2.2));

    if (lovrViewID == 1) {
        return vec4(vec3(albedo), 1.);
    }

    return vec4(luminence, 1.0);

    // //object color
    // vec4 baseColor = graphicsColor * texture(lovrDiffuseTexture, uv);
    // vec4 emissive = texture(lovrEmissiveTexture, uv) * lovrEmissiveColor;
    
    // // cubemap reflection and refractions
    // vec4 reflections = vec4(0.);
    // vec3 refl = vec3(0.0);
    // vec3 refr = vec3(0.0);
    // if (reflectionStrength > 0) {
    //     vec3 n_ws=normalize(N);
    //     vec3 n_vs=normalize(vNormalView);
    //     n_vs=normalize(vLovrTransform * (vLovrNormalMatrixInversed * N));
    //     vec3 i_vs=normalize(vViewDir);
    //     float ndi=0.04+0.96*(1.0-sqrt(max(0.0,dot(n_vs,i_vs))));
    //     vec3 ref = reflect(normalize(-viewDir), N).xyz;
    //     refl=texture(cubemap, ref, -0.5).rgb * ndi * metalness * graphicsColor.rgb;
    //     vec3 r = refract(-i_vs, n_vs, 0.66);
    //     refr=texture(cubemap, vLovrViewTransposed * r).rgb * (1. - baseColor.a);
    //     reflections = vec4(refl + refr, 1.) * reflectionStrength;
    // }
    
    // //float fresnel = clamp(0., 1., 1 - dot(N, viewDir));
    // // return texture(lovrRoughnessTexture, uv).rrra;
    // // return texture(lovrMetalnessTexture, uv);
    // // return texture(lovrDiffuseTexture, uv);
    // // return texture(lovrNormalTexture, uv);
    // // return texture(lovrOcclusionTexture, uv);
    // // return texture(lovrEmissiveTexture, uv);
    
    // if (lovrViewID == 1) {         
    //     // return vec4(vec3(reflectionStrength), 1.0);
    //     return vec4(refl, 1.0);
    //     // return reflections;
    // }
    // //     return vec4(N, 1.);
    // //else return vec4(N, 1);
    // return (baseColor + emissive + reflections) * vec4(lighting, 1.);
}