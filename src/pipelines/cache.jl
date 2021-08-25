"""
Cache for graphics pipelines.

!!! warning
    This cache is not thread-safe.
"""
struct GraphicsPipelineCache
    device::Device
    pipelines::Dictionary{GraphicsPipelineCreateInfo,Pipeline}
end

GraphicsPipelineCache(device) = GraphicsPipelineCache(device, Dictionary{GraphicsPipelineCreateInfo,Pipeline}())

"""
Retrieve or create graphics pipelines, depending on whether they were already cached.
Note that because of caching, you shouldn't expect duplicate pipelines if you provide `GraphicsPipelineCreateInfo`.
If duplicates are present, the behavior differs from `Vulkan.create_graphics_pipelines` in that
they will all be associated with the same pipeline.
"""
function Base.get!(cache::GraphicsPipelineCache, create_infos::AbstractVector{GraphicsPipelineCreateInfo}; allocator = C_NULL, pipeline_cache = C_NULL)
    info_uncached = filter(Base.Fix1(!haskey, cache.pipelines), create_infos)
    if !isempty(info_uncached)
        (pipelines, _) = unwrap(create_graphics_pipelines(cache.device, info_uncached; allocator, pipeline_cache))
        foreach(zip(info_uncached, pipelines)) do (info, pipeline)
            insert!(cache.pipelines, info, pipeline)
        end
    end
    map(Base.Fix1(getindex, cache.pipelines), create_infos)
end
