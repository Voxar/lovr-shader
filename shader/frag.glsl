
#define PI 3.141592653589
#define PI2 PI / 2.0

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

uniform float alloMetalness;
uniform float alloRoughness;

uniform int alloEnvironmentMapType; // 0: none, 1: cubemap, 2: spherical
uniform sampler2D alloEnvironmentMapSpherical;
uniform samplerCube alloEnvironmentMapCube;


uniform float draw_albedo;
uniform float draw_metalness;
uniform float draw_roughness;
uniform float draw_diffuseEnv;
uniform float draw_specularEnv;
uniform float draw_diffuseLight;
uniform float draw_specularLight;
uniform float draw_occlusion;
uniform float draw_lights;
uniform float draw_ambient;
uniform float draw_emissive;

vec3 environmentMap(vec3 direction);
vec3 environmentMap(vec3 direction, float bias);

vec3 environmentMap(vec3 direction) {
    return environmentMap(direction, 0);
}

vec3 environmentMap(vec3 direction, float roughness) {
    if (alloEnvironmentMapType == 1) {
        // float mipmapCount = log2(float(textureSize(alloEnvironmentMapCube, 0).x));
        float mipmapCount = floor(log2(textureSize(alloEnvironmentMapCube, 0).x)) - 1;
        float k =  min(sin(PI2*roughness) * 2, 1.);
        return textureLod(alloEnvironmentMapCube, direction, k * mipmapCount).rgb;
    } 
    
    if (alloEnvironmentMapType == 2) {
        float theta = acos(-direction.y / length(direction));
        float phi = atan(direction.x, -direction.z);
        vec2 cubeUv = vec2(.5 + phi / (2. * PI), theta / PI);
        // float mipmapCount = log2(float(textureSize(alloEnvironmentMapSpherical, 0).x));
        float mipmapCount = floor(log2(textureSize(alloEnvironmentMapSpherical, 0).x)) - 2;
        // return textureLod(alloEnvironmentMapSpherical, cubeUv, ).rgb;
        float k =  min(sin(PI2*roughness) * 2, 1.);
        return textureLod(alloEnvironmentMapSpherical, cubeUv, k * mipmapCount).rgb;
    }
    return vec3(0.0);
}

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

vec3 fresnelSchlickRoughness(float HdotV, vec3 baseReflectivity, float roughness) {
    // More rough = less fresnel
    return baseReflectivity + (max(vec3(1.0 - roughness), baseReflectivity) - baseReflectivity) * pow(1.0 - HdotV, 5.0);
}

// https://www.unrealengine.com/en-US/blog/physically-based-shading-on-mobile
vec2 prefilteredBRDF(float NoV, float roughness) {
  vec4 c0 = vec4(-1., -.0275, -.572, .022);
  vec4 c1 = vec4(1., .0425, 1.04, -.04);
  vec4 r = roughness * c0 + c1;
  float a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
  return vec2(-1.04, 1.04) * a004 + r.zw;
}

vec3 tonemap_ACES(vec3 x) {
  float a = 2.51;
  float b = 0.03;
  float c = 2.43;
  float d = 0.59;
  float e = 0.14;
  return (x * (a * x + b)) / (x * (c * x + d) + e);
}

// vec3 reflections(vec3 N, vec3 viewDir, float metalness, vec4 graphicsColor, float opacity) {
//     // cubemap reflection and refractions
//     vec3 refl = vec3(0.0);
//     vec3 refr = vec3(0.0);

