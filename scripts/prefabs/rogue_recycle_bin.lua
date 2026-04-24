local assets = {
}

local function onopen(inst)
end

local function onclose(inst)
    -- 当容器关闭时，将所有未回收的物品退还给玩家
    if inst.components.container then
        local owner = inst.components.inventoryitem and inst.components.inventoryitem.owner or inst.entity:GetParent()
        
        for k, v in pairs(inst.components.container.slots) do
            local item = inst.components.container:RemoveItemBySlot(k)
            if item then
                if owner and owner.components.inventory then
                    owner.components.inventory:GiveItem(item, nil, owner:GetPosition())
                else
                    item.Transform:SetPosition(inst.Transform:GetWorldPosition())
                end
            end
        end
    end
end

local function onremove(inst)
    if inst.components.container then
        inst.components.container:DropEverything()
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddNetwork()

    inst:AddTag("rogue_recycle_bin")
    inst:AddTag("CLASSIFIED")
    inst:AddTag("NOBLOCK")

    -- 这是一个虚拟容器，不需要物理碰撞和动画，只需网络同步组件
    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("container")
    inst.components.container:WidgetSetup("rogue_recycle_bin")
    inst.components.container.onopenfn = onopen
    inst.components.container.onclosefn = onclose

    inst:ListenForEvent("onremove", onremove)

    inst.persists = false

    return inst
end

return Prefab("rogue_recycle_bin", fn, assets)
