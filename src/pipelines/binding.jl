"""
Binding state that must be set in order for
drawing commands to render correctly.
"""
struct BindRequirements
    dependencies::ShaderDependencies
    push_data::Any
    pipeline::Created{Pipeline,GraphicsPipelineCreateInfo}
end

"""
Describes the current binding state.
"""
struct BindState
    vertex_buffer::Optional{VertexBuffer}
    index_buffer::Optional{IndexBuffer}
    descriptor_sets::Vector{Created{DescriptorSet,DescriptorSetAllocateInfo}}
    push_data::Any
    pipeline::Optional{Created{Pipeline,GraphicsPipelineCreateInfo}}
end

function Base.bind(cbuffer::CommandBuffer, reqs::BindRequirements, state::BindState)
    @unpack vertex_buffer, index_buffer, descriptor_sets = reqs.dependencies
    @unpack push_data, pipeline = reqs

    pipeline ≠ state.pipeline && cmd_bind_pipeline(cbuffer, PIPELINE_BIND_POINT_GRAPHICS, pipeline)
    vertex_buffer ≠ state.vertex_buffer && cmd_bind_vertex_buffers(cbuffer, [vertex_buffer], [0])

    if !isnothing(index_buffer) && index_buffer ≠ state.index_buffer
        cmd_bind_index_buffer(cbuffer, index_buffer, 0, INDEX_TYPE_UINT32)
    end

    if !isempty(descriptor_sets) && descriptor_sets ≠ state.descriptor_sets
        cmd_bind_descriptor_sets(cbuffer, PIPELINE_BIND_POINT_GRAPHICS, pipeline.info.layout, 0, handle.(descriptor_sets), [])
    end

    if !isnothing(push_data) && push_data ≠ state.push_data
        cmd_push_constants(cbuffer, pipeline.info.layout, SHADER_STAGE_VERTEX_BIT, 1, Ref(push_data), sizeof(push_data))
    end

    BindState(vertex_buffer, index_buffer, descriptor_sets, push_data, pipeline)
end
