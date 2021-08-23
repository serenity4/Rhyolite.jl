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
