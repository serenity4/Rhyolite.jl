function find_memory_type(physical_device, type_flag, properties::MemoryPropertyFlag)
    mem_props = get_physical_device_memory_properties(physical_device)
    indices = findall(x -> properties in x.property_flags, mem_props.memory_types[1:mem_props.memory_type_count]) .- 1
    if isempty(indices)
        error("Could not find memory with properties $properties")
    else
        ind = findfirst(i -> type_flag & (1 << i) ≠ 0, indices)
        if isnothing(ind)
            error("Could not find memory with type $type_flag")
        else
            indices[ind], mem_props[indices[ind]]
        end
    end
end

"""
Memory domains:
- `MEMORY_DOMAIN_HOST` is host-visible memory, ideal for uploads to the GPU. It is preferably coherent and non-cached.
- `MEMORY_DOMAIN_HOST_CACHED` is host-visible, cached memory, ideal for readbacks from the GPU. It is preferably coherent.
- `MEMORY_DOMAIN_DEVICE` is device-local. It may be visible (integrated GPUs).
"""
@enum MemoryDomain::Int8 begin
    MEMORY_DOMAIN_HOST
    MEMORY_DOMAIN_HOST_CACHED
    MEMORY_DOMAIN_DEVICE
end

function score(domain::MemoryDomain, properties)
    @match domain begin
        &MEMORY_DOMAIN_HOST => 10 * MEMORY_PROPERTY_HOST_VISIBLE_BIT in properties + MEMORY_PROPERTY_HOST_COHERENT_BIT in properties - MEMORY_PROPERTY_HOST_CACHED_BIT in propetries
        &MEMORY_DOMAIN_HOST_CACHED => 10 * MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_CACHED_BIT in properties + MEMORY_PROPERTY_HOST_COHERENT_BIT in properties
        &MEMORY_DOMAIN_DEVICE => MEMORY_PROPERTY_DEVICE_LOCAL_BIT in properties
    end
end

function find_memory_type(f, physical_device, type_flag)
    mem_props = get_physical_device_memory_properties(physical_device)
    memtypes = mem_props.memory_types[1:mem_props.memory_type_count]
    candidate_indices = findall(i -> type_flag & (1 << i) ≠ 0, 0:length(memtypes) - 1)
    index, mem_prop = findmax(i -> f(memtypes[i + 1].property_flags), candidate_indices)
    index, mem_prop
end

find_memory_type(physical_device, type_flag, domain::MemoryDomain) = find_memory_type(Base.Fix1(score, domain), physical_device, type_flag)

mutable struct LinearAllocator
    memory::DeviceMemory
    size::Int
    properties::MemoryPropertyFlag
    last_offset::Int
end

device(allocator::LinearAllocator) = allocator.memory.device

function LinearAllocator(device::Device, size, properties)
    memory = DeviceMemory(device, size, properties)
    la = LinearAllocator(memory, size, properties, 0)
    map_memory(la)
    finalizer(unmap_memory, la)
end

function Vulkan.bind_buffer_memory(buffer, allocator::LinearAllocator, size, alignment)::ResultTypes.Result{Result,VulkanError}
    offset = alignment * cld(allocator.last_offset, alignment)
    ret = bind_buffer_memory(device(allocator), buffer, allocator.memory, offset)
    if !iserror(ret)
        allocator.last_offset = offset + size
    end
    ret
end

function Vulkan.map_memory(allocator::LinearAllocator, offset::Integer, size::Integer)
    if MEMORY_PROPERTY_HOST_COHERENT_BIT ∉ allocator.properties
        invalidate_mapped_memory_ranges(device(allocator), [MappedMemoryRange(allocator.memory, offset, size)])
    end
    map_memory(device(allocator), allocator.memory, offset, size)
end

function Vulkan.unmap_memory(allocator::LinearAllocator)
    if MEMORY_PROPERTY_HOST_COHERENT_BIT ∉ allocator.properties
        flush_mapped_memory_ranges(device(allocator), [MappedMemoryRange(allocator.memory, 0, allocator.size)])
    end
    unmap_memory(device(allocator), allocator.memory)
end

function reset!(allocator::LinearAllocator)
    allocator.last_offset = 0
end

buffer_size(data::DenseVector{T}) where {T} = sizeof(T) * length(data)
buffer_size(data) = sizeof(data)

# struct MemoryManager
#     allocators::Dictionary{MemoryDomain,}
# end

function Vulkan.DeviceMemory(device, memory_requirements::MemoryRequirements, properties)
    i, _ = find_memory_type(device.physical_device, memory_requirements.memory_type_bits, properties)
    DeviceMemory(device, memory_requirements.size, i)
end

"""
Upload data to the specified memory.

!!! warning
    The `memory` must be host coherent and host visible, otherwise the operation will fail.
"""
function upload_data(memory::DeviceMemory, data::DenseArray{T}; offset=0) where {T}
    memptr = unwrap(map_memory(memory.device, memory, offset, buffer_size(data)))
    GC.@preserve data unsafe_copyto!(Ptr{T}(memptr), pointer(data), length(data))
    unwrap(unmap_memory(memory.device, memory))
end

upload_data(resource::Allocated, data; offset=0) = upload_data(memory(resource), data; offset)

"""
Download data from the specified memory to an `Array`.

If `copy` if set to true, then all the data mapped from `memory` will be copied. If not, care should be taken to preserve the `memory` mapped and valid as long as the returned data is in use.
"""
function download_data(::Type{<:DenseArray{T}}, memory::DeviceMemory, dims; offset = 0, copy = true, unmap = true) where {T}
    size = sizeof(T) * prod(dims)
    memptr = unwrap(map_memory(memory.device, memory, offset, size))
    data = unsafe_wrap(Array, convert(Ptr{T}, memptr), dims; own = false)
    if unmap
        unwrap(unmap_memory(memory.device, memory))
    end
    if copy
        deepcopy(data)
    else
        data
    end
end

"""
Allocate a `DeviceMemory` object with the specified properties and bind it to the `buffer` using memory requirements from `get_buffer_memory_requirements`.
"""
function Vulkan.DeviceMemory(buffer::Buffer, properties::MemoryPropertyFlag) where {T}
    device = buffer.device
    memreqs = get_buffer_memory_requirements(device, buffer)
    memory = DeviceMemory(device, memreqs, properties)
    unwrap(bind_buffer_memory(device, buffer, memory, 0))
    memory
end

"""
Allocate a host visible and coherent `DeviceMemory` object, bind it to the `buffer` using memory requirements from `get_buffer_memory_requirements` and upload `data` to it.
"""
function Vulkan.DeviceMemory(buffer::Buffer, data::DenseArray{T}) where {T}
    memory = DeviceMemory(buffer, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)
    upload_data(memory, data)
    memory
end

"""
Allocate a `DeviceMemory` object and bind it to the `image` using memory requirements from `get_image_memory_requirements`.
"""
function Vulkan.DeviceMemory(image::Image, properties::MemoryPropertyFlag)
    memreqs = get_image_memory_requirements(image.device, image)
    memory = DeviceMemory(image.device, memreqs, properties)
    unwrap(bind_image_memory(image.device, image, memory, 0))
    memory
end