//     vec3 n_ws=normalize(N);
//     vec3 n_vs=normalize(vNormalView);
//     n_vs=normalize(vLovrTransform * (vLovrNormalMatrixInversed * N));
//     vec3 i_vs=normalize(vViewDir);
//     float ndi=0.04+0.96*(1.0-sqrt(max(0.0,dot(n_vs,i_vs))));
//     vec3 ref = reflect(normalize(-viewDir), N).xyz;
//     // refl=texture(cubemap, ref, -0.5).rgb * ndi * metalness * graphicsColor.rgb;
//     refl=environmentMap(ref, -0.5) * ndi * metalness * graphicsColor.rgb;
//     vec3 r = refract(-i_vs, n_vs, 0.66);
//     refr=texture(cubemap, vLovrViewTransposed * r).rgb * (1. - opacity);
//     return vec3(refl + refr) * reflectionStrength;
// }

// V: view position
// L: direcion to light
// N: Normal
vec3 cook(vec3 F0, vec3 V, vec3 L, vec3 N, vec3 radiance, float roughness, float metalness) {
    vec3 H = normalize(V + L);

    // Cook-Torrence BRDF
    float NdotV = max(dot(N, V), 0.001);
    float NdotL = max(dot(N, L), 0.001);
    float HdotV = max(dot(H, V), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    
    float D = distributionGGX(NdotH, roughness); // statistical amount of light rays reflected by micro facets
    float G = geometrySmith(NdotV, NdotL, roughness); // statistical amount of light rays not shadowed by micro facets
    vec3 F = fresnelSchlick(HdotV, F0); // fresnel - reflections are more clear at glancing anles - ie edges of a sphere
    // Diffuse is all light not reflected as specular because the equal amount of enery coming in has to come out somewhere
    // But metallic materials absorb anything not bounced of as specular so subtract that energy
    vec3 diff = (vec3(1.0) - F) * (1.0 - metalness);
    // diff *= occlusion;

    vec3 spec = D * G * F;
    spec /= 4.0 * NdotV * NdotL;
    
    return spec;
}

vec4 color(vec4 graphicsColor, sampler2D image, vec2 uv) {
    vec3 viewDir = normalize(vCameraPositionWorld - vFragmentPos);
    vec3 V = viewDir;
    vec4 Nmap = texture(lovrNormalTexture, uv);
    vec3 N = normalize(vNormal);
    if (Nmap != vec4(1) ) {
        N = perturb_normal(N, vCameraPositionWorld - vFragmentPos, uv);
    }

    // mapped values
    vec3 albedo = texture(lovrDiffuseTexture, lovrTexCoord).rgb * graphicsColor.rgb * draw_albedo;
    vec4 emissive = texture(lovrEmissiveTexture, uv) * lovrEmissiveColor * draw_emissive;
    float occlusion = texture(lovrOcclusionTexture, lovrTexCoord).r * draw_occlusion;
    float roughness = texture(lovrRoughnessTexture, lovrTexCoord).g * lovrRoughness * alloRoughness * draw_roughness;
    float metalness = texture(lovrMetalnessTexture, lovrTexCoord).b * lovrMetalness * alloMetalness * draw_metalness;
    // Reflectance at normal incidence. F0.
    // dia-electric use 0.04 and if it's metal then use the albedo color
    vec3 baseReflectivity = mix(vec3(0.04), albedo, metalness);

    float NdotV = max(dot(N, V), 0.001);

    vec3 luminence = vec3(0.0); // Lo
    vec3 diffuse = vec3(0.), specular = vec3(0.);
    for(int i_light = 0; i_light < lightCount; i_light++) {
        vec3 lightPos = i_light == lightCount ? vCameraPositionWorld : lightPositions[i_light].xyz;
        vec3 lightColor = i_light == lightCount ? vec3(1,0,1) : lightColors[i_light].rgb;
        // lightColor = vec3(1.0);
        lightColor *= 1.;

        vec3 L = normalize(lightPos - vFragmentPos);
        vec3 H = normalize(V + L);
        float distance = length(lightPos - vFragmentPos);
        float attenuation = 1.0 / (distance * distance);
        vec3 radiance = lightColor * attenuation;

        // Cook-Torrence BRDF
        float NdotL = max(dot(N, L), 0.001);
        float HdotV = max(dot(H, V), 0.0);
        float NdotH = max(dot(N, H), 0.0);
        
        float D = distributionGGX(NdotH, roughness); // statistical amount of light rays reflected by micro facets
        float G = geometrySmith(NdotV, NdotL, roughness); // statistical amount of light rays not shadowed by micro facets
        vec3 F = fresnelSchlick(HdotV, baseReflectivity); // fresnel - reflections are more clear at glancing anles - ie edges of a sphere
        
        // Diffuse is all light not reflected as specular because the equal amount of enery coming in has to come out somewhere
        // But metallic materials absorb anything not bounced of as specular so subtract that energy
        vec3 diff = (vec3(1.0) - F) * (1.0 - metalness);
        // diff *= occlusion;

        vec3 spec = D * G * F;
        spec /= 4.0 * NdotV * NdotL;
        
        spec *= draw_specularLight;
        diff *= draw_diffuseLight;

        // diffuse * albedo because diffuse is the wavelengths (colors) not absorbed while refracting(?)
        // divided by PI ??
        // NdotL ??
        luminence += (diff * albedo / PI + spec) * radiance * NdotL;
        
        specular += spec;
        diffuse += diff;
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
    diffuse /= lightCount;

    luminence *= draw_lights;

    // environment diffuse is the color shining on us and taking up by the material
    vec3 F = fresnelSchlickRoughness(NdotV, baseReflectivity, roughness);
    vec3 kD = (1.0 - F) * (1.0 - metalness);
    vec3 diffuseEnvironmentMap = environmentMap(N, 0.75);
    vec3 environmentDiffuse = diffuseEnvironmentMap * kD * albedo;


    // environment specular is the color of environment reflecting off the surface of the material and into our eyes
    vec3 R = reflect(-V, N);
    vec2 lookup = prefilteredBRDF(NdotV, roughness); // microfacet statistical amount of light rays hitting us
    vec3 specularEnvironmentMap = environmentMap(R, roughness);
    vec3 environmentSpecular = specularEnvironmentMap * (F * lookup.r + lookup.g);


    // if (lovrViewID == 1)
    //environmentSpecular  /=  4. ;

    environmentDiffuse *= draw_diffuseEnv;
    environmentSpecular *= draw_specularEnv;

    vec3 ambient = (environmentDiffuse + environmentSpecular) * (occlusion + 1-draw_occlusion);
    // ambient *= 0.001;

    ambient *= draw_ambient;

    vec3 result = ambient + luminence + emissive.rgb;

    // HDR tonemapping
    if (lovrViewID == 1){
    result = result / (result + vec3(1.0));
    result.rgb = tonemap_ACES(result.rgb);
    } else {

    result.rgb = tonemap_ACES(result.rgb);

    }
    // gamma correction
    float gamma = 1.2;
    // result = pow(result, vec3(1.0/gamma));


    if (lovrViewID == 1) {
        // return vec4(N, 1.);
        // return vec4(vec3(metalness * roughness), 1.);
        // return vec4(vec3(kk), 1.);
        // return vec4(vec3(occlusion), 1.);
        // return vec4(vec3(metalness), 1.);
        // return vec4(vec3(roughness), 1.);
        // return vec4(vec3(diffuse), 1.);
        // return vec4(vec3(luminence), 1.);
        // return vec4(vec3(environmentMap(R, roughness)), 1.);
        // return vec4(vec3(albedo), 1.);
        // return vec4(vec3(specularEnvironmentMap), 1.);
        // return vec4(vec3(diffuseEnvironmentMap), 1.);
        // return vec4(vec3(fresnelSchlick(NdotV, baseReflectivity)), 1.);
        // return vec4(reflections(N, viewDir, metalness, graphicsColor, tex.a), 1.);s
        // return vec4(ambient, 1.);
        // return vec4(N, 1.);
    }

    return vec4(result, 1.0);

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