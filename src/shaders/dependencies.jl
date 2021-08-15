const VertexBuffer = Allocated{Buffer,DeviceMemory}
const IndexBuffer = Allocated{Buffer,DeviceMemory}

"""
Describes data that an object needs to be drawn, but without having a pipeline created yet.
"""
struct ShaderDependencies
    vertex_buffer::VertexBuffer
    index_buffer::Optional{IndexBuffer}
    descriptor_sets::Vector{Created{DescriptorSet,DescriptorSetAllocateInfo}}
end

function Vulkan.update_descriptor_sets(device::Device, shader_dependencies::ShaderDependencies, resources)
    update_descriptor_sets(
        device,
        map(Base.Fix1(WriteDescriptorSet, shader_dependencies), resources),
        [],
    )
end

struct Descriptor
    set::DescriptorSet
    "1-based indexing."
    index::Int
    binding::Int
end
