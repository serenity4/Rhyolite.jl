module Rhyolite

using Vulkan

import Vulkan: handle, instance, device

using TimerOutputs
using MLStyle
using Dictionaries
using UnPack

using SPIRV: ImageType
using SPIRV

import glslang_jll
const glslangValidator = glslang_jll.glslangValidator(identity)

const to = TimerOutput()
const Optional{T} = Union{T,Nothing}

const debug_callback_c = Ref{Ptr{Cvoid}}(C_NULL)
const debug_messenger = Ref{DebugUtilsMessengerEXT}()

function __init__()
    # for debugging in Vulkan
    debug_callback_c[] =
        @cfunction(default_debug_callback, UInt32, (DebugUtilsMessageSeverityFlagEXT, DebugUtilsMessageTypeFlagEXT, Ptr{vk.VkDebugUtilsMessengerCallbackDataEXT}, Ptr{Cvoid}))
end

include("utils.jl")
include("handle_wrappers.jl")
include("dispatch.jl")
include("init.jl")
include("memory.jl")
include("commands.jl")
include("frames.jl")

include("shaders/dependencies.jl")
include("shaders/resources.jl")
include("shaders/vertex.jl") # type piracy
include("shaders/formats.jl")
include("shaders/specification.jl")
include("shaders/source.jl")
include("shaders/compilation.jl")

include("descriptor_allocator.jl")
include("descriptor_set_layouts.jl")

include("pipelines/binding.jl")
include("pipelines/cache.jl")

include("draw/render_set.jl")

export
        # handles
        AbstractHandle,
        handle,
        Allocated,
        memory,
        Created,
        info,

        # initialization
        init,
        init_debug,
        debug_messenger,

        # setup introspection
        require_extension,
        require_feature,
        require_layer,

        # memory
        download_data,
        upload_data,
        buffer_size,
        find_memory_type,

        # descriptor allocator
        DescriptorAllocator,
        find_pool!,
        allocate_descriptor_sets!,
        free_descriptor_sets!,

        # descriptor set layout cache
        DescriptorSetLayoutCache,

        # queue dispatch
        QueueDispatch,
        queue_infos,
        submit,
        present,
        queue_family_indices,

        # frames
        Frame,
        FrameSynchronization,
        FrameState,
        wait_hasrendered,
        next_frame!,
        command_buffers,

        # commands
        @record,
        ThreadedCommandPool,

        # shaders
        ShaderDependencies,
        ShaderResource,
        ShaderLanguage, SPIR_V, GLSL, HLSL,
        ShaderSpecification,
        ShaderCache, find_shader!, find_source!,
        SampledImage,
        StorageBuffer,
        collect_bindings,
        create_descriptor_set_layouts,
        create_descriptor_set_layouts!,
        vertex_input_attribute_descriptions,

        # pipeline
        BindRequirements,
        BindState,
        GraphicsPipelineCache,

        # render sets
        RenderSet,
        RenderInfo,
        prepare!

end # module
