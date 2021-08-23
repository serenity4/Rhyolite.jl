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
        include("shaders.jl")
    end

    @testset "Pipelines" begin
        include("pipelines.jl")
    end

    @testset "Rendering" begin
        @testset "Headless rendering" begin
            include("headless.jl")
        end
    end
end
