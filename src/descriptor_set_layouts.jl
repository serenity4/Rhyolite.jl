struct DescriptorSetLayoutCache
    device::Device
    dset_layouts::Dictionary{DescriptorSetLayoutCreateInfo,DescriptorSetLayout}
end

device(cache::DescriptorSetLayoutCache) = cache.device

DescriptorSetLayoutCache(device) = DescriptorSetLayoutCache(device, Dictionary{DescriptorSetLayoutCreateInfo,DescriptorSetLayout}())

@forward DescriptorSetLayoutCache.dset_layouts Base.haskey, Base.getindex, Base.insert!

function Base.get!(cache::DescriptorSetLayoutCache, info::DescriptorSetLayoutCreateInfo)
    if haskey(cache, info)
        cache[info]
    else
        dset_layout = unwrap(create_descriptor_set_layout(device(cache), info))
        insert!(cache, info, dset_layout)
        dset_layout
    end
end

function allocate_descriptor_sets!(da::DescriptorAllocator, cache::DescriptorSetLayoutCache, shaders)
    allocate_descriptor_sets!(da, create_descriptor_set_layouts!(cache, shaders))
end

function create_descriptor_set_layouts!(cache::DescriptorSetLayoutCache, shaders)
    map(collect_bindings(shaders)) do layout_binding
        info = DescriptorSetLayoutCreateInfo(layout_binding)
        Created(get!(cache, info), info)
    end
end

function create_descriptor_set_layouts(device, shaders)
    map(collect_bindings(shaders)) do layout_binding
        info = DescriptorSetLayoutCreateInfo(layout_binding)
        Created(unwrap(create_descriptor_set_layout(device, info)), info)
    end
end

function collect_bindings(shaders)
    binding_sets = Dictionary{Int,Vector{DescriptorSetLayoutBinding}}()
    for shader ∈ shaders
        for info ∈ shader.descriptor_infos
            push!(get!(binding_sets, info.index, DescriptorSetLayoutBinding[]), DescriptorSetLayoutBinding(info.binding, info.type, shader.source.stage; descriptor_count=1))
        end
    end
    if !all(collect(keys(binding_sets)) .== 0:length(binding_sets) - 1)
        error("Invalid layout description (non-contiguous binding sets from 0) in $binding_sets.")
    end
    collect(values(binding_sets))
end
