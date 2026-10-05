// NOTE IMPORTANTE :
// Le shader d'origine utilise un modèle d'éclairage custom "LightingTreeLeaf"
// défini dans UnityBuiltin3xTreeLibrary.cginc (fichier interne du built-in RP,
// non fourni). Sa formule exacte de translucence n'est donc pas reproductible
// au bit près. Ce shader reconstruit une approximation standard de translucence
// "wrap-around" (technique courante pour du feuillage) : diffuse + spéculaire
// Blinn-Phong + un terme de lumière transmise à travers la feuille, pondéré par
// la translucency map. Ajuste visuellement _Shininess et le facteur de
// translucence (INTENSITE_TRANSLUCENCE ci-dessous) si le rendu ne correspond
// pas à tes attentes.
//
// Comme dans l'original ("noforwardadd"), seule la lumière principale (+ SH
// ambiante) contribue à l'éclairage — les lumières additionnelles ne sont pas
// prises en compte ici non plus.
//
// Vent / instancing Terrain : non supportés, voir la conversion du shader
// d'écorce pour le contexte complet.

Shader "Nature/Tree Creator Leaves URP"
{
    Properties
    {
        _Color ("Main Color", Color) = (1,1,1,1)
        _Shininess ("Shininess", Range (0.01, 1)) = 0.078125
        _MainTex ("Base (RGB) Alpha (A)", 2D) = "white" {}
        _BumpMap ("Normalmap", 2D) = "bump" {}
        _GlossMap ("Gloss (A)", 2D) = "black" {}
        _TranslucencyMap ("Translucency (A)", 2D) = "white" {}
        _ShadowOffset ("Shadow Offset (A)", 2D) = "black" {}
        _Cutoff ("Alpha cutoff", Range(0,1)) = 0.3
    }

    SubShader
    {
        Tags { "IgnoreProjector"="True" "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }
        LOD 200
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float _Shininess;
            float4 _MainTex_ST;
            float _Cutoff;
        CBUFFER_END
        ENDHLSL

        // ---------------------------------------------------------------
        // FORWARD LIT
        // ---------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // Facteur d'intensité de la translucence — à ajuster visuellement.
            #define INTENSITE_TRANSLUCENCE 1.0

            TEXTURE2D(_MainTex);          SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);          SAMPLER(sampler_BumpMap);
            TEXTURE2D(_GlossMap);         SAMPLER(sampler_GlossMap);
            TEXTURE2D(_TranslucencyMap);  SAMPLER(sampler_TranslucencyMap);

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
                half4  color       : TEXCOORD5; // color.a = AO, comme l'original
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

            half4 frag(Varyings IN, bool frontFace : SV_IsFrontFace) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half4 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                clip(c.a - _Cutoff);

                half3 albedo = c.rgb * IN.color.rgb * IN.color.a * _Color.rgb;
                half gloss = SAMPLE_TEXTURE2D(_GlossMap, sampler_GlossMap, IN.uv).a;
                half3 translucencyMap = SAMPLE_TEXTURE2D(_TranslucencyMap, sampler_TranslucencyMap, IN.uv).rgb;

                half3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv));

                // Cull Off : on flippe le normal pour la face arrière (comme le ferait
                // FaceSign dans un surface shader double-face).
                half3x3 tangentToWorld = half3x3(IN.tangentWS.xyz, IN.bitangentWS.xyz, IN.normalWS);
                half3 normalWS = normalize(mul(normalTS, tangentToWorld));
                if (!frontFace) normalWS = -normalWS;

                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);

                Light mainLight = GetMainLight(IN.shadowCoord);
                half atten = mainLight.shadowAttenuation;

                // ---- Diffuse + spéculaire (façade avant de la feuille) ----
                half nDotL = saturate(dot(normalWS, mainLight.direction));
                half3 halfDir = normalize(mainLight.direction + viewDirWS);
                half nDotH = saturate(dot(normalWS, halfDir));
                half specPower = exp2(_Shininess * 11.0 + 1.0);
                half3 specular = gloss * pow(nDotH, specPower) * mainLight.color * atten;

                half3 diffuse = albedo * mainLight.color * nDotL * atten;
                diffuse += albedo * SampleSH(normalWS);

                // ---- Translucence (lumière traversant la feuille, vue de dos) ----
                half backLight = saturate(-dot(normalWS, mainLight.direction));
                half viewAlignment = saturate(dot(viewDirWS, -mainLight.direction));
                half3 translucency = translucencyMap * albedo * mainLight.color
                                      * (backLight + viewAlignment * 0.5) * atten
                                      * INTENSITE_TRANSLUCENCE;

                half4 outColor = half4(diffuse + specular + translucency, c.a);
                outColor.rgb = MixFog(outColor.rgb, InitializeInputDataFog(float4(IN.positionWS, 1), 0));
                return outColor;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // SHADOW CASTER (avec découpe alpha, double-face)
        // ---------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
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
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).a;
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }

        // ---------------------------------------------------------------
        // DEPTH ONLY (avec découpe alpha, double-face)
        // ---------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            Cull Off
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).a;
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
