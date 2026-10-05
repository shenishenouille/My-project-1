Shader "Flooded_Grounds/PBR_TopBlend_URP"
{
    Properties
    {
        _MainTex ("Base Albedo (RGB)", 2D) = "white" {}
        _Spc("Base Metalness(R) Smoothness(A)", 2D) = "black" {}
        _BumpMap ("Base Normal", 2D) = "bump" {}
        _AO("Base AO", 2D)= "white" {}
        _layer1Tex ("Layer1 Albedo (RGB) Smoothness (A)", 2D) = "white" {}
        _layer1Metal ("Layer1 Metalness", Range(0,1)) = 0
        _layer1Norm("Layer 1 Normal", 2D) = "bump" {}
        _layer1Breakup ("Layer1 Breakup (R)", 2D) = "white" {}
        _layer1BreakupAmnt ("Layer1 Breakup Amount", Range(0,1)) = 0.5
        _layer1Tiling("Layer1 Tiling", float) = 10
        _Power ("Layer1 Blend Amount", float ) = 1
        _Shift("Layer1 Blend Height", float) = 1
        _DetailBump ("Detail Normal", 2D) = "bump" {}
        _DetailInt ("DetailNormal Intensity", Range(0,1)) = 0.4
        _DetailTiling("DetailNormal Tiling", float) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        LOD 300

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
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
            TEXTURE2D(_Spc);            SAMPLER(sampler_Spc);
            TEXTURE2D(_BumpMap);        SAMPLER(sampler_BumpMap);
            TEXTURE2D(_AO);             SAMPLER(sampler_AO);
            TEXTURE2D(_layer1Tex);      SAMPLER(sampler_layer1Tex);
            TEXTURE2D(_layer1Norm);     SAMPLER(sampler_layer1Norm);
            TEXTURE2D(_layer1Breakup);  SAMPLER(sampler_layer1Breakup);
            TEXTURE2D(_DetailBump);     SAMPLER(sampler_DetailBump);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _layer1Metal;
                float _layer1BreakupAmnt;
                float _layer1Tiling;
                float _Power;
                float _Shift;
                float _DetailInt;
                float _DetailTiling;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                half3  normalWS    : TEXCOORD2;
                half4  tangentWS   : TEXCOORD3; // w = sign
                half3  bitangentWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
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
                VertexNormalInputs normInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.normalWS    = normInputs.normalWS;
                OUT.tangentWS   = half4(normInputs.tangentWS, IN.tangentOS.w * GetOddNegativeScale());
                OUT.bitangentWS = normInputs.bitangentWS;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.shadowCoord = GetShadowCoord(posInputs);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                float2 uv        = IN.uv;
                float2 uvLayer1  = uv * _layer1Tiling;
                float2 uvDetail  = uv * _DetailTiling;

                // ---- sampling (identique au shader original) ----
                half3 main       = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb;
                half3 norm       = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv));
                half4 spec       = SAMPLE_TEXTURE2D(_Spc, sampler_Spc, uv);
                half3 ao         = SAMPLE_TEXTURE2D(_AO, sampler_AO, uv).rgb;
                half4 layer1     = SAMPLE_TEXTURE2D(_layer1Tex, sampler_layer1Tex, uvLayer1);
                half3 layer1norm = UnpackNormal(SAMPLE_TEXTURE2D(_layer1Norm, sampler_layer1Norm, uvLayer1));
                half  layer1Breakup = SAMPLE_TEXTURE2D(_layer1Breakup, sampler_layer1Breakup, uvLayer1).r;
                half3 detnorm    = UnpackNormal(SAMPLE_TEXTURE2D(_DetailBump, sampler_DetailBump, uvDetail));

                half3 modNormal = norm + half3(layer1norm.r * 0.6, layer1norm.g * 0.6, 0.0);

                // repère tangent -> monde (remplace WorldNormalVector du surface shader)
                half3x3 tangentToWorld = half3x3(IN.tangentWS.xyz, IN.bitangentWS.xyz, IN.normalWS);
                half3 modNormalWS = normalize(mul(modNormal, tangentToWorld));

                // ---- masques de blend (identique) ----
                half3 layer1direction = half3(0, 1, 0);
                half blend  = dot(modNormalWS, layer1direction);
                half blend2 = (blend * _Power + _Shift) * lerp(1.0, layer1Breakup, _layer1BreakupAmnt);
                blend2 = saturate(pow(blend2, 3));

                // ---- combinaison des deux couches ----
                half3 blendedNormalTS = lerp(norm, layer1norm, blend2);
                blendedNormalTS += detnorm * half3(_DetailInt, _DetailInt, 0.0);
                blendedNormalTS = normalize(blendedNormalTS);

                half3 albedo     = lerp(main, layer1.rgb, blend2);
                half  smoothness = lerp(spec.a, layer1.a, blend2);
                half  metallic   = lerp(spec.r, _layer1Metal, blend2);

                half3 normalWS = normalize(mul(blendedNormalTS, tangentToWorld));

                // ---- assemblage URP (équivalent SurfaceOutputStandard + lighting) ----
                InputData inputData = (InputData)0;
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                inputData.shadowCoord = IN.shadowCoord;
                inputData.fogCoord = 0;
                inputData.vertexLighting = half3(0, 0, 0);
                inputData.bakedGI = SampleSH(normalWS);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionHCS);
                inputData.shadowMask = half4(1, 1, 1, 1);

                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = albedo;
                surfaceData.metallic = metallic;
                surfaceData.specular = half3(0, 0, 0);
                surfaceData.smoothness = smoothness;
                surfaceData.normalTS = blendedNormalTS;
                surfaceData.occlusion = ao.r;
                surfaceData.emission = half3(0, 0, 0);
                surfaceData.alpha = 1.0;
                surfaceData.clearCoatMask = 0;
                surfaceData.clearCoatSmoothness = 0;

                half4 color = UniversalFragmentPBR(inputData, surfaceData);
                color.rgb = MixFog(color.rgb, InitializeInputDataFog(float4(IN.positionWS, 1), 0));
                return color;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // SHADOW CASTER (nécessaire pour que l'objet projette une ombre)
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
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
            };

            float4 GetShadowPositionHClip(Attributes input)
            {
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

                return positionCS;
            }

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                output.positionCS = GetShadowPositionHClip(input);
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // DEPTH ONLY (pré-passe de profondeur, SSAO, etc.)
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
