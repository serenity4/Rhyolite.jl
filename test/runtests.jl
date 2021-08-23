using Vulkan
using Dictionaries
using Rhyolite
using Test
using Accessors

resource(filename) = joinpath(@__DIR__, "resources", filename)

@testset "Rhyolite.jl" begin
    @testset "Initialization" begin
        config = dictionary([QUEUE_GRAPHICS_BIT | QUEUE_COMPUTE_BIT => 1])
        instance, device = init(; queue_config = config, device_extensions = ["VK_KHR_synchronization2"])
        disp = QueueDispatch(device, config)
        pools = ThreadedCommandPool(device, disp, dictionary(1:4 .=> collect(keys(config))))
        ev = Event(device)
        buffer = first(unwrap(allocate_command_buffers(device, CommandBufferAllocateInfo(CommandPool(pools), COMMAND_BUFFER_LEVEL_PRIMARY, 1))))
        @record buffer begin
            cmd_set_event(ev, PIPELINE_STAGE_TOP_OF_PIPE_BIT)
        end
        queue = submit(disp, QUEUE_GRAPHICS_BIT, [SubmitInfo2KHR([], [CommandBufferSubmitInfoKHR(buffer, 0)], [])])
        @test unwrap(queue_wait_idle(queue)) == SUCCESS
    end

    @testset "Shaders" begin
        instance, device = init(; device_extensions = ["VK_KHR_synchronization2"])
        frag_shader = resource("decorations.frag")

        @testset "Shader cache" begin
            spec = ShaderSpecification(frag_shader, GLSL)
            cache = ShaderCache(device)
            find_shader!(ShaderCache(device), spec) # trigger JIT compilation
            t = @elapsed find_shader!(cache, spec)
            @test t > 0.01
            t = @elapsed find_shader!(cache, spec)
            @test t < 1e-5
        end

        @testset "Descriptors" begin
            da = DescriptorAllocator(device)
            spec = ShaderSpecification(frag_shader, GLSL)
            cache = ShaderCache(device)
            shader = Rhyolite.find_shader!(cache, spec)
            layouts = create_descriptor_set_layouts(device, [shader])
            sets = allocate_descriptor_sets!(da, layouts)
            @test length(da.pools) == 1
            pool_state = first(da.pools)
            @test pool_state.allocated == dictionary([DESCRIPTOR_TYPE_STORAGE_IMAGE => 1])

            # check resources are reused by the descriptor allocator
            sets2 = allocate_descriptor_sets!(da, layouts)
            @test pool_state.allocated == dictionary([DESCRIPTOR_TYPE_STORAGE_IMAGE => 2])

            # check that new sets were allocated
            @test handle.(sets) ≠ handle.(sets2)

            # check resources get cleaned up
            free_descriptor_sets!(da, [sets; sets2])

            @test pool_state.allocated == dictionary([DESCRIPTOR_TYPE_STORAGE_IMAGE => 0])
        end
    end

    @testset "Pipelines" begin
        instance, device = init(; device_extensions = ["VK_KHR_synchronization2"])
        vert_shader_file = resource("headless.vert")
        frag_shader_file = resource("headless.frag")

        format = FORMAT_R32G32B32A32_SFLOAT

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

        @testset "Graphics pipeline cache" begin
            shader_cache = ShaderCache(device)
            shaders = map([vert_shader_file, frag_shader_file]) do file
                find_shader!(shader_cache, ShaderSpecification(file, GLSL))
            end
            shader_stages = PipelineShaderStageCreateInfo.(shaders)
            width = height = 1000
            vertex_input_state = PipelineVertexInputStateCreateInfo(
                [VertexInputBindingDescription(0, 20, VERTEX_INPUT_RATE_VERTEX)],
                [
                    VertexInputAttributeDescription(0, 0, FORMAT_R32G32_SFLOAT, 0),
                    VertexInputAttributeDescription(1, 0, FORMAT_R32G32B32_SFLOAT, 8),
                ],
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
            pipeline_info = GraphicsPipelineCreateInfo(
                shader_stages,
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
            )
            pipeline_infos = map(1:1000) do i
                @set pipeline_info.color_blend_state = PipelineColorBlendStateCreateInfo(
                    false,
                    LOGIC_OP_CLEAR,
                    [color_blend_attachment],
                    Float32.((0.0, 0.0, 0.0, i/1000)),
                )
            end
            cache = GraphicsPipelineCache(device)

            # trigger JIT compilation
            get_graphics_pipelines!(GraphicsPipelineCache(device), pipeline_infos)
            create_graphics_pipelines(device, pipeline_infos)

            t = @elapsed create_graphics_pipelines(device, pipeline_infos)
            t1 = @elapsed get_graphics_pipelines!(cache, pipeline_infos)
            t2 = @elapsed get_graphics_pipelines!(cache, pipeline_infos)
            # test pipeline creation time is not inflated
            @test t1/t < 10
            # test caching speedup
            @test t/t2 > 5
        end
    end

    @testset "Rendering" begin
        @testset "Headless rendering" begin
            include("headless.jl")
        end
    end
end
