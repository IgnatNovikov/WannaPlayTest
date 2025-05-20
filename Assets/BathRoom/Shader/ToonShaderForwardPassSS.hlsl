#ifndef UNIVERSAL_SIMPLE_LIT_PASS_INCLUDED
#define UNIVERSAL_SIMPLE_LIT_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "ToonShaderInput.hlsl"
#include "./Fog.hlsl"


struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 texcoord : TEXCOORD0;
    float2 staticLightmapUV : TEXCOORD1;
    float2 dynamicLightmapUV : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float2 uv : TEXCOORD0;

    float3 positionWS : TEXCOORD1; // xyz: posWS

    #ifdef _NORMALMAP
    half4 normalWS : TEXCOORD2; // xyz: normal, w: viewDir.x
    half4 tangentWS : TEXCOORD3; // xyz: tangent, w: viewDir.y
    half4 bitangentWS : TEXCOORD4; // xyz: bitangent, w: viewDir.z
    #else
    half3 normalWS : TEXCOORD2;
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        half4 fogFactorAndVertexLight  : TEXCOORD5; // x: fogFactor, yzw: vertex light
    #else
    half fogFactor : TEXCOORD5;
    #endif

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        float4 shadowCoord             : TEXCOORD6;
    #endif

    DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 7);

    #ifdef DYNAMICLIGHTMAP_ON
    float2  dynamicLightmapUV : TEXCOORD8; // Dynamic lightmap UVs
    #endif
    float4 positionCS : SV_POSITION;

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;

    inputData.positionWS = input.positionWS;

    #ifdef _NORMALMAP
    half3 viewDirWS = half3(input.normalWS.w, input.tangentWS.w, input.bitangentWS.w);
    inputData.tangentToWorld = half3x3(input.tangentWS.xyz, input.bitangentWS.xyz, input.normalWS.xyz);
    inputData.normalWS = TransformTangentToWorld(normalTS, inputData.tangentToWorld);
    #else
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(inputData.positionWS);
    inputData.normalWS = input.normalWS;
    #endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    viewDirWS = SafeNormalize(viewDirWS);

    inputData.viewDirectionWS = viewDirWS;

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        inputData.shadowCoord = input.shadowCoord;
    #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
    #else
    inputData.shadowCoord = float4(0, 0, 0, 0);
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        inputData.fogCoord = InitializeInputDataFog(float4(inputData.positionWS, 1.0), input.fogFactorAndVertexLight.x);
        inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
    #else
    inputData.fogCoord = InitializeInputDataFog(float4(inputData.positionWS, 1.0), input.fogFactor);
    inputData.vertexLighting = half3(0, 0, 0);
    #endif

    #if defined(DYNAMICLIGHTMAP_ON)
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.dynamicLightmapUV, input.vertexSH, inputData.normalWS);
    #else
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);
    #endif

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);

    #if defined(DEBUG_DISPLAY)
    #if defined(DYNAMICLIGHTMAP_ON)
    inputData.dynamicLightmapUV = input.dynamicLightmapUV.xy;
    #endif
    #if defined(LIGHTMAP_ON)
    inputData.staticLightmapUV = input.staticLightmapUV;
    #else
    inputData.vertexSH = input.vertexSH;
    #endif
    #endif
}

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

// Used in Standard (Simple Lighting) shader
Varyings Vert(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
    output.positionWS.xyz = vertexInput.positionWS;
    output.positionCS = vertexInput.positionCS;

    #ifdef _NORMALMAP
    half3 viewDirWS = GetWorldSpaceViewDir(vertexInput.positionWS);
    output.normalWS = half4(normalInput.normalWS, viewDirWS.x);
    output.tangentWS = half4(normalInput.tangentWS, viewDirWS.y);
    output.bitangentWS = half4(normalInput.bitangentWS, viewDirWS.z);
    #else
    output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);
    #endif

    OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
    #ifdef DYNAMICLIGHTMAP_ON
    output.dynamicLightmapUV = input.dynamicLightmapUV.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
    #endif
    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
        output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
    #endif

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        output.shadowCoord = GetShadowCoord(vertexInput);
    #endif

    return output;
}

