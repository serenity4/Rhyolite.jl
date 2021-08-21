struct QueueDispatch
    queues::Dictionary{QueueFlag,Vector{Created{Queue,DeviceQueueInfo2}}}
    present_queue::Optional{Created{Queue,DeviceQueueInfo2}}
    """
    Build a `QueueDispatch` structure from a given device and configuration.

    !!! warning
        `device` must have been created with a consistent number of queues as requested in the provided queue configuration.
        It is highly recommended to have created the device with the result of `queue_infos(QueueDispatch, physical_device, config)`.
    """
    function QueueDispatch(device, config; surface = nothing)
        physical_device = handle(device).physical_device
        families = find_queue_family.(physical_device, collect(keys(config)))
        queues = dictionary(map(zip(keys(config), families)) do (property, family)
            property => map(0:config[property] - 1) do count
                info = DeviceQueueInfo2.(family, count)
                Created(get_device_queue_2(device, info), info)
            end
        end)
        present_queue = if !isnothing(surface)
            idx = findfirst(families) do family
                unwrap(get_physical_device_surface_support_khr(physical_device, family, surface))
            end
            if isnothing(idx)
                error("Could not find a queue that supports presentation on the provided surface.")
            else
                first(collect(queues)[idx])
            end
        else
            nothing
        end
        new(queues, present_queue)
    end
end

function queue_infos(::Type{QueueDispatch}, physical_device::PhysicalDevice, config)
    all(==(1), config) || error("Only one queue per property is currently supported")
    families = find_queue_family.(physical_device, collect(keys(config)))
    DeviceQueueCreateInfo.(families, ones.(collect(config)))
end

function submit(dispatch::QueueDispatch, properties::QueueFlag, submit_infos; fence = C_NULL)
    q = queue(dispatch, properties)
    unwrap(queue_submit_2_khr(q, submit_infos; fence))
    q
end

function queue(dispatch::QueueDispatch, properties::QueueFlag)
    if properties in keys(dispatch.queues)
        first(dispatch.queues[properties])
    else
        for props in keys(dispatch.queues)
            if properties in props
                return first(dispatch.queues[props])
            end
        end
        error("Could not find a queue matching with the required properties $properties.")
    end
end

function present(dispatch::QueueDispatch, present_info::PresentInfoKHR)
    queue = dispatch.present_queue
    if isnothing(queue)
        error("No presentation queue was specified for $dispatch")
    else
        queue_present_khr(queue, present_info)
    end
end

function queue_family_indices(dispatch::QueueDispatch; include_present = true)
    indices = map(dispatch.queues) do queues
        map(queues) do queue
            info(queue).queue_family_index
        end
    end
    indices = reduce(vcat, indices)
    if include_present && !isnothing(dispatch.present_queue)
        push!(indices, info(dispatch.present_queue).queue_family_index)
    end
    sort!(unique!(indices))
end
