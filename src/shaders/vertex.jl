function vertex_input_attribute_descriptions(::Type{T}, binding, formats=Format.(fieldtypes(T))) where {T}
    VertexInputAttributeDescription.(
        0:fieldcount(T)-1,
        binding,
        formats,
        fieldoffset.(T, 1:fieldcount(T)),
    )
end

Vulkan.VertexInputBindingDescription(::Type{T}, binding; input_rate = VERTEX_INPUT_RATE_VERTEX) where {T} =
    VertexInputBindingDescription(binding, sizeof(T), input_rate)
