// http://media.steampowered.com/apps/dota2/workshop/Dota2ShaderMaskGuide.pdf
// https://developer.valvesoftware.com/wiki/Phong_materials
// TODO Fresnel / Diffuse Color Warp, metalness
@export hero.fragment

uniform mat4 viewInverse : VIEWINVERSE;

@import clay.standard.chunk.varying

uniform sampler2D diffuseMap;
uniform sampler2D normalMap;
uniform sampler2D maskMap1;
uniform sampler2D maskMap2;

uniform float u_SpecularExponent = 20;
uniform float u_SpecularScale = 1.0;
uniform vec3 u_SpecularColor = vec3(1.0, 1.0, 1.0);
uniform float u_RimLightScale = 1.0;
uniform vec3 u_RimLightColor = vec3(1.0, 1.0, 1.0);

@import clay.standard.chunk.light_header

// Import util functions and uniforms needed
@import clay.util.calculate_attenuation

@import clay.plugin.compute_shadow_map

void main() {

#ifdef RENDER_WEIGHT
    gl_FragColor = vec4(v_Weight.xyz, 1.0);
    return;
#endif
#ifdef RENDER_TEXCOORD
    gl_FragColor = vec4(v_Texcoord, 1.0, 1.0);
    return;
#endif

    vec4 finalColor = vec4(1.0);
    vec4 texColor = vec4(0.0);
    vec3 diffuseItem = vec3(0.0, 0.0, 0.0);
    vec3 specularItem = vec3(0.0, 0.0, 0.0);
    vec3 fresnelTerm = vec3(0.0, 0.0, 0.0);
    vec3 rimLightning = vec3(0.0, 0.0, 0.0);
    float selfIllumination = 0.0;

    vec3 eyePos = viewInverse[3].xyz;
    vec3 V = normalize(eyePos - v_WorldPosition);

    float specularIntensity = u_SpecularScale;
    vec3 specularColor = u_SpecularColor;
    float specularExponent = u_SpecularExponent;
    vec3 normal = v_Normal;

#ifdef NORMALMAP_ENABLED
    normal = texture2D(normalMap, v_Texcoord).xyz * 2.0 - 1.0;
    mat3 tbn = mat3(v_Tangent, v_Bitangent, v_Normal);
    normal = normalize(tbn * normal);
#endif
    // http://www.polycount.com/forum/showthread.php?t=110022
    fresnelTerm.r = 0.2 + 0.85 * pow(1.0 - max(0.0, dot(V, normal)), 4.0);
    fresnelTerm.r *= fresnelTerm.r;
    // TODO
    fresnelTerm.g = 1.0 - dot(V, normal);
    fresnelTerm.g *= fresnelTerm.g;

#ifdef DIFFUSEMAP_ENABLED
    texColor = texture2D(diffuseMap, v_Texcoord);
    if (texColor.a < 0.5) {
        gl_FragColor = vec4(0.0);
        return;
    }
    finalColor *= texColor;
#endif
#ifdef MASKMAP1_ENABLED
    vec4 mask1Tex = texture2D(maskMap1, v_Texcoord);
    selfIllumination += mask1Tex.a;
#endif
#ifdef MASKMAP2_ENABLED
    vec4 mask2Tex = texture2D(maskMap2, v_Texcoord);
    // Mask2 r -> specular intensity
    specularIntensity *= mask2Tex.r;
    #if !defined(IS_SPECULAR_MAP)
        // Mask2 g -> rim lightning
        rimLightning = vec3(fresnelTerm.g * u_RimLightScale * mask2Tex.g) * u_RimLightColor;
        // Masked by a 'sky light'
        rimLightning *= clamp(dot(normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
        // Mask2 b -> tint specular by color
        specularColor = mix(u_SpecularColor.rgb, texColor.rgb, mask2Tex.b);
        // Mask2 a -> specularExponent
        specularExponent *= mask2Tex.a;
    #endif
#endif

#ifdef AMBIENT_LIGHT_COUNT
    for(int i = 0; i < AMBIENT_LIGHT_COUNT; i++){
        diffuseItem += ambientLightColor[i];
    }
#endif

#ifdef RENDER_DIFFUSE
    gl_FragColor = vec4(texColor.rgb, 1.0);
    return;
#endif

#ifdef RENDER_SPECULAR_INTENSITY
    gl_FragColor = vec4(vec3(specularIntensity), 1.0);
    return;
#endif
#ifdef RENDER_SPECULAR_EXPONENT
    gl_FragColor = vec4(vec3(specularExponent), 1.0);
    return;
#endif
#ifdef RENDER_SPECULAR_COLOR
    gl_FragColor = vec4(specularColor, 1.0);
    return;
#endif
#ifdef RENDER_NORMAL
    gl_FragColor = vec4(normal, 1.0);
    return;
#endif
#ifdef RENDER_FRESNEL
    gl_FragColor = vec4(fresnelTerm, 1.0);
    return;
#endif
#ifdef RENDER_RIMLIGHT
    gl_FragColor = vec4(vec3(rimLightning), 1.0);
    return;
#endif
#ifdef RENDER_SELF_ILLUMINATION
    gl_FragColor = vec4(texColor.rgb * selfIllumination, 1.0);
    return;
#endif

#ifdef POINT_LIGHT_COUNT
    #if defined(POINT_LIGHT_SHADOWMAP_COUNT)
        float shadowContribs[POINT_LIGHT_COUNT];
        if(shadowEnabled){
            computeShadowOfPointLights(v_WorldPosition, shadowContribs);
        }
    #endif
    for(int i = 0; i < POINT_LIGHT_COUNT; i++){

        vec3 lightPosition = pointLightPosition[i];
        vec3 lightColor = pointLightColor[i];
        float range = pointLightRange[i];

        vec3 L = lightPosition - v_WorldPosition;

        // Calculate point light attenuation
        float dist = length(L);
        float attenuation = calculateAttenuation(dist, range);

        // Normalize vectors
        L /= dist;
        vec3 H = normalize(L + V);

        float ndh = dot(normal, H);
        ndh = clamp(ndh, 0.0, 1.0);

        float ndl = dot(normal,  L);
        // Half lambert
        // https://developer.valvesoftware.com/wiki/Half_Lambert
        ndl = ndl * 0.5 + 0.5;

        float shadowContrib = 1.0;
        #if defined(POINT_LIGHT_SHADOWMAP_COUNT)
            if(shadowEnabled){
                shadowContrib = shadowContribs[i];
            }
        #endif

        diffuseItem += lightColor * ndl * attenuation * shadowContrib;
        specularItem += lightColor * ndl * pow(ndh, specularExponent) * attenuation * shadowContrib;
    }
#endif

#ifdef DIRECTIONAL_LIGHT_COUNT
    #if defined(DIRECTIONAL_LIGHT_SHADOWMAP_COUNT)
        float shadowContribs[DIRECTIONAL_LIGHT_COUNT];
        if(shadowEnabled){
            computeShadowOfDirectionalLights(v_WorldPosition, shadowContribs);
        }
    #endif
    for(int i = 0; i < DIRECTIONAL_LIGHT_COUNT; i++){

        vec3 L = -normalize(directionalLightDirection[i]);
        vec3 lightColor = directionalLightColor[i];

        vec3 H = normalize(L + V);

        float ndh = dot(normal, H);
        ndh = clamp(ndh, 0.0, 1.0);

        float ndl = dot(normal, L);
        ndl = ndl * 0.5 + 0.5;

        float shadowContrib = 1.0;
        #if defined(DIRECTIONAL_LIGHT_SHADOWMAP_COUNT)
            if(shadowEnabled){
                shadowContrib = shadowContribs[i];
            }
        #endif

        diffuseItem += lightColor * ndl * shadowContrib;
        specularItem += lightColor * ndl * pow(ndh, specularExponent) * shadowContrib;
    }
#endif

#ifdef SPOT_LIGHT_COUNT
    #if defined(SPOT_LIGHT_SHADOWMAP_COUNT)
        float shadowContribs[SPOT_LIGHT_COUNT];
        if(shadowEnabled){
            computeShadowOfSpotLights(v_WorldPosition, shadowContribs);
        }
    #endif
    for(int i = 0; i < SPOT_LIGHT_COUNT; i++){
        vec3 lightPosition = spotLightPosition[i];
        vec3 spotLightDirection = -normalize(spotLightDirection[i]);
        vec3 lightColor = spotLightColor[i];
        float range = spotLightRange[i];
        float umbraAngleCosine = spotLightUmbraAngleCosine[i];
        float penumbraAngleCosine = spotLightPenumbraAngleCosine[i];
        float falloffFactor = spotLightFalloffFactor[i];

        vec3 L = lightPosition - v_WorldPosition;
        // Calculate attenuation
        float dist = length(L);
        float attenuation = calculateAttenuation(dist, range);

        // Normalize light direction
        L /= dist;
        // Calculate spot light fall off
        float lightDirectCosine = dot(spotLightDirection, L);

        float falloff;
        // Fomular from real-time-rendering
        falloff = clamp((lightDirectCosine-umbraAngleCosine)/(penumbraAngleCosine-umbraAngleCosine), 0.0, 1.0);
        falloff = pow(falloff, falloffFactor);

        vec3 H = normalize(L + V);

        float ndh = dot(normal, H);
        ndh = clamp(ndh, 0.0, 1.0);

        float ndl = dot(normal, L);
        ndl = ndl * 0.5 + 0.5;

        float shadowContrib = 1.0;
        #if defined(SPOT_LIGHT_SHADOWMAP_COUNT)
            if(shadowEnabled){
                shadowContrib = shadowContribs[i];
            }
        #endif

        diffuseItem += lightColor * ndl * attenuation * (1.0-falloff) * shadowContrib;

        specularItem += lightColor * ndl * pow(ndh, specularExponent) * attenuation * (1.0-falloff) * shadowContrib;
    }
#endif

    finalColor.rgb *= diffuseItem;
    finalColor.rgb += specularItem * specularIntensity * specularColor;
    // Rim lightning
    finalColor.rgb += rimLightning;
    // finalColor.rgb += selfIllumination * texColor.rgb;
    // gl_FragColor = finalColor;

    gl_FragColor = vec4(mix(finalColor.rgb, texColor.rgb, selfIllumination), finalColor.a);
}

@end