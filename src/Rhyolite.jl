module Rhyolite

using Vulkan
using TimerOutputs
using MLStyle
using Dictionaries
using UnPack

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
include("init.jl")
include("memory.jl")
include("commands.jl")
include("descriptor_allocator.jl")
include("frames.jl")

include("shaders/dependencies.jl")
include("shaders/resources.jl")
include("pipelines/binding.jl")

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

        # frames
        Frame,
        FrameSynchronization,
        FrameState,
        wait_hasrendered,
        next_frame!,
        command_buffers,

        # commands
        @record,

        # shaders
        ShaderDependencies,
        ShaderResource,
        SampledImage,
        StorageBuffer,

        # pipeline
        BindRequirements,
        BindState

end # module
