abstract type PassType end

struct OpaqueShadingPass <: PassType end
struct LightingPass <: PassType end
struct TransparentShadingPass <: PassType end

function Vk.PipelineColorBlendStateCreateInfo(pass::PassType)
    Vk.PipelineColorBlendStateCreateInfo(
        false,
        Vk.LOGIC_OP_AND,
        [Vk.PipelineColorBlendAttachmentState(pass)],
    )
end

function Vk.PipelineColorBlendAttachmentState(pass::OpaqueShadingPass)
    Vk.PipelineColorBlendAttachmentState(
        false,
        Vk.BLEND_FACTOR_ONE,
        Vk.BLEND_FACTOR_ZERO,
        Vk.BLEND_OP_ADD,
        Vk.BLEND_FACTOR_ONE,
        Vk.BLEND_FACTOR_ZERO,
        Vk.BLEND_OP_ADD;
        color_write_mask = Vk.COLOR_COMPONENT_R_BIT | Vk.COLOR_COMPONENT_G_BIT | Vk.COLOR_COMPONENT_B_BIT
    )
end

function Vk.PipelineColorBlendAttachmentState(pass::TransparentShadingPass)
    Vk.PipelineColorBlendAttachmentState(
        true,
        Vk.BLEND_FACTOR_SRC_ALPHA,
        Vk.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        Vk.BLEND_OP_ADD,
        Vk.BLEND_FACTOR_SRC_ALPHA,
        Vk.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        Vk.BLEND_OP_ADD;
        color_write_mask = Vk.COLOR_COMPONENT_R_BIT | Vk.COLOR_COMPONENT_G_BIT | Vk.COLOR_COMPONENT_B_BIT | Vk.COLOR_COMPONENT_A_BIT
    )
end
