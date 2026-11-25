TESTS={}
local function Equal(a,b,why) assert(a==b,(why or "mismatch")..": "..tostring(a).." ~= "..tostring(b)) end
local function NoCombatWrites()
    for _,write in ipairs(MOCK.writes) do assert(not write.combat,"wrote a CVar during combat") end
end

TESTS["default native only, outline preserved"] = function()
    local ns=MOCK.Load()
    Equal(MOCK.cv.outlineModeShowLootEffectWhenDisabled,"1")
    Equal(MOCK.cv.graphicsOutlineMode,"2")
    Equal(MOCK.cv.SoftTargetInteract,"0")
    Equal(ns.db.enhanced,false)
    for _,write in ipairs(MOCK.writes) do Equal(write.name,"outlineModeShowLootEffectWhenDisabled") end
end

TESTS["graphics preset reapplies once without loops"] = function()
    MOCK.Load()
    local before=#MOCK.writes
    MOCK.cv.outlineModeShowLootEffectWhenDisabled="0"
    for i=1,10 do MOCK.Fire("CVAR_UPDATE","graphicsQuality") end
    MOCK.Advance(2)
    Equal(MOCK.cv.outlineModeShowLootEffectWhenDisabled,"1")
    Equal(#MOCK.writes,before+1)
end

TESTS["quest object exists without UnitExists and releases alpha"] = function()
    local ns=MOCK.Load({enhanced=true})
    local plate=MOCK.Target({quest=true,cursor="Quest"})
    assert(MOCK.Effect(plate):IsVisible())
    Equal(plate.UnitFrame:GetAlpha(),0)
    ns.SetOption("enabled",false)
    Equal(MOCK.Effect(plate),nil)
    Equal(plate.UnitFrame:GetAlpha(),0.65)
    Equal(MOCK.cv.SoftTargetInteract,"0")
    Equal(MOCK.cv.outlineModeShowLootEffectWhenDisabled,"0")
    Equal(next(ns.db.journal),nil)
end

TESTS["external setting edit wins on restore"] = function()
    local ns=MOCK.Load({enhanced=true})
    MOCK.cv.SoftTargetInteractRange="8"
    ns.RestoreAll()
    Equal(MOCK.cv.SoftTargetInteractRange,"8")
    Equal(MOCK.cv.SoftTargetInteractArc,"0")
    Equal(next(ns.db.journal),nil)
end

TESTS["no protected writes in combat, deferred disable restores"] = function()
    local ns=MOCK.Load({enhanced=true})
    local plate=MOCK.Target({quest=true,cursor="Quest"})
    local effect=MOCK.Effect(plate)
    MOCK.SetCombat(true)
    assert(not effect:IsVisible())
    local count=#MOCK.writes
    ns.RestoreAll(); MOCK.Advance(1)
    Equal(#MOCK.writes,count)
    MOCK.SetCombat(false); MOCK.Advance(0.3)
    Equal(MOCK.cv.SoftTargetInteract,"0")
    Equal(MOCK.cv.outlineModeShowLootEffectWhenDisabled,"0")
    NoCombatWrites()
end

TESTS["unsupported interface does not change settings"] = function()
    MOCK.interface=120005
    local ns=MOCK.Load({enhanced=true})
    ns.SetOption("enabled",false)
    Equal(#MOCK.writes,0)
    assert(not ns.supported)
end

TESTS["unknown and failed CVars are not journaled as applied"] = function()
    local ns=MOCK.Load()
    MOCK.cv.SoftTargetInteractRange=nil
    MOCK.fail="SoftTargetInteract"
    ns.SetOption("enhanced",true)
    Equal(ns.db.journal.SoftTargetInteract,nil)
    Equal(ns.db.journal.SoftTargetInteractRange,nil)
    for _,write in ipairs(MOCK.writes) do assert(write.name~="SoftTargetInteractRange") end
    assert(ns.lastError)
end

TESTS["living interaction target is paused until player moves"] = function()
    MOCK.Load({enhanced=true})
    MOCK.Target({object=false,exists=true,dead=false,name="旁边的玩家",guid="Player-1-42"})
    Equal(MOCK.cv.SoftTargetInteract,"0")
    MOCK.target=nil; MOCK.units.nameplate1=nil
    MOCK.y=6; MOCK.Advance(0.3)
    Equal(MOCK.cv.SoftTargetInteract,"3")
end

TESTS["pause recovery retains original settings across reload"] = function()
    local saved={enhanced=true,pausedInteract="3",journal={SoftTargetInteract={original="0",last="0",group="soft"}}}
    local ns=MOCK.Load(saved)
    Equal(MOCK.cv.SoftTargetInteract,"3")
    ns.RestoreAll()
    Equal(MOCK.cv.SoftTargetInteract,"0")
end

TESTS["competing enhancer pauses only added effects"] = function()
    MOCK.loaded.Lueur=true
    local ns=MOCK.Load({enhanced=true})
    Equal(MOCK.cv.SoftTargetInteract,"0")
    Equal(MOCK.cv.outlineModeShowLootEffectWhenDisabled,"1")
    Equal(ns.conflict,"Lueur")
    assert(not ns.CanEnhance())
end

TESTS["preview and style edits do not enable targeting"] = function()
    local ns=MOCK.Load()
    local writes=#MOCK.writes
    SlashCmdList.SPARKLEBOOST("test")
    assert(SparkleBoostOptions:IsVisible())
    ns.SetOption("style","ring"); ns.SetOption("size",2); ns.SetOption("brightness",1.5)
    MOCK.Advance(0.5)
    Equal(#MOCK.writes,writes)
    Equal(MOCK.cv.SoftTargetInteract,"0")
    SlashCmdList.SPARKLEBOOST("")
    assert(not SparkleBoostOptions:IsVisible())
end

TESTS["removed nameplate restores alpha even after API forgets plate"] = function()
    MOCK.Load({enhanced=true})
    local plate=MOCK.Target({quest=true,cursor="Quest"})
    local effect=MOCK.Effect(plate)
    MOCK.target=nil; MOCK.units.nameplate1=nil
    MOCK.Fire("NAME_PLATE_UNIT_REMOVED","nameplate1")
    assert(not effect:IsVisible())
    Equal(plate.UnitFrame:GetAlpha(),0.65)
end

TESTS["Chinese quest objective fallback classifies object"] = function()
    MOCK.objectives={{text="丢失的木箱：0/1",finished=false}}
    MOCK.Load({enhanced=true})
    local plate=MOCK.Target({name="丢失的木箱",cursor="Interact",quest=false})
    assert(MOCK.Effect(plate):IsVisible())
end

TESTS["secret target data releases stale visual"] = function()
    MOCK.Load({enhanced=true})
    local plate=MOCK.Target({quest=true,cursor="Quest"})
    local effect=MOCK.Effect(plate)
    MOCK.secrets=true
    MOCK.Fire("PLAYER_SOFT_INTERACT_CHANGED")
    MOCK.Advance(0.3)
    assert(not effect:IsVisible())
end

TESTS["animation scales, colors and does not allocate per frame"] = function()
    local ns=MOCK.Load({enhanced=true})
    local plate=MOCK.Target({cursor="Mine",quest=false})
    local effect=MOCK.Effect(plate)
    assert(effect:IsVisible())
    local frames=#MOCK.frames
    local original=effect.textures[2].height
    ns.SetOption("size",3); ns.SetOption("palette","cyan"); MOCK.Advance(0.3)
    assert(effect.textures[2].height>original)
    Equal(effect.textures[2].color[2],0.85)
    MOCK.Advance(4)
    Equal(#MOCK.frames,frames)
    ns.SetOption("style","sparkles"); MOCK.Advance(0.1)
    Equal(effect.textures[2].color[4],0)
end

TESTS["logout restores originals without disabling preference"] = function()
    local ns=MOCK.Load({enhanced=true})
    MOCK.Fire("PLAYER_LOGOUT")
    Equal(MOCK.cv.SoftTargetInteract,"0")
    Equal(MOCK.cv.outlineModeShowLootEffectWhenDisabled,"0")
    Equal(ns.db.enabled,true)
    Equal(next(ns.db.journal),nil)
    local count=#MOCK.writes
    MOCK.Advance(3)
    Equal(#MOCK.writes,count)
end

TESTS["early logout cannot reactivate delayed enhancement"] = function()
    MOCK.loaded.ForeverLootSparkles=true
    MOCK.Load({enhanced=true})
    MOCK.Fire("PLAYER_LOGOUT")
    local count=#MOCK.writes
    MOCK.Advance(8)
    Equal(#MOCK.writes,count)
    Equal(MOCK.cv.SoftTargetInteract,"0")
end

TESTS["journal cannot restore an unrelated graphics setting"] = function()
    local ns=MOCK.Load({journal={graphicsOutlineMode={original="0",last="2",group="soft"}}})
    ns.RestoreAll()
    Equal(MOCK.cv.graphicsOutlineMode,"2")
    assert(not ns.SetManagedCVar("graphicsOutlineMode",0,"soft"))
end

TESTS["corrupt saved options cannot produce invalid graphics values"] = function()
    local ns=MOCK.Load({size=0/0,brightness=math.huge,range=-900,style="invalid",palette="invalid",journal="invalid",minimapAngle=0/0})
    Equal(ns.db.size,1.5); Equal(ns.db.brightness,1); Equal(ns.db.range,5)
    Equal(ns.db.minimapAngle,225)
    assert(not ns.SetOption("size","NaN"))
    assert(not ns.SetOption("style","invalid"))
    Equal(MOCK.cv.graphicsOutlineMode,"2")
end

TESTS["minimap opens settings while disabled and in combat without CVar writes"] = function()
    local ns=MOCK.Load({enabled=false})
    local button=assert(SparkleBoostMinimapButton,"missing minimap button")
    assert(button:IsVisible())
    Equal(button:GetParent(),Minimap)
    Equal(button.clicks[1],"LeftButtonUp")
    MOCK.SetCombat(true)
    local writes=#MOCK.writes
    button.scripts.OnMouseDown(button,"LeftButton")
    button.scripts.OnClick(button,"LeftButton")
    assert(SparkleBoostOptions:IsVisible())
    button.scripts.OnMouseDown(button,"LeftButton")
    button.scripts.OnClick(button,"LeftButton")
    assert(not SparkleBoostOptions:IsVisible())
    button.scripts.OnClick(button,"RightButton")
    assert(not SparkleBoostOptions:IsVisible())
    Equal(ns.db.enabled,false); Equal(ns.db.enhanced,false)
    Equal(#MOCK.writes,writes)
end

TESTS["minimap drag uses UI scale and does not open settings on release"] = function()
    local ns=MOCK.Load()
    local button=assert(SparkleBoostMinimapButton,"missing minimap button")
    Minimap.scale=0.75
    MOCK.cursorX=(Minimap.centerX+100)*Minimap.scale
    MOCK.cursorY=(Minimap.centerY+100)*Minimap.scale
    local writes=#MOCK.writes
    button.scripts.OnMouseDown(button,"LeftButton")
    button.scripts.OnDragStart(button)
    MOCK.Advance(0.1)
    assert(math.abs(ns.db.minimapAngle-45)<0.001)
    local point=button.points[1]
    Equal(point[2],Minimap)
    assert(math.abs(point[4]-86/math.sqrt(2))<0.001)
    assert(math.abs(point[5]-86/math.sqrt(2))<0.001)
    button.scripts.OnDragStop(button)
    Equal(button.scripts.OnUpdate,nil)
    button.scripts.OnClick(button,"LeftButton")
    assert(not SparkleBoostOptions or not SparkleBoostOptions:IsVisible())
    button.scripts.OnMouseDown(button,"LeftButton")
    button.scripts.OnClick(button,"LeftButton")
    assert(SparkleBoostOptions:IsVisible(),"next real click must work")
    Equal(SparkleBoostDB.minimapAngle,ns.db.minimapAngle)
    Equal(#MOCK.writes,writes)
end

TESTS["minimap restores saved angle and initializes only once"] = function()
    local ns=MOCK.Load({minimapAngle=180,enabled=false})
    local button=assert(SparkleBoostMinimapButton,"missing minimap button")
    local point=button.points[1]
    assert(math.abs(point[4]+86)<0.001 and math.abs(point[5])<0.001)
    local frames=#MOCK.frames
    ns.CreateMinimapButton()
    Equal(#MOCK.frames,frames)
    Equal(ns.db.minimapAngle,180)
    Equal(button.scripts.OnUpdate,nil)
end

TESTS["minimap hidden during drag stops updates and keeps valid position"] = function()
    local ns=MOCK.Load({minimapAngle=90})
    local button=assert(SparkleBoostMinimapButton,"missing minimap button")
    MOCK.cursorX,MOCK.cursorY=Minimap.centerX,Minimap.centerY
    button.scripts.OnMouseDown(button,"LeftButton")
    button.scripts.OnDragStart(button)
    MOCK.Advance(0.1)
    Equal(ns.db.minimapAngle,90)
    Minimap.centerX=nil
    MOCK.Advance(0.1)
    Equal(ns.db.minimapAngle,90)
    button:Hide()
    Equal(button.scripts.OnUpdate,nil)
    button:Show()
    button.scripts.OnMouseDown(button,"LeftButton")
    button.scripts.OnClick(button,"LeftButton")
    assert(SparkleBoostOptions:IsVisible())
end
