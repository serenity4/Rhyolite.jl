using Vulkan
using Dictionaries
using Rhyolite
using Test

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
            Rhyolite.find_shader!(ShaderCache(device), spec) # trigger JIT compilation
            t = @elapsed Rhyolite.find_shader!(cache, spec)
            @test t > 0.01
            t = @elapsed Rhyolite.find_shader!(cache, spec)
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

        @testset "Rendering" begin
            @testset "Headless rendering" begin
                include("headless.jl")
            end
        end
    end
end
