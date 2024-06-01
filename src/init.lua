local HttpService = game:GetService("HttpService")

local __initdeps = {n = 0, closed = true}
local deps = __initdeps

type Primitive = string|boolean|number|Vector3|Instance|CFrame|UDim|UDim2|Vector2|ColorSequence|NumberSequence|Color3|BrickColor

export type State<T> = {
    value: T,
    Value: T,
    update: (self:State<T>)->(),
}

export type Derived<T> = {
    value: T,
    Value: T,
    update: (self:State<T>)->(),
    destroy: (self:Derived<T>)->()
}

export type T_Props = {
    [string|number]: Primitive|State<any>|(Instance)->()|Instance
}

local function captureDeps(fn)
    -- TODO: need to see if this captures inner states too
    -- e.g inside if statements
    local prevDeps = deps
    deps = table.clone(__initdeps)
    deps.closed = nil

    local value = fn()

    local capturedDeps = deps
    deps = prevDeps

    return capturedDeps, value
end

local function addToDeps(val)
    if not deps.closed then
        table.insert(deps, val)
    end
end

local function propKind(Inst:Instance, prop:string)
    local Ok, Res = pcall(function()
        return (Inst::any)[prop]
    end)

    if not Ok then
        return "None"
    elseif typeof(Res) == "RBXScriptSignal" then
        return "Event"
    else
        return "Prop"
    end
end

local function Watcher(object, fn:()->()): ()->()
    local index = HttpService:GenerateGUID()
    object._subscribed[index] = fn

    local destroyed = false
    return function()
        assert(not destroyed, "Watcher was already destroyed.")

        object._subscribed[index] = nil
        destroyed = true
    end
end

local function applyProps(Inst:Instance, Props:T_Props)
    local Hooks = {}
    for Key, Value in Props do
        local Kind = propKind(Inst, Key :: string)
        if Kind == "Prop" then
            if typeof(Value) == "table" and Value._type == "Reactive" then
                Watcher(Value, function()
                    Inst[Key] = Value.value
                end)
            else
                Inst[Key] = Value
            end
        elseif Kind == "Event" then
            if typeof(Value) ~= "function" then
                error("Attempt to connect function '"..Key.."' with "..typeof(Value))
            end
            
            (Inst[Key]::RBXScriptSignal):Connect(function(...)
                Value(Inst, ...)
            end)
        elseif typeof(Value) == "function" then
            table.insert(Hooks, Value)
        elseif typeof(Value) == "Instance" then
            Value.Parent = Inst
        else
            error("Invalid/Nil property for "..Inst.Name..": "..Key)
        end
    end

    for _, Hook in ipairs(Hooks) do
        task.spawn(Hook, Inst)
    end
end

local state do
    state = {}
    state._type = "Reactive"
    state._kind = "State"

    function state:update()
        for _, callback in self._subscribed do
            task.spawn(callback)
        end
    end

    function state:__newindex(key, value)
        assert(key == "value" or key == "Value", "Cannot change property of State: "..key)
        self._rawValue = value
        self:update()
    end

    function state:__index(key:string)
        if key == "value" or key == "Value" then
            addToDeps(self)
            return self._rawValue
        else
            return state[key]
        end
    end
end

local derived do
    derived = {}
    derived.__index = derived
    derived._type = "Reactive"
    derived._kind = "Derived"

    function derived:update()
        local deps, value = captureDeps(self._callback)
        self._rawValue = value
        self._deps = deps

        for _, v in self._subscribed do
            task.spawn(v)
        end
    end

    function derived:destroy()
        for Val, Idx in self._deps do
            if Val._subscribed[Idx] then
                Val._subscribed[Idx] = nil
            end
        end
    
        self._deps = nil
        self._callback = nil
    end

    function derived:__index(key:string)
        if key == "value" or key == "Value" then
            addToDeps(self)
            return self._rawValue
        else
            return derived[key]
        end
    end
end

local function Make(Name:string|Instance, Props:T_Props)
    if typeof(Name) == "string" then
        local New = Instance.new(Name)
        applyProps(New, Props)
        return New
    elseif typeof(Name) == "Instance" then
        applyProps(Name, Props)
        return Name :: Instance
    else
        error("Invalid type for 'Name' in Make: "..typeof(Name))
    end
end

local function State<T>(value:T): State<T>
    local self = setmetatable({
        _subscribed = {},
        _rawValue = value
    }, state)
    
    return self
end

-- TODO: obtain obscured values (inside if statements or so)
local function Derive<T>(fn:()->()): Derived<T>
    local self = setmetatable({
        _callback = fn,
        _subscribed = {}
    }, derived)

    self:update()

    for _, Value in ipairs(self._deps) do
        local index = HttpService:GenerateGUID()
        self._deps[Value] = index
        Value._subscribed[index] = function()
            self:update()
        end
    end

    return self
end

local function Component<T>(Props:T, Callback:(Props:T)->())
    return function(InnerProps:T)
        for Key, Value in InnerProps :: any do
            local Type = typeof((Props::any)[Key])
            assert(typeof(Value) ~= "table" or Value._type ~= "Reactive", "Cannot pass Reactives to functions.")
            assert(typeof(Value) == Type, "Invalid type "..Key.." for a Component. Expected "..Type..", got "..typeof(Value))
        end

        for Key, Value in Props :: any do
            if not (InnerProps::any)[Key] then
                (InnerProps::any)[Key] = Value
            end
        end

        local Inst = Callback(InnerProps)

        local ToHydrate = {}
        for Key, Value in Props::any do
            if propKind(Inst, Key) == "Prop" and not (InnerProps::any)[Key] then
                ToHydrate[Key] = Value
            end
        end

        Make(Inst, ToHydrate)

        return Inst
    end
end

local function Changed(name:string, fn:(Inst:Instance, oldValue:any, newValue:any)->())
    return function(inst:Instance)
        assert(propKind(inst, name)=="Prop",name.." is not a valid property of "..inst.ClassName)

        local oldValue = inst[name]
        inst:GetPropertyChangedSignal(name):Connect(function()
            fn(inst, inst[name], oldValue)
            oldValue = inst[name]
        end)
    end
end

local function Bind(name:string, value:State<any>)
    return function(inst:Instance)
        assert(propKind(inst, name) == "Prop", "Cannot bind value "..name.." of "..inst.ClassName.." to State.")
        if typeof(value) == "table" then
            Watcher(value,function()
                value.Value = inst[name]
            end)
        end
    end
end

local function Ref(value:State<Instance>)
    return function(inst)
        value.value = inst
    end
end

local function ForPairs<K,V>(tbl:{[K]:V}, fn:(inst:Instance,k:K,v:V)->())
    return function (inst)
        for K, V in tbl do
            fn(inst,K,V)
        end
    end
end

local function Iter<V>(tbl:{[number]:V}, fn:(inst:Instance,i:number,v:V)->())
    return function (inst)
        for I, V in ipairs(tbl) do
            fn(inst,I,V)
        end
    end
end

local function Child(name:string, toHydrate:T_Props)
    return function(inst:Instance)
        local child = inst:FindFirstChild(name)
        assert(child, name.." is not a child of "..inst.Name)

        Make(child,toHydrate)
    end
end
 
return table.freeze {
    Make = Make,
    State = State,
    Derive = Derive,
    Watcher = Watcher,
    Changed = Changed,
    Bind = Bind,
    Ref = Ref,
    ForPairs = ForPairs,
    Iter = Iter,
    Child = Child,
    Component = Component,
    Empty = function() end
}