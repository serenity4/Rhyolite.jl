const VertexBuffer = Allocated{Buffer,DeviceMemory}
const IndexBuffer = Allocated{Buffer,DeviceMemory}

"""
Describes data that an object needs to be drawn, but without having a pipeline created yet.
"""
struct ShaderDependencies
    vertex_buffer::VertexBuffer
    index_buffer::Optional{IndexBuffer}
    descriptor_sets::Vector{DescriptorSet}
    set_layouts::Vector{DescriptorSetLayout}
end

function Vulkan.update_descriptor_sets(device, shader_dependencies::ShaderDependencies, resources)
    update_descriptor_sets(
        device,
        map(Base.Fix1(WriteDescriptorSet, shader_dependencies), resources),
        [],
    )
end

struct DescriptorInfo
    type::DescriptorType
    "1-based index into a descriptor set."
    index::Int
    binding::Int
end

struct Descriptor
    set::DescriptorSet
    info::DescriptorInfo
end
