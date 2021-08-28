abstract type PassType end

struct OpaqueShadingPass <: PassType end
struct LightingPass <: PassType end
struct TransparentShadingPass <: PassType end

function Vulkan.PipelineColorBlendStateCreateInfo(pass::PassType)
    PipelineColorBlendStateCreateInfo(
        false,
        LOGIC_OP_AND,
        [PipelineColorBlendAttachmentState(pass)],
    )
end

function Vulkan.PipelineColorBlendAttachmentState(pass::OpaqueShadingPass)
    PipelineColorBlendAttachmentState(
        false,
        BLEND_FACTOR_ONE,
        BLEND_FACTOR_ZERO,
        BLEND_OP_ADD,
        BLEND_FACTOR_ONE,
        BLEND_FACTOR_ZERO,
        BLEND_OP_ADD;
        color_write_mask = COLOR_COMPONENT_R_BIT | COLOR_COMPONENT_G_BIT | COLOR_COMPONENT_B_BIT
    )
end

function Vulkan.PipelineColorBlendAttachmentState(pass::TransparentShadingPass)
    PipelineColorBlendAttachmentState(
        true,
        BLEND_FACTOR_SRC_ALPHA,
        BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        BLEND_OP_ADD,
        BLEND_FACTOR_SRC_ALPHA,
        BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        BLEND_OP_ADD;
        color_write_mask = COLOR_COMPONENT_R_BIT | COLOR_COMPONENT_G_BIT | COLOR_COMPONENT_B_BIT | COLOR_COMPONENT_A_BIT
    )
end
