Shader "Flooded_Grounds/Triplanar_BumpSpec_URP"
{
    Properties
    {
        _TexScale ("Tex Scale", Range (0.1, 10.0)) = 1.0
        _BlendPlateau ("BlendPlateau", Range (0.0, 1.0)) = 0.2
        _MainTex ("Base 1 (RGB) Gloss(A)", 2D) = "white" {}
        _BumpMap1 ("NormalMap 1 (_Y_X)", 2D) = "bump" {}
        _Cutoff ("Alpha cutoff", Range(0,1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" "IgnoreProjector"="True" }
        LOD 400

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D(_MainTex);   SAMPLER(sampler_MainTex);
        TEXTURE2D(_BumpMap1);  SAMPLER(sampler_BumpMap1);

        CBUFFER_START(UnityPerMaterial)
            float _TexScale;
            float _BlendPlateau;
            float _Cutoff;
        CBUFFER_END

        // Recalcule le blend triplanaire + couleur + bump, identique au surf() d'origine.
        // objPos / objNormal : position et normale en ESPACE OBJET (comme thisPos/thisNormal du vertLocal original)
        void TriplanarSample(float3 objPos, float3 objNormal, out half3 albedo, out half alpha, out half3 bumpVecObj)
        {
            half3 blendWeights = abs(objNormal);
            blendWeights = max(blendWeights - _BlendPlateau, 0);
            blendWeights /= (blendWeights.x + blendWeights.y + blendWeights.z).xxx;

            half2 coord1 = objPos.yz * _TexScale;
            half2 coord2 = objPos.zx * _TexScale;
            half2 coord3 = objPos.xy * _TexScale;

            half4 col1 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, coord1);
            half4 col2 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, coord2);
            half4 col3 = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, coord3);

            half2 bumpVec1 = SAMPLE_TEXTURE2D(_BumpMap1, sampler_BumpMap1, coord1).wy * 2 - 1;
            half2 bumpVec2 = SAMPLE_TEXTURE2D(_BumpMap1, sampler_BumpMap1, coord2).wy * 2 - 1;
            half2 bumpVec3 = SAMPLE_TEXTURE2D(_BumpMap1, sampler_BumpMap1, coord3).wy * 2 - 1;

            half3 bump1 = half3(0, bumpVec1.x, bumpVec1.y);
            half3 bump2 = half3(bumpVec2.y, 0, bumpVec2.x);
            half3 bump3 = half3(bumpVec3.x, bumpVec3.y, 0);

            half4 blendedColor = col1 * blendWeights.xxxx + col2 * blendWeights.yyyy + col3 * blendWeights.zzzz;
            bumpVecObj = bump1 * blendWeights.xxx + bump2 * blendWeights.yyy + bump3 * blendWeights.zzz;

            albedo = blendedColor.rgb;
            alpha = blendedColor.a;
        }
        ENDHLSL

        // ---------------------------------------------------------------
        // FORWARD LIT
        // ---------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 color      : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionOSInterp : TEXCOORD0; // position objet (= thisPos)
                float3 normalOSInterp   : TEXCOORD1; // normale objet (= thisNormal)
                float3 positionWS  : TEXCOORD2;
                half4  color       : TEXCOORD3;
                float4 shadowCoord : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.positionOSInterp = IN.positionOS.xyz; // équivalent local de thisPos
                OUT.normalOSInterp   = IN.normalOS;       // équivalent local de thisNormal
                OUT.color = IN.color;
                OUT.shadowCoord = GetShadowCoord(posInputs);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half3 albedo;
                half alpha;
                half3 bumpVecObj;
                TriplanarSample(IN.positionOSInterp, normalize(IN.normalOSInterp), albedo, alpha, bumpVecObj);

                clip(alpha - _Cutoff);

                albedo *= IN.color.rgb;

                // Reconstruction du normal (objet -> monde), comme le hack de l'original
                half3 normalObj = normalize(half3(0, 0, 1) + bumpVecObj);
                half3 normalWS = normalize(TransformObjectToWorldNormal(normalObj));

                Light mainLight = GetMainLight(IN.shadowCoord);
                half3 diffuse = albedo * mainLight.color * saturate(dot(normalWS, mainLight.direction)) * mainLight.shadowAttenuation;
                diffuse += albedo * SampleSH(normalWS);

                #ifdef _ADDITIONAL_LIGHTS
                    uint pixelLightCount = GetAdditionalLightsCount();
                    for (uint lightIndex = 0u; lightIndex < pixelLightCount; lightIndex++)
                    {
                        Light light = GetAdditionalLight(lightIndex, IN.positionWS);
                        diffuse += albedo * light.color * saturate(dot(normalWS, light.direction)) * light.distanceAttenuation * light.shadowAttenuation;
                    }
                #endif

                half4 color = half4(diffuse, alpha);
                color.rgb = MixFog(color.rgb, InitializeInputDataFog(float4(IN.positionWS, 1), 0));
                return color;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // SHADOW CASTER (avec découpe alpha triplanaire)
        // ---------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOSInterp : TEXCOORD0;
                float3 normalOSInterp   : TEXCOORD1;
            };

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(input.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                output.positionCS = positionCS;
                output.positionOSInterp = input.positionOS.xyz;
                output.normalOSInterp = input.normalOS;
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                half3 albedo; half alpha; half3 bumpVecObj;
                TriplanarSample(input.positionOSInterp, normalize(input.normalOSInterp), albedo, alpha, bumpVecObj);
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // DEPTH ONLY (avec découpe alpha triplanaire)
        // ---------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }

            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOSInterp : TEXCOORD0;
                float3 normalOSInterp   : TEXCOORD1;
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.positionOSInterp = input.positionOS.xyz;
                output.normalOSInterp = input.normalOS;
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                half3 albedo; half alpha; half3 bumpVecObj;
                TriplanarSample(input.positionOSInterp, normalize(input.normalOSInterp), albedo, alpha, bumpVecObj);
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
