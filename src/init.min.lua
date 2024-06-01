local a=game:GetService'HttpService'local b={n=0,closed=true}local c=b type
Primitive=string|boolean|number|Vector3|Instance|CFrame|UDim|UDim2|Vector2|
ColorSequence|NumberSequence|Color3|BrickColor export type State<T> ={value:T,
Value:T,update:(self:State<T>)->()}export type Derived<T> ={value:T,Value:T,
update:(self:State<T>)->(),destroy:(self:Derived<T>)->()}export type T_Props={[
string|number]:Primitive|State<any>|((Instance)->())|Instance}local function
captureDeps(d)local e=c c=table.clone(b)c.closed=nil local f=d()local g=c c=e
return g,f end local function addToDeps(d)if not c.closed then table.insert(c,d)
end end local function propKind(d:Instance,e:string)local f,g=pcall(function()
return(d::any)[e]end)if not f then return'None'elseif typeof(g)==
'RBXScriptSignal'then return'Event'else return'Prop'end end local function
Watcher(d,e:()->()):()->()local f=a:GenerateGUID()d._subscribed[f]=e local g=
false return function()assert(not g,'Watcher was already destroyed.')d.
_subscribed[f]=nil g=true end end local function applyProps(d:Instance,e:T_Props
)local f={}for g,h in e do local i=propKind(d,g::string)if i=='Prop'then if
typeof(h)=='table'and h._type=='Reactive'then Watcher(h,function()d[g]=h.value
end)else d[g]=h end elseif i=='Event'then if typeof(h)~='function'then error(
"Attempt to connect function '"..g.."' with "..typeof(h))end(d[g]::
RBXScriptSignal):Connect(function(...)h(d,...)end)elseif typeof(h)=='function'
then table.insert(f,h)elseif typeof(h)=='Instance'then h.Parent=d else error(
'Invalid/Nil property for '..d.Name..': '..g)end end for i,j in ipairs(f)do task
.spawn(j,d)end end local d do d={}d._type='Reactive'd._kind='State'function d.
update(e)for f,g in e._subscribed do task.spawn(g)end end function d.__newindex(
e,f,g)assert(f=='value'or f=='Value','Cannot change property of State: '..f)e.
_rawValue=g e:update()end function d.__index(e,f:string)if f=='value'or f==
'Value'then addToDeps(e)return e._rawValue else return d[f]end end end local e
do e={}e.__index=e e._type='Reactive'e._kind='Derived'function e.update(f)local
g,h=captureDeps(f._callback)f._rawValue=h f._deps=g for i,j in f._subscribed do
task.spawn(j)end end function e.destroy(f)for g,h in f._deps do if g._subscribed
[h]then g._subscribed[h]=nil end end f._deps=nil f._callback=nil end function e.
__index(f,g:string)if g=='value'or g=='Value'then addToDeps(f)return f._rawValue
else return e[g]end end end local function Make(f:string|Instance,g:T_Props)if
typeof(f)=='string'then local h=Instance.new(f)applyProps(h,g)return h elseif
typeof(f)=='Instance'then applyProps(f,g)return f::Instance else error(
"Invalid type for 'Name' in Make: "..typeof(f))end end local function State<T>(f
:T):State<T>local g=setmetatable({_subscribed={},_rawValue=f},d)return g end
local function Derive<T>(f:()->()):Derived<T>local g=setmetatable({_callback=f,
_subscribed={}},e)g:update()for h,i in ipairs(g._deps)do local j=a:GenerateGUID(
)g._deps[i]=j i._subscribed[j]=function()g:update()end end return g end
local function Component<T>(f:T,g:(Props:T)->())return function(h:T)for i,j in h
::any do local k=typeof((f::any)[i])assert(typeof(j)~='table'or j._type~=
'Reactive','Cannot pass Reactives to functions.')assert(typeof(j)==k,
'Invalid type '..i..' for a Component. Expected '..k..', got '..typeof(j))end
for k,l in f::any do if not(h::any)[k]then(h::any)[k]=l end end local m=g(h)
local n={}for o,p in f::any do if propKind(m,o)=='Prop'and not(h::any)[o]then n[
o]=p end end Make(m,n)return m end end local function Changed(f:string,g:(Inst:
Instance,oldValue:any,newValue:any)->())return function(h:Instance)assert(
propKind(h,f)=='Prop',f..' is not a valid property of '..h.ClassName)local m=h[f
]h:GetPropertyChangedSignal(f):Connect(function()g(h,h[f],m)m=h[f]end)end end
local function Bind(f:string,g:State<any>)return function(h:Instance)assert(
propKind(h,f)=='Prop','Cannot bind value '..f..' of '..h.ClassName..' to State.'
)if typeof(g)=='table'then Watcher(g,function()g.Value=h[f]end)end end end
local function Ref(f:State<Instance>)return function(g)f.value=g end end
local function ForPairs<K,V>(f:{[K]:V},g:(inst:Instance,k:K,v:V)->())return
function(h)for m,n in f do g(h,m,n)end end end local function Iter<V>(f:{[number
]:V},g:(inst:Instance,i:number,v:V)->())return function(h)for m,n in ipairs(f)do
g(h,m,n)end end end local function Child(f:string,g:T_Props)return function(h:
Instance)local m=h:FindFirstChild(f)assert(m,f..' is not a child of '..h.Name)
Make(m,g)end end return table.freeze{Make=Make,State=State,Derive=Derive,Watcher
=Watcher,Changed=Changed,Bind=Bind,Ref=Ref,ForPairs=ForPairs,Iter=Iter,Child=
Child,Component=Component,Empty=function()end}