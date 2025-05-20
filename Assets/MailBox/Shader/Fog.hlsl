#if defined(CUSTOM_FOG)
float4 FourColorGradientSmooth(float t, float4 color1, float4 color2, float4 color3, float4 color4, float boundary1,
                               float boundary2, float boundary3, float fogPower)
{
    float toFirstBoundary = smoothstep(0, boundary1, t);
    float betweenFirstAndSecondBoundary = smoothstep(boundary1, boundary2, t);
    float betweenSecondAndThirdBoundary = smoothstep(boundary2, boundary3, t);

    float isFirst = 1 - toFirstBoundary;
    float isSecond = toFirstBoundary - betweenFirstAndSecondBoundary;
    float isThird = betweenFirstAndSecondBoundary - betweenSecondAndThirdBoundary;
    float isFourth = betweenSecondAndThirdBoundary;

    float4 blended1 = lerp(color1, color2, t / boundary1);
    float4 blended2 = lerp(color2, color3, (t - boundary1) / (boundary2 - boundary1));
    float4 blended3 = lerp(color3, color4, (t - boundary2) / (boundary3 - boundary2));

    float4 finalColor = isFirst * blended1 + isSecond * blended2 + isThird * blended3 + isFourth *
        color4;
    finalColor.a = pow(t, fogPower);

    return finalColor;
}


float ComputeCustomFogFactor(float distance, float minDistance, float maxDistance)
{
    return saturate((distance - minDistance) / (maxDistance - minDistance));
}


float _MinFogDistance;
float _MaxFogDistance;
float4 _NoFogColor;
float4 _NearColor;
float4 _MidColor;
float4 _FarColor;
float _NearColorBounds;
float _MidColorBounds;
float _FarColorBounds;
float _FogPower;
float3 _FogStartPosition;

#endif
