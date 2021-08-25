struct RenderInfo
    shader_dependencies::ShaderDependencies
    pipeline::Ref{Created{Pipeline,GraphicsPipelineCreateInfo}}
    draw_args::NTuple{4,Int}
    push_data::Any
end

struct RenderSet
    pipeline_cache::GraphicsPipelineCache
    render_infos::Dictionary{Any,RenderInfo}
end

RenderSet(device) = RenderSet(GraphicsPipelineCache(device))
RenderSet(cache::GraphicsPipelineCache) = RenderSet(cache, Dictionary{Any,RenderInfo}())

function prepare!(f, set::RenderSet)
    batch = Dictionary{GraphicsPipelineCreateInfo,Ref{Pipeline}}()
    for (object, info) in pairs(set.render_infos)
        prepare_pipeline!(f, batch, set, object, info)
        prepare_resources!(set, object, info)
    end
    if !isempty(batch)
        pipelines = get_graphics_pipelines!(set.pipeline_cache, collect(keys(batch)))
        for ((info, ref), pipeline) in zip(pairs(batch), pipelines)
            ref[] = Created(pipeline, info)
        end
    end
end

function prepare_pipeline!(f, batch, set::RenderSet, object, info)
    if !isdefined(info.pipeline, 1)
        insert!(batch, info.pipeline, f(set.pipeline_cache.device, object))
    end
end

function BindRequirements(info::RenderInfo)
    pipeline_info = render_info.pipeline.info
    push_ranges = pipeline_info.push_constant_ranges == C_NULL ? nothing : pipeline_info.push_constant_ranges
    BindRequirements(info.shader_dependencies, PipelineBindingState(pipeline, push_ranges), pipeline_info.pipeline_layout, info.push_data)
end
