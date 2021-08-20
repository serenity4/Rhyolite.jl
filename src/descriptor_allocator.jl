struct DescriptorPoolState
    allocated::Dictionary{DescriptorType,Int}
    limits::Dictionary{DescriptorType,Int}
    max::Int
end

struct PoolAllocations
    set::DescriptorSet
    pool::DescriptorPool
    allocated::Dictionary{DescriptorType,Int}
end

"""
Entity which manages descriptor pools and descriptor sets.
"""
struct DescriptorAllocator
    device::Device
    pools::Dictionary{DescriptorPool,DescriptorPoolState}
    allocations::Dictionary{DescriptorSet,PoolAllocations}
end

Base.broadcastable(da::DescriptorAllocator) = Ref(da)

DescriptorAllocator(device) = DescriptorAllocator(device, Dictionary{DescriptorPool,DescriptorPoolState}(), Dictionary{DescriptorSet,PoolAllocations}())

function new_pool!(da::DescriptorAllocator, allocations::Dictionary{DescriptorType,Int}; next = C_NULL, flags = DescriptorPoolCreateFlag(0))
    limits = [DescriptorPoolSize(t, max(allocations[t], 20)) for t in keys(allocations)]
    maxsize = max(sum(allocations), 50)
    create_info = DescriptorPoolCreateInfo(maxsize, limits; next, flags = flags | DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT)
    new = Created(unwrap(create_descriptor_pool(da.device, create_info)), create_info)
    limits_dict = Dictionary(getproperty.(limits, :type), Int.(getproperty.(limits, :descriptor_count)))
    insert!(da.pools, handle(new), DescriptorPoolState(Dictionary{DescriptorType,Int64}(), limits_dict, maxsize))
    new
end

function compute_allocations(da::DescriptorAllocator, layouts::AbstractVector{DescriptorSetLayoutCreateInfo})
    allocations = Dictionary{DescriptorType,Int}()
    for layout in layouts
        for binding in layout.bindings
            set!(allocations, binding.descriptor_type, get(allocations, binding.descriptor_type, 0) + binding.descriptor_count)
        end
    end
    allocations
end

function compute_allocations(da::DescriptorAllocator, layout::DescriptorSetLayoutCreateInfo)
    dictionary(map(layout.bindings) do binding
        binding.descriptor_type => Int(binding.descriptor_count)
    end)
end

function compute_allocations(da::DescriptorAllocator, layouts::AbstractVector{Created{DescriptorSetLayout, DescriptorSetLayoutCreateInfo}})
    compute_allocations(da, info.(layouts))
end

function compute_allocations(da::DescriptorAllocator, layouts::AbstractVector{DescriptorSetLayout})
    compute_allocations(da, [da.layouts[layout] for layout in layouts])
end

function find_pool!(da::DescriptorAllocator, layouts)
    find_pool!(da, compute_allocations(da, layouts))
end

function find_pool!(da::DescriptorAllocator, allocations::Dictionary{DescriptorType,Int})
    for (pool, state) in zip(keys(da.pools), da.pools)
        n = 0
        has_room = sum(allocations) < sum(state.max) && all(keys(state.allocated)) do t
            state.allocated[t] + allocations[t] < state.limits[t]
        end
        if has_room
            return pool
        end
    end

    # no pool could be reused
    new_pool!(da, allocations)
end

function allocate_descriptor_sets!(da::DescriptorAllocator, layouts::Vector{Created{DescriptorSetLayout,DescriptorSetLayoutCreateInfo}}; next=C_NULL)
    pool = find_pool!(da, layouts)
    allocations = compute_allocations(da, info.(layouts))

    for (type, count) in pairs(allocations)
        allocated = da.pools[pool].allocated
        set!(allocated, type, get(allocated, type, 0) + count)
    end

    allocate_info = DescriptorSetAllocateInfo(next, pool, layouts)
    sets = unwrap(allocate_descriptor_sets(da.device, allocate_info))

    # record allocations for ulterior deletion
    foreach(zip(layouts, sets)) do (layout, set)
        insert!(da.allocations, set, PoolAllocations(set, pool, compute_allocations(da, info(layout))))
    end

    Created.(sets, allocate_info)
end

"""
Free descriptor sets from a descriptor allocator.

!!! warning
    All descriptor sets must have been allocated with the same pool, through the same descriptor allocator.
    They may, however, have been allocated in several times.
"""
function free_descriptor_sets!(da::DescriptorAllocator, sets)
    pool_allocs = Dictionary{DescriptorPool,Vector{PoolAllocations}}()
    foreach(handle.(sets)) do set
        set_allocs = da.allocations[set]
        push!(get!(pool_allocs, set_allocs.pool, PoolAllocations[]), set_allocs)
    end
    foreach(pairs(pool_allocs)) do (pool, allocs)
        foreach(allocs) do alloc
            for (type, count) in pairs(alloc.allocated)
                da.pools[pool].allocated[type] -= count
            end
        end
        free_descriptor_sets(da.device, pool, getproperty.(allocs, :set))
    end
    nothing
end
