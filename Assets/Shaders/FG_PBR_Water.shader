Shader "Flooded_Grounds/PBR_Water_URP"
{
    Properties
    {
        _Color ("Main Color", Color) = (1,1,1,1)
        _Emis("Self-Ilumination", Range(0,1)) = 0.1
        _Smth("Smoothness", Range(0,1)) = 0.9
        _Parallax ("Height", Range (0.005, 0.08)) = 0.02
        _MainTex ("Base (RGB) Gloss (A)", 2D) = "white" {}
        _BumpMap ("Normalmap", 2D) = "bump" {}
        _BumpMap2 ("Normalmap2", 2D) = "bump" {}
        _BumpLerp("Normalmap2 Blend", Range(0,1)) = 0.5
        _ParallaxMap ("Heightmap", 2D) = "black" {}
        _ScrollSpeed("Scroll Speed", float) = 0.2
        _WaveFreq("Wave Frequency", float) = 20
        _WaveHeight("Wave Height", float) = 0.1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        LOD 200

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float _Emis;
            float _Smth;
            float _Parallax;
            float4 _MainTex_ST;
            float _BumpLerp;
            float _ScrollSpeed;
            float _WaveFreq;
            float _WaveHeight;
        CBUFFER_END

        // Déplacement vertical par vagues sinusoïdales, identique à vert() de l'original.
        float3 ApplyWaveDisplacement(float3 positionOS)
        {
            float phase = _Time.x * _WaveFreq;
            float offset = (positionOS.x + (positionOS.z * 2)) * 8;
            positionOS.y = sin(phase + offset) * _WaveHeight;
            return positionOS;
        }

        // Reproduction de UnityStandardUtils.cginc / ParallaxOffset (absente en URP)
        half2 ParallaxOffsetURP(half h, half height, half3 viewDirTS)
        {
            h = h * height - height * 0.5;
            half3 v = normalize(viewDirTS);
            v.z += 0.42;
            return h * (v.xy / v.z);
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

            TEXTURE2D(_MainTex);     SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);     SAMPLER(sampler_BumpMap);
            TEXTURE2D(_BumpMap2);    SAMPLER(sampler_BumpMap2);
            TEXTURE2D(_ParallaxMap); SAMPLER(sampler_ParallaxMap);

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
                half4  tangentWS   : TEXCOORD3;
                half3  bitangentWS : TEXCOORD4;
                half3  viewDirTS   : TEXCOORD5;
                float4 shadowCoord : TEXCOORD6;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                IN.positionOS.xyz = ApplyWaveDisplacement(IN.positionOS.xyz);

                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.normalWS    = normInputs.normalWS;
                OUT.tangentWS   = half4(normInputs.tangentWS, IN.tangentOS.w * GetOddNegativeScale());
                OUT.bitangentWS = normInputs.bitangentWS;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.shadowCoord = GetShadowCoord(posInputs);

                // Direction de vue en espace tangent (remplace IN.viewDir du surface shader)
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(posInputs.positionWS);
                half3x3 worldToTangent = half3x3(OUT.tangentWS.xyz, OUT.bitangentWS.xyz, OUT.normalWS);
                OUT.viewDirTS = mul(worldToTangent, viewDirWS);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                float t = _Time.x;
                half scrollX  = _ScrollSpeed * t;
                half scrollY  = (_ScrollSpeed * t) * 0.5;
                half scrollX2 = (1 - _ScrollSpeed) * t;
                half scrollY2 = (1 - _ScrollSpeed * t) * 0.5;

                float2 uvParallax = IN.uv + half2(scrollX * 0.2, scrollY * 0.2);

                half h = SAMPLE_TEXTURE2D(_ParallaxMap, sampler_ParallaxMap, uvParallax).r;
                half2 offset = ParallaxOffsetURP(h, _Parallax, IN.viewDirTS);

                float2 uvMain = IN.uv + offset + half2(scrollX, scrollY);

                half2 uv1 = IN.uv + offset + half2(scrollX, scrollY);
                half2 uv2 = IN.uv + offset + half2(scrollX2, scrollY2);

                half3 nrml  = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv1));
                half3 nrml2 = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv2));
                half3 nrml3 = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap2, sampler_BumpMap2, IN.uv));

                half4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvMain);

                half3 finalNormalTS = lerp(nrml.rgb + (nrml2.rgb * half3(1, 1, 0)), nrml3, _BumpLerp);
                finalNormalTS = normalize(finalNormalTS);

                half3 albedo = tex.rgb * _Color.rgb;
                half3 emission = tex.rgb * _Color.rgb * _Emis;

                half3x3 tangentToWorld = half3x3(IN.tangentWS.xyz, IN.bitangentWS.xyz, IN.normalWS);
                half3 normalWS = normalize(mul(finalNormalTS, tangentToWorld));

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
                surfaceData.metallic = 0;
                surfaceData.specular = half3(0, 0, 0);
                surfaceData.smoothness = _Smth;
                surfaceData.normalTS = finalNormalTS;
                surfaceData.occlusion = 1;
                surfaceData.emission = emission;
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
        // SHADOW CASTER (reproduit le déplacement des vagues pour rester cohérent)
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
            };

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);

                input.positionOS.xyz = ApplyWaveDisplacement(input.positionOS.xyz);

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
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // DEPTH ONLY
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
                input.positionOS.xyz = ApplyWaveDisplacement(input.positionOS.xyz);
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
