// NOTE IMPORTANTE :
// Ce shader porte fidèlement la partie visuelle (surf) du shader d'origine
// "Nature/Tree Creator Bark". L'animation de vent et le cross-fade de LOD
// du système Tree Creator (fonction TreeVertBark, variables _TreeInstanceColor /
// _TreeInstanceScale / _SquashAmount injectées par le moteur d'arbres du Terrain)
// ne sont PAS repris ici : ce système est spécifique au built-in render pipeline
// et n'est pas piloté par le Terrain sous URP. Si tes arbres doivent bouger au
// vent sous URP, il faudra soit les convertir en prefabs (LODGroup + un shader
// avec vertex wind fait en Shader Graph), soit passer par des arbres SpeedTree.

Shader "Nature/Tree Creator Bark URP"
{
    Properties
    {
        _Color ("Main Color", Color) = (1,1,1,1)
        _SpecColor ("Specular Color", Color) = (0.5, 0.5, 0.5, 1)
        _Shininess ("Shininess", Range (0.01, 1)) = 0.078125
        _MainTex ("Base (RGB) Alpha (A)", 2D) = "white" {}
        _BumpMap ("Normalmap", 2D) = "bump" {}
        _GlossMap ("Gloss (A)", 2D) = "black" {}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        LOD 200

        // ---------------------------------------------------------------
        // FORWARD LIT (Blinn-Phong, équivalent du surf() d'origine)
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);   SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);   SAMPLER(sampler_BumpMap);
            TEXTURE2D(_GlossMap);  SAMPLER(sampler_GlossMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _SpecColor;
                float _Shininess;
                float4 _MainTex_ST;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;
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
                half4  color       : TEXCOORD5;
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

                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.normalWS    = normInputs.normalWS;
                OUT.tangentWS   = half4(normInputs.tangentWS, IN.tangentOS.w * GetOddNegativeScale());
                OUT.bitangentWS = normInputs.bitangentWS;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.color       = IN.color;
                OUT.shadowCoord = GetShadowCoord(posInputs);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half4 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                half3 albedo = c.rgb * IN.color.rgb * IN.color.a * _Color.rgb;
                half gloss = SAMPLE_TEXTURE2D(_GlossMap, sampler_GlossMap, IN.uv).a;

                half3x3 tangentToWorld = half3x3(IN.tangentWS.xyz, IN.bitangentWS.xyz, IN.normalWS);
                half3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv));
                half3 normalWS = normalize(mul(normalTS, tangentToWorld));

                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);

                Light mainLight = GetMainLight(IN.shadowCoord);
                half3 halfDir = normalize(mainLight.direction + viewDirWS);
                half nDotL = saturate(dot(normalWS, mainLight.direction));
                half nDotH = saturate(dot(normalWS, halfDir));

                // Équivalent BlinnPhong : Specular = _Shininess (exposant), Gloss = intensité
                half specPower = exp2(_Shininess * 11.0 + 1.0); // ~[2, 4096], approx du mapping legacy
                half3 specular = _SpecColor.rgb * gloss * pow(nDotH, specPower) * mainLight.shadowAttenuation;

                half3 diffuse = albedo * mainLight.color * nDotL * mainLight.shadowAttenuation;
                diffuse += albedo * SampleSH(normalWS);

                #ifdef _ADDITIONAL_LIGHTS
                    uint pixelLightCount = GetAdditionalLightsCount();
                    for (uint lightIndex = 0u; lightIndex < pixelLightCount; lightIndex++)
                    {
                        Light light = GetAdditionalLight(lightIndex, IN.positionWS);
                        half atten = light.distanceAttenuation * light.shadowAttenuation;
                        half3 h = normalize(light.direction + viewDirWS);
                        half ndl = saturate(dot(normalWS, light.direction));
                        half ndh = saturate(dot(normalWS, h));
                        diffuse += albedo * light.color * ndl * atten;
                        specular += _SpecColor.rgb * gloss * pow(ndh, specPower) * light.color * atten;
                    }
                #endif

                half4 outColor = half4(diffuse + specular, c.a);
                outColor.rgb = MixFog(outColor.rgb, InitializeInputDataFog(float4(IN.positionWS, 1), 0));
                return outColor;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // SHADOW CASTER
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
