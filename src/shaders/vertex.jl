Vulkan.VertexInputAttributeDescription(::Type{T}, binding) where {T} =
    VertexInputAttributeDescription.(
        0:fieldcount(T)-1,
        binding,
        Format.(fieldtypes(T)),
        fieldoffset.(T, 1:fieldcount(T)),
    )

Vulkan.VertexInputBindingDescription(::Type{T}, binding; input_rate = VERTEX_INPUT_RATE_VERTEX) where {T} =
    VertexInputBindingDescription(binding, sizeof(T), input_rate)
