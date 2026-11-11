# Stick Together Free — Technical Specifications

Seven authored models: Campfire, TreeLog, Axe, Steak, ChickenLeg, Hazel and Bramble. Campfire includes animated flame and smoke. No tent, buggy, trees, grass, extra rocks/firewood models or full forest scene. Neutral studio geometry, cameras, lights and labels are presentation helpers.

## Geometry

| Model | Vertices (Unity) | Triangles | Dimensions (m, Unity XYZ) |
|---|---:|---:|---|
| Campfire | 6077 | 4810 | 1.182 × 0.298 × 1.200 |
| TreeLog | 3759 | 3316 | 2.300 × 0.847 × 0.934 |
| Bramble | 9899 | 7220 | 2.103 × 1.500 × 2.573 |
| Hazel | 9647 | 7220 | 1.930 × 1.800 × 2.077 |
| Axe | 846 | 832 | 0.244 × 0.840 × 0.080 |
| ChickenLeg | 1662 | 1850 | 0.064 × 0.050 × 0.190 |
| Steak | 530 | 496 | 0.092 × 0.027 × 0.230 |

Total Unity imported vertices: 32,420; triangles: 25,744. One UV set per model, no mesh animations and no supplied LOD chain. ChickenLeg: 927 authored vertices / 1662 imported vertices (UV/normal splits), 1850 triangles, approximately 0.19 m long, bottom-centred pivot, mesh-node rotation zero, external textures. The six existing model files and GUIDs are retained from the 2026-09-29 Complete source.

## Unity

Unity 6000.0.77f1, Windows. 7 prefabs, 7 model files, 29 textures (all 2048 × 2048), 12 materials including studio and VFX materials, 6 scenes: Overview_Free and Demo_Free for BRP, URP and HDRP. The product uses the shared `Assets/RetroStyleGames/StickTogether` root and `Assets/RetroStyleGames/Base/Shaders/RSG_Lit.shadergraph` (GUID `d7393aece742b974b8bd8606d7f02d17`).

Shader Graph 17.0.4 is required for Built-in; URP/HDRP use the matching 17.0.4 package. Unity UI 2.0.0 supports labels. Post Processing 3.4.0 was installed in the builder for validation; these Free scenes contain no PostProcessLayer/PostProcessVolume, so it is not a Free runtime dependency. Open only the scenes matching the active render pipeline. Other pipeline scenes require their matching packages. Cross-pipeline material subassets can warn about unavailable pipeline version scripts when only one SRP is installed; the shared RSG shader is retained for compatibility.

All prefab roots have position/rotation zero and scale one. Campfire and TreeLog use static non-convex MeshColliders; Axe, Steak and ChickenLeg use convex MeshColliders. Hazel/Bramble have small capsule colliders for their central woody core; leaf cards do not have separate collision. Fire/smoke are decorative. Lighting is scene-owned. Unity navigation: hold right mouse and use WASD/QE to fly and mouse to look; Shift moves faster, Tab cycles close-up views, R resets to overview.

## Textures and materials

BaseColor: sRGB, with foliage alpha where supplied. MAS: linear, R metallic, G ambient occlusion, B 1, A smoothness. Normal: linear, tangent-space OpenGL +Y; Unity imports as Normal Map. Roughness = 1 − smoothness. ChickenLeg has zero metallic, high-resolution geometry-baked AO, skin smoothness 0.35–0.50 and lower smoothness on the bone; BaseColor and OpenGL normals are baked from the generated high-resolution textured model. Shared Firewood, Rock and Stones textures/materials are required by Campfire and do not imply their separate models are included. Two fire flipbook textures are also included. Raw FBX uses the same maps and naming.

## Unreal

Unreal Engine 5.8, content-only project; two maps `L_Free_Overview` and `L_Free_Demo`. Shared root `/Game/StickTogether`. Seven authored static meshes. Registry asset counts: 8 Blueprint, 6 Material, 11 MaterialInstanceConstant, 7 StaticMesh, 33 Texture2D, 2 World. No Nanite or virtual textures are enabled on the authored content. Existing UE materials retain their Complete PBR packing; ChickenLeg uses the same MAS file as Unity with G to AO, R to metallic and 1−A to roughness. Its normal texture flips green on import for Unreal. One generated convex collision hull on ChickenLeg; the original six use their existing configured collision. No extra runtime plugins required. Python/editor scripting plugins are build tools and disabled in the delivered project. Windows builder validation only; no untested platform support claim.

## Raw FBX and compatibility

Exactly seven FBX files, matching texture dependencies and README. Import file units once: source FBX uses metre units, Unity world units are metres, Unreal world units are centimetres. No embedded texture media. Retain material slots and assign external maps by matching names. Engine scene/VFX playback and colliders are provided in the engine packages, not the raw FBX archive.

Shared paths/GUIDs intentionally support Complete/subpack compatibility. Importing multiple editions can replace shared assets. Free adds ChickenLeg and Free scenes; it adjusts Campfire prefab nesting and the two bushes' central collision while retaining original GUIDs. Original Complete and the six delivered subpacks were not modified.

ChickenLeg is AI-generated: reference image via `fal-ai/nano-banana-pro/edit` on fal; high-resolution textured mesh via `fal-ai/hunyuan3d-v3/image-to-3d` with PBR enabled. Blender cleanup, mesh reduction, new UVs and 2048 px high-to-low baking produced the final game asset. The new geometry and texture maps replace the earlier ChickenLeg while retaining its paths, names and Unity GUIDs. Marketplace AI/rights disclosures and listing fields remain the publisher's review responsibility. This local candidate awaits independent review before upload.

## Raw setup

FBX layout follows StickTogether/{Props,Environment,Foliage}; texture dependencies may live in another group. Use double-sided alpha clipping for foliage. Flame is additive; smoke alpha-blended. See engine editions for complete fire animation setup.