half4 RimLight(half3 normal, half3 viewDirection)
{
    half NdotV = dot(normal, viewDirection);
    half rim = abs(1 - abs(NdotV));
    rim = pow(rim, _RimPower);
    rim *= _RimIntensity;
    return lerp(half4(0, 0, 0, 0), _RimColor, saturate(rim));
}

inline half3 applyHue(half3 aColor, float aHue)
{
    const float angle = radians(aHue);
    const half3 k = float3(0.57735, 0.57735, 0.57735);
    const float cosAngle = cos(angle);
    //Rodrigues' rotation formula
    return aColor * cosAngle + cross(k, aColor) * sin(angle) + k * dot(k, aColor) * (1 - cosAngle);
}

inline half3 applyHSBEffect(half3 startColor)
{
    half3 outputColor = startColor;
    outputColor.rgb = applyHue(outputColor.rgb, _Hue);
    outputColor.rgb = (outputColor.rgb - 0.5f) * (_Contrast) + 0.5f;
    outputColor.rgb = outputColor.rgb + _Brightness;
    const half3 intensity = dot(outputColor.rgb, float3(0.299, 0.587, 0.114));
    outputColor.rgb = lerp(intensity, outputColor.rgb, _Saturation);
    return outputColor;
}

half4 CustomLightning(Light light, InputData inputData, SurfaceData surfaceData, float isMainLight)
{
    float3 hsvColorMainLightColor = RgbToHsv(light.color);
    hsvColorMainLightColor.y *= _DirectionalLightSaturationCoef;
    half3 lightColor = lerp(light.color, HsvToRgb(hsvColorMainLightColor), isMainLight);
    float attenuation = light.distanceAttenuation * light.shadowAttenuation;
    half3 normalDir = inputData.normalWS;
    half NdotL = dot(normalDir, light.direction) * 0.5 + 0.5;
    half ramp = smoothstep(_RampThreshold - _RampSmoothing, _RampThreshold + _RampSmoothing, NdotL);
    half3 rampColor = lerp(_SColor.rgb, _HColor.rgb, ramp);
    half3 shadow = (_FallingShadowColor.rgb + (half3(1, 1, 1) - _FallingShadowColor.rgb) * attenuation) * ramp;
    half4 c = half4(rampColor * lightColor * shadow, 1);
    
    c.rgb += RimLight(normalDir, inputData.viewDirectionWS).rgb;

    #if defined(_SPECGLOSSMAP) || defined(_SPECULAR_COLOR)
    half smoothness = exp2(10 * surfaceData.smoothness + 1);
    half3 attenuatedLightColor = light.color * attenuation;
    c.rgb += LightingSpecular(attenuatedLightColor, light.direction, inputData.normalWS, inputData.viewDirectionWS, half4(surfaceData.specular, 1), smoothness);
    #endif

    c.a *= surfaceData.alpha;
    return c;
}

float2 rotateVector(float2 v, float angle, float2 pivot = float2(0, 0))
{
    v -= pivot;
    float angleInRadians = angle * PI / 180.0;
    float sinAngle = sin(angleInRadians);
    float cosAngle = cos(angleInRadians);
    v = float2(v.x * cosAngle - v.y * sinAngle, v.x * sinAngle + v.y * cosAngle);
    v += pivot;
    return v;
}

#if defined(FLICKERING)
half4 Flickering(Varyings input)
{
    float3 screenPos = ComputeNormalizedDeviceCoordinatesWithZ(input.positionWS, UNITY_MATRIX_VP);
    float3 rootScreenPos = ComputeNormalizedDeviceCoordinatesWithZ(_FlickerRootPos.xyz, UNITY_MATRIX_VP);
    float3 viewDirWS = _WorldSpaceCameraPos - _FlickerRootPos.xyz;
    float distToCamera = length(viewDirWS);
    float2 screenSpaceUV = ((screenPos - rootScreenPos) * _FlickerShineScale * distToCamera).xy;
    float summDuration = _FlickerShineShowingDuration + _FlickerShineHidingDuration;
    float time = max(0, _Time.y - _StartTime - _FlickerShineDelay);
    float animationTime = (fmod(time, summDuration) - _FlickerShineHidingDuration) / summDuration;
    float2 uv = frac(screenSpaceUV + animationTime * _FlickerForwardOrBackward);
    half4 texColor = SAMPLE_TEXTURE2D(_FlickerTex, sampler_FlickerTex, uv);
    half4 finalColor = _FlickerColor.a * (_FlickerColor * texColor);
    return 1 + finalColor;
}
#endif

