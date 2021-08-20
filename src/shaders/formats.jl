@enum ShaderLanguage begin
    SPIR_V = 1
    GLSL   = 2
    HLSL   = 3
end

function file_ext(language::ShaderLanguage, stage::ShaderStageFlag)
    language in [GLSL, HLSL] || error("Cannot get file extension for language $language")
    @match stage begin
        &SHADER_STAGE_VERTEX_BIT => "vert"
        &SHADER_STAGE_FRAGMENT_BIT => "frag"
        &SHADER_STAGE_TESSELLATION_CONTROL_BIT => "tesc"
        &SHADER_STAGE_TESSELLATION_EVALUATION_BIT => "tese"
        &SHADER_STAGE_GEOMETRY_BIT => "geom"
        &SHADER_STAGE_COMPUTE_BIT => "comp"
        &SHADER_STAGE_RAYGEN_BIT_KHR => "rgen"
        &SHADER_STAGE_INTERSECTION_BIT_KHR => "rint"
        &SHADER_STAGE_ANY_HIT_BIT_KHR => "rahit"
        &SHADER_STAGE_CLOSEST_HIT_BIT_KHR => "rchit"
        &SHADER_STAGE_MISS_BIT_KHR => "rmiss"
        &SHADER_STAGE_CALLABLE_BIT_KHR => "rcall"
        &SHADER_STAGE_MESH_BIT_NV => "mesh"
        &SHADER_STAGE_TASK_BIT_NV => "task"
        _ => error("Unknown stage $stage")
    end
end

"""
    shader_stage(file_ext)

Automatically detect a shader stage from a file extension.
Can only be used with [`GLSL`](@ref) and [`HLSL`](@ref).

## Examples

```julia
julia> shader_stage("my_shader.frag", GLSL) == SHADER_STAGE_FRAGMENT_BIT
true

julia> shader_stage("my_shader.geom", HLSL) == SHADER_STAGE_GEOMETRY_BIT
true
```
"""
function shader_stage(file::AbstractString, language::ShaderLanguage)
    _, file_ext = splitext(file)
    language in [GLSL, HLSL] || error("Cannot retrieve shader stage from shader language $language")
    @match file_ext begin
        ".vert" => SHADER_STAGE_VERTEX_BIT
        ".frag" => SHADER_STAGE_FRAGMENT_BIT
        ".tesc" => SHADER_STAGE_TESSELLATION_CONTROL_BIT
        ".tese" => SHADER_STAGE_TESSELLATION_EVALUATION_BIT
        ".geom" => SHADER_STAGE_GEOMETRY_BIT
        ".comp" => SHADER_STAGE_COMPUTE_BIT
        ".rgen" => SHADER_STAGE_RAYGEN_BIT_KHR
        ".rint" => SHADER_STAGE_INTERSECTION_BIT_KHR
        ".rahit" => SHADER_STAGE_ANY_HIT_BIT_KHR
        ".rchit" => SHADER_STAGE_CLOSEST_HIT_BIT_KHR
        ".rmiss" => SHADER_STAGE_MISS_BIT_KHR
        ".rcall" => SHADER_STAGE_CALLABLE_BIT_KHR
        ".mesh" => SHADER_STAGE_MESH_BIT_NV
        ".task" => SHADER_STAGE_TASK_BIT_NV
        _ => error("Unknown file extension $file_ext")
    end
end

"""
    shader_language(file_ext)

Automatically detect a [`ShaderLanguage`](@ref) from the file extension.
Currently, only .spv, .glsl and .hlsl are recognized.

## Examples

```julia
julia> shader_language("my_shader.glsl")
GLSL
julia> shader_language("my_shader.spv")
SPIR_V
```
"""
function shader_language(file::AbstractString)
    _, file_ext = splitext(file)
    @match file_ext begin
        ".spv" => SPIR_V
        ".glsl" => GLSL
        ".hlsl" => HLSL
        _ => error("Unknown file extension $file_ext")
    end
end
