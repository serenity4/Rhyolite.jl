using Vulkan
using Rhyolite
using ColorTypes
using FileIO
using Dictionaries
using Accessors
using Test

resource(filename) = joinpath(@__DIR__, "resources", filename)
render(filename) = joinpath(@__DIR__, "renders", filename)

function render_headless(output_png, points, colors; width = 1000, height = 1000)
    instance, device = init(; instance_extensions = ["VK_KHR_surface"], device_extensions = ["VK_KHR_synchronization2", "VK_KHR_swapchain"])
    config = dictionary([QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT => 1])
    disp = QueueDispatch(device, config)
    pools = ThreadedCommandPool(device, disp, dictionary(1:1 .=> collect(keys(config))))
    shader_cache = ShaderCache(device)
    vert_shader = find_shader!(shader_cache, ShaderSpecification(resource("headless.vert"), GLSL))
    frag_shader = find_shader!(shader_cache, ShaderSpecification(resource("headless.frag"), GLSL))

    # compared to a display-based rendering, we have a lot more freedom over the format that we use.
    format = FORMAT_R32G32B32A32_SFLOAT
    format_props = get_physical_device_format_properties(handle(device).physical_device, format)

    if !(FORMAT_FEATURE_TRANSFER_SRC_BIT | FORMAT_FEATURE_TRANSFER_DST_BIT | FORMAT_FEATURE_COLOR_ATTACHMENT_BIT in format_props.optimal_tiling_features)
        error("Physical device $(get_physical_device_properties(handle(device).physical_device)) not supported")
    end

    target_attachment = AttachmentDescription(
        format,
        SAMPLE_COUNT_1_BIT,
        ATTACHMENT_LOAD_OP_CLEAR,
        ATTACHMENT_STORE_OP_STORE,
        ATTACHMENT_LOAD_OP_DONT_CARE,
        ATTACHMENT_STORE_OP_DONT_CARE,
        IMAGE_LAYOUT_UNDEFINED,
        IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    )

    render_pass = RenderPass(
        device,
        [target_attachment],
        [
            SubpassDescription(
                PIPELINE_BIND_POINT_GRAPHICS,
                [],
                [AttachmentReference(0, IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)],
                [],
            ),
        ],
        [
            SubpassDependency(
                SUBPASS_EXTERNAL,
                0;
                src_stage_mask = PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dst_stage_mask = PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dst_access_mask = ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            ),
        ],
    )

    # create image and framebuffer
    fb_image_info = ImageCreateInfo(
        IMAGE_TYPE_2D,
        format,
        Extent3D(width, height, 1),
        1,
        1,
        SAMPLE_COUNT_1_BIT,
        IMAGE_TILING_OPTIMAL,
        IMAGE_USAGE_COLOR_ATTACHMENT_BIT | IMAGE_USAGE_TRANSFER_SRC_BIT,
        SHARING_MODE_EXCLUSIVE,
        queue_family_indices(disp),
        IMAGE_LAYOUT_UNDEFINED,
    )
    fb_image = unwrap(create_image(device, fb_image_info))

    # some GPUs don't offer host-coherent host-visible memory for color attachments
    fb_image_memory = DeviceMemory(fb_image, MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    fb_image_view = ImageView(
        device,
        fb_image,
        IMAGE_VIEW_TYPE_2D,
        format,
        ComponentMapping(fill(COMPONENT_SWIZZLE_IDENTITY, 4)...),
        ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
    )
    framebuffer = Framebuffer(device, render_pass, [fb_image_view], width, height, 1)

    # prepare vertex buffer
    vdata = collect(zip(points, colors))
    vbuffer = Buffer(device, buffer_size(vdata), BUFFER_USAGE_VERTEX_BUFFER_BIT, SHARING_MODE_EXCLUSIVE, queue_family_indices(disp))
    vmemory = DeviceMemory(vbuffer, vdata)

    # build graphics pipeline
    shader_stage_cis = PipelineShaderStageCreateInfo.([vert_shader, frag_shader])
    vertex_input_state = PipelineVertexInputStateCreateInfo(
        [VertexInputBindingDescription(eltype(vdata), 0)],
        vertex_input_attribute_descriptions(eltype(vdata), 0, [FORMAT_R32G32_SFLOAT, FORMAT_R32G32B32_SFLOAT]),
    )
    input_assembly_state = PipelineInputAssemblyStateCreateInfo(PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false)
    viewport_state = PipelineViewportStateCreateInfo(
        viewports = [Viewport(0, 0, width, height, 0, 1)],
        scissors = [Rect2D(Offset2D(0, 0), Extent2D(width, height))],
    )
    rasterizer = PipelineRasterizationStateCreateInfo(
        false,
        false,
        POLYGON_MODE_FILL,
        FRONT_FACE_CLOCKWISE,
        false,
        0.0,
        0.0,
        0.0,
        1.0,
        cull_mode = CULL_MODE_BACK_BIT,
    )
    multisample_state = PipelineMultisampleStateCreateInfo(SAMPLE_COUNT_1_BIT, false, 1.0, false, false)
    color_blend_attachment = PipelineColorBlendAttachmentState(
        true,
        BLEND_FACTOR_SRC_ALPHA,
        BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        BLEND_OP_ADD,
        BLEND_FACTOR_SRC_ALPHA,
        BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        BLEND_OP_ADD;
        color_write_mask = COLOR_COMPONENT_R_BIT | COLOR_COMPONENT_G_BIT | COLOR_COMPONENT_B_BIT,
    )
    color_blend_state = PipelineColorBlendStateCreateInfo(
        false,
        LOGIC_OP_CLEAR,
        [color_blend_attachment],
        Float32.((0.0, 0.0, 0.0, 0.0)),
    )
    pipeline_layout = PipelineLayout(device, [], [])
    (pipeline, _...), _ = unwrap(
        create_graphics_pipelines(
            device,
            [
                GraphicsPipelineCreateInfo(
                    shader_stage_cis,
                    rasterizer,
                    pipeline_layout,
                    render_pass,
                    0,
                    0;
                    vertex_input_state,
                    multisample_state,
                    color_blend_state,
                    input_assembly_state,
                    viewport_state,
                ),
            ],
        ),
    )

    dst_image_info = setproperties(fb_image_info, tiling = IMAGE_TILING_LINEAR, usage = IMAGE_USAGE_TRANSFER_DST_BIT)
    dst_image = unwrap(create_image(device, dst_image_info))
    dst_image_memory = DeviceMemory(dst_image, MEMORY_PROPERTY_HOST_COHERENT_BIT | MEMORY_PROPERTY_HOST_VISIBLE_BIT)

    # record commands
    command_buffer = first(unwrap(allocate_command_buffers(device, CommandBufferAllocateInfo(CommandPool(pools), COMMAND_BUFFER_LEVEL_PRIMARY, 1))))
    @record command_buffer begin
        cmd_bind_vertex_buffers([vbuffer], [0])
        cmd_bind_pipeline(PIPELINE_BIND_POINT_GRAPHICS, pipeline)
        cmd_pipeline_barrier(
            PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            PIPELINE_STAGE_TRANSFER_BIT,
            [],
            [],
            [
                ImageMemoryBarrier(
                    AccessFlag(0),
                    ACCESS_MEMORY_READ_BIT,
                    IMAGE_LAYOUT_UNDEFINED,
                    IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    QUEUE_FAMILY_IGNORED,
                    QUEUE_FAMILY_IGNORED,
                    dst_image,
                    ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
                ),
            ],
        )
        cmd_begin_render_pass(
            RenderPassBeginInfo(
                render_pass,
                framebuffer,
                Rect2D(Offset2D(0, 0), Extent2D(width, height)),
                [ClearValue(ClearColorValue((0.1f0, 0.1f0, 0.15f0, 1.0f0)))],
            ),
            SUBPASS_CONTENTS_INLINE,
        )
        cmd_draw(length(vdata), 1, 0, 0)
        cmd_end_render_pass()
        cmd_pipeline_barrier(
            PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            PIPELINE_STAGE_TRANSFER_BIT,
            [],
            [],
            [
                ImageMemoryBarrier(
                    ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                    ACCESS_MEMORY_READ_BIT,
                    IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                    IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                    QUEUE_FAMILY_IGNORED,
                    QUEUE_FAMILY_IGNORED,
                    fb_image,
                    ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
                ),
            ],
        )
        cmd_copy_image(
            fb_image,
            IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            dst_image,
            IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            [
                ImageCopy(
                    ImageSubresourceLayers(IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
                    Offset3D(0, 0, 0),
                    ImageSubresourceLayers(IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
                    Offset3D(0, 0, 0),
                    Extent3D(width, height, 1),
                ),
            ],
        )
    end

    # submit commands
    q = submit(disp, QUEUE_GRAPHICS_BIT, [SubmitInfo2KHR([], [CommandBufferSubmitInfoKHR(command_buffer, 0)], [])])
    GC.@preserve fb_image fb_image_view fb_image_memory framebuffer dst_image dst_image_memory vbuffer vmemory command_buffer pools begin
        unwrap(queue_wait_idle(q))
        data = download_data(Array{RGBA{Float32}}, dst_image_memory, (width, height))
    end

    save(output_png, data)
end

output_png = render("render_headless.png")

!ispath(output_png) || rm(output_png)

render_headless(output_png,
    NTuple{2,Float32}[
        (-1, -1),
        (1, -1),
        (-1, 1),
        (1, 1),
    ],
    RGB{Float32}[
        RGB(1,0,0),
        RGB(0,1,0),
        RGB(0,0,1),
        RGB(1,0,1),
    ]
)

@test stat(output_png).size > 200000