half4 CalculateLightingColorCustom(LightingData lightingData, SurfaceData surfaceData, Varyings input)
{
    half3 lightingColor = 0;

    if (IsOnlyAOLightingFeatureEnabled())
    {
        return half4(lightingData.giColor, surfaceData.alpha); // Contains white + AO
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_GLOBAL_ILLUMINATION))
    {
        lightingColor += lightingData.giColor;
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_MAIN_LIGHT))
    {
        lightingColor += lightingData.mainLightColor;
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_ADDITIONAL_LIGHTS))
    {
        lightingColor += lightingData.additionalLightsColor;
    }

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_VERTEX_LIGHTING))
    {
        lightingColor += lightingData.vertexLightingColor;
    }

    lightingColor *= surfaceData.albedo;

    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_EMISSION))
    {
        lightingColor += lightingData.emissionColor;
    }

    #if defined(FLICKERING)
    lightingColor *= Flickering(input);
    #endif

    return half4(lightingColor, surfaceData.alpha);
}

//UniversalFragmentBlinnPhong
half4 CustomLightningURP(InputData inputData, SurfaceData surfaceData, Varyings input)
{
    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, debugColor))
    {
        return debugColor;
    }
    #endif

    uint meshRenderingLayers = GetMeshRenderingLayer();
    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, aoFactor);

    inputData.bakedGI *= surfaceData.albedo;

    LightingData lightingData = CreateLightingData(inputData, surfaceData);
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
    {
        lightingData.mainLightColor += CustomLightning(mainLight, inputData, surfaceData, 1).rgb;
    }

    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_CLUSTERED_LIGHTING
    for (uint lightIndex = 0; lightIndex < min(_AdditionalLightsDirectionalCount, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
        {
            lightingData.additionalLightsColor += CustomLightning(light, inputData, surfaceData, 0);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
        {
            lightingData.additionalLightsColor += CustomLightning(light, inputData, surfaceData, 0).rgb;
        }
    LIGHT_LOOP_END
    #endif

    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * surfaceData.albedo;
    #endif

    return CalculateLightingColorCustom(lightingData, surfaceData, input);
}

half4 Frag(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    SurfaceData surfaceData;
    InitializeSimpleLitSurfaceData(input.uv, surfaceData);

    surfaceData.albedo = applyHSBEffect(surfaceData.albedo);
    float2 screenCoord = GetNormalizedScreenSpaceUV(input.positionCS);
    if (_ScreenParams.x > _ScreenParams.y) {
        screenCoord.y *= _ScreenParams.y / _ScreenParams.x;
    }
    else {
        screenCoord.x *= _ScreenParams.x / _ScreenParams.y;
    }
    float4 screenSpaceColor = SAMPLE_TEXTURE2D(_ScreenSpaceTex, sampler_ScreenSpaceTex,screenCoord );
    surfaceData.albedo = lerp(screenSpaceColor.rgb,surfaceData.albedo, surfaceData.alpha);
    
    InputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);
    SETUP_DEBUG_TEXTURE_DATA(inputData, input.uv, _BaseMap);

    #ifdef _DBUFFER
    ApplyDecalToSurfaceData(input.positionCS, surfaceData, inputData);
    #endif

    half4 color = CustomLightningURP(inputData, surfaceData, input);
    #if defined(CUSTOM_FOG)
    float customFogFactor = ComputeCustomFogFactor(distance(input.positionWS, _FogStartPosition), _MinFogDistance,
                                                   _MaxFogDistance);
    float4 fog = FourColorGradientSmooth(customFogFactor, _NoFogColor, _NearColor, _MidColor, _FarColor,
                                         _NearColorBounds, _MidColorBounds, _FarColorBounds, _FogPower);
    color.rgb = lerp(color.rgb, fog.rgb, fog.a * _FogIntensity);
    #endif

   // color.rgb = lerp(screenSpaceColor.rgb,color.rgb, color.a);
    color.a = OutputAlpha(color.a, _Surface);
 
    return color;
}

#endif
