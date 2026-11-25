local M = MOCK
local TEST = {}
TESTS = TEST

local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function start()
    local db = M.Load(nil, true, false)
    return M.Open(), db
end

local function setEnemy(first, last)
    M.target = { player = true, first = first, last = last }
end

local function addNames(count)
    local names = { "暮刃 枫影", "踏雪 银松", "深潮 暮羽", "荒歌 岩脊", "夜棘 灰烬", "寒鸦 晨星", "白霜 松歌" }
    for index = 1, count do M.Paste(names[index], index % 2 == 0) end
    return names
end

local function lastMacro()
    return M.calls[#M.calls]
end

function TEST.minimap_click_toggles_the_panel()
    local db = M.Load(nil, true, false)
    local control = assert(WantedPosterMinimapButton)
    equal(control.parent, Minimap)
    equal(control.clicks[1], "LeftButtonUp")
    equal(control.mouseEnabled, true)
    equal(control.shown, true)
    M.Emit("PLAYER_ENTERING_WORLD", false, false)
    equal(#Minimap.children, 1)
    equal(WantedPosterFrame, nil)
    M.SetCombat(true)
    M.Click(control)
    equal(WantedPosterFrame, nil)
    equal(M.notices[#M.notices], "通缉令  脱战后可以打开或关闭面板。")
    M.SetCombat(false)
    M.Click(control)
    local pane = assert(WantedPosterFrame)
    equal(pane.shown, true)
    M.Paste("北郡 春霜")
    M.Click(control)
    equal(pane.shown, false)
    M.Click(control)
    equal(WantedPosterFrame, pane)
    equal(pane.shown, true)
    equal(db.groups[1].names[1], "北郡 春霜")
    M.Load(db, false, true)
    M.Click(assert(WantedPosterMinimapButton))
    equal(WantedPosterFrame.rows[1].find.label.text, "北郡 春霜")
end

function TEST.minimap_drag_persists_without_toggling()
    local db = M.Load(nil, true, false)
    local control = assert(WantedPosterMinimapButton)
    equal(control.dragButtons[1], "LeftButton")
    M.Click(control, "RightButton")
    equal(WantedPosterFrame, nil)

    M.cursorX, M.cursorY = (Minimap.centerX + 76) * Minimap.scale, Minimap.centerY * Minimap.scale
    M.Fire(control, "OnMouseDown", "LeftButton")
    M.Fire(control, "OnDragStart")
    assert(control.scripts.OnUpdate)
    M.cursorX, M.cursorY = Minimap.centerX * Minimap.scale, (Minimap.centerY + 76) * Minimap.scale
    M.Fire(control, "OnUpdate")
    M.Fire(control, "OnDragStop")
    equal(control.scripts.OnUpdate, nil)
    assert(math.abs(db.minimapAngle - 90) < 0.001)
    local x, y = control.x, control.y
    M.Fire(control, "OnClick", "LeftButton")
    equal(WantedPosterFrame, nil)

    M.Load(db, false, true)
    control = assert(WantedPosterMinimapButton)
    equal(control.x, x)
    equal(control.y, y)
    M.Click(control)
    equal(assert(WantedPosterFrame).shown, true)
end

function TEST.panel_resizes_at_fixed_ratio_and_restores_scale()
    UIParent:SetScale(0.8)
    local pane, db = start()
    equal(pane.width, 280)
    equal(pane.height, 326)
    equal(pane.previousGroup.text, "<")
    equal(pane.nextGroup.text, ">")
    equal(pane.previousPage.text, "<")
    equal(pane.nextPage.text, ">")
    equal(pane.resize.dragButtons[1], "LeftButton")
    pane.left, pane.top = 550, 820
    local originalX, originalY = 350, 240
    M.cursorX, M.cursorY = originalX, originalY
    M.Fire(pane.resize, "OnDragStart")
    assert(pane.resize.scripts.OnUpdate)
    local function dragBy(delta)
        M.cursorX = originalX + 0.8 * pane.width * delta
        M.cursorY = originalY - 0.8 * pane.height * delta
        M.Fire(pane.resize, "OnUpdate")
    end
    dragBy(3)
    equal(pane:GetScale(), 1.50)
    dragBy(-3)
    equal(pane:GetScale(), 0.70)
    dragBy(0.2)
    assert(math.abs(pane:GetScale() - 1.2) < 0.001)
    equal(pane.point, "TOPLEFT")
    assert(math.abs(pane.x * pane:GetEffectiveScale() - 440) < 0.001)
    assert(math.abs(-pane.y * pane:GetEffectiveScale() - (820 - 1080) * 0.8) < 0.001)
    M.SetCombat(true)
    equal(pane.resize.enabled, false)
    dragBy(0.4)
    equal(pane.resize.scripts.OnUpdate, nil)
    assert(math.abs(db.panelScale - 1.2) < 0.001)
    M.SetCombat(false)
    M.Load(db, false, true)
    pane = M.Open()
    assert(math.abs(pane:GetScale() - 1.2) < 0.001)
    equal(pane.width, 280)
    equal(pane.height, 326)
end

function TEST.compact_controls_fit_at_minimum_scale()
    M.Load({ panelScale = 0.70 }, true, false)
    local pane = M.Open()
    addNames(7)
    M.Click(pane.previousPage)
    equal(pane:GetScale(), 0.70)
    equal(#pane.rows, 5)
    equal(pane.pageLabel.text, "1 / 2 页")
    equal(pane.status.text, "本组共 7 人")
    assert(pane.pageLabel:GetUnboundedStringWidth() <= pane.pageLabel:GetWidth())

    local title
    for _, child in ipairs(pane.children) do
        assert(child.text ~= "本次登录")
        if child.text == "WANTED" then title = child end
    end
    assert(title)
    equal(title.size, 27)
    equal(title.justify, "CENTER")
    equal(title.x + title.width / 2, pane.width / 2)
    equal(pane.previousGroup.y + pane.previousGroup.height / 2, title.y + title.height / 2)
    equal(pane.nextGroup.y + pane.nextGroup.height / 2, title.y + title.height / 2)
    equal(pane.addTarget.text, "通缉目标")
    equal(pane.clear.text, "清空")
    equal(pane.searchPage.text, "搜索")

    local controls = {
        pane.close, pane.previousGroup, title, pane.nextGroup,
        pane.addTarget, pane.input, pane.addPasted,
        pane.previousPage, pane.pageLabel, pane.nextPage, pane.clear, pane.searchPage, pane.status, pane.resize,
    }
    for slot, row in ipairs(pane.rows) do
        equal(row.find.y, 107 + (slot - 1) * 35)
        equal(row.remove.width, 22)
        equal(row.remove.height, 22)
        assert(row.find.enabled and row.remove.enabled)
        controls[#controls + 1] = row.find
        controls[#controls + 1] = row.remove
    end
    for index, control in ipairs(controls) do
        assert(control.shown and control.x >= 0 and control.y >= 0)
        assert(control.x + control.width <= pane.width and control.y + control.height <= pane.height)
        for otherIndex = index + 1, #controls do
            local other = controls[otherIndex]
            assert(control.x + control.width <= other.x or other.x + other.width <= control.x
                or control.y + control.height <= other.y or other.y + other.height <= control.y,
                "compact panel regions overlap")
        end
    end
end

function TEST.manual_add_and_duplicate()
    local pane, db = start()
    equal(#db.groups[1].names, 0)
    setEnemy("听风人", "夜松")
    M.Click(pane.addTarget)
    M.Paste("  听风人　 夜松 ")
    equal(#db.groups[1].names, 1)
    equal(db.groups[1].names[1], "听风人 夜松")
    equal(pane.rows[1].find.label.text, "听风人 夜松")
    M.Click(pane.rows[1].find)
    equal(lastMacro(), "/tar 听风人 夜松")
    M.Paste("River Stone", true)
    M.Paste("river stone")
    equal(#db.groups[1].names, 2)
end

function TEST.incomplete_and_protected_names()
    local pane, db = start()
    M.Click(pane.addTarget)
    equal(#db.groups[1].names, 0)
    M.target = { player = false, first = "老灰熊", last = "野兽" }
    M.Click(pane.addTarget)
    equal(#db.groups[1].names, 0)
    setEnemy(M.secret, "夜松")
    M.Click(pane.addTarget)
    equal(pane.status.text, "当前目标姓名不可读，可以粘贴加入。")
    M.Paste("只有名字")
    M.Paste("北境 风铃\n/run print(1)")
    M.Paste("北境 风铃; /run")
    M.Paste("北境 [风铃]")
    equal(#db.groups[1].names, 0)
    setEnemy("  北境　风铃  ", nil)
    M.Click(pane.addTarget)
    equal(db.groups[1].names[1], "北境 风铃")
end

function TEST.five_per_page_and_correct_actions()
    local pane = start()
    assert(pane.searchPage.panelButton and pane.searchPage.secureAction)
    local names = addNames(7)
    equal(pane.pageLabel.text, "2 / 2 页")
    equal(pane.rows[1].find.label.text, names[6])
    equal(pane.rows[3].find.shown, false)
    M.Click(pane.searchPage)
    equal(lastMacro(), "/tar " .. names[6] .. "\n/tar " .. names[7])
    M.Click(pane.previousPage)
    equal(pane.pageLabel.text, "1 / 2 页")
    for index = 1, 5 do
        M.Click(pane.rows[index].find)
        equal(lastMacro(), "/tar " .. names[index])
    end
    M.Click(pane.nextPage)
    M.Click(pane.rows[2].find)
    equal(lastMacro(), "/tar " .. names[7])
    local macroCount = 0
    for _ in pairs(M.macros) do macroCount = macroCount + 1 end
    equal(macroCount, 3)
end

function TEST.length_limit_and_complete_lines()
    local pane, db = start()
    for _, surname in ipairs({ "姓", "流", "姓3", "姓4", "姓5" }) do
        M.Paste(("名"):rep(25) .. " " .. surname)
    end
    equal(#db.groups[1].names, 5)
    M.Click(pane.previousPage)
    M.Click(pane.searchPage)
    local body = lastMacro()
    equal(#body, 255)
    equal(select(2, body:gsub("/tar ", "")), 3)
    assert(body:match("姓3$"))
    M.Paste(("名"):rep(85) .. " 姓")
    equal(#db.groups[1].names, 5)
end

function TEST.player_names_fit_on_the_poster_centerline()
    local pane, db = start()
    local name = ("长"):rep(40) .. " " .. ("松"):rep(43)
    M.Paste(name)
    local find = pane.rows[1].find
    local label = find.label
    equal(label.justify, "CENTER")
    equal(find.x + label.x + label.width / 2, pane.width / 2)
    assert(find.x + label.x + label.width < pane.rows[1].remove.x)
    equal(label.size, 16)
    assert(#label.text > 0 and #label.text < #name and #label.text % #"长" == 0)
    equal(label.text, name:sub(1, #label.text))
    assert(label:GetUnboundedStringWidth() <= label:GetWidth())
    equal(find.hint, name)
    equal(db.groups[1].names[1], name)
    M.Click(find)
    equal(lastMacro(), "/tar " .. name)

    M.Paste("暮刃 枫影")
    equal(label.size, 23)
    equal(label.text, "暮刃 枫影")
    local wideName = "清风照雪千山 白云归远海"
    M.Paste(wideName)
    local wideLabel = pane.rows[2].find.label
    equal(wideLabel.size, 16)
    equal(wideLabel.text, wideName)
    assert(wideLabel:GetUnboundedStringWidth() <= wideLabel:GetWidth())
end

function TEST.single_removal_and_clear_selected_page()
    local pane, db = start()
    local names = addNames(7)
    M.Click(pane.previousPage)
    M.Click(pane.rows[2].remove)
    equal(db.groups[1].names[2], names[3])
    M.Click(pane.rows[2].find)
    equal(lastMacro(), "/tar " .. names[3])
    M.Click(pane.nextPage)
    equal(pane.rows[1].find.label.text, names[7])
    M.Click(pane.clear)
    equal(M.popup.count, 1)
    M.Accept()
    equal(#db.groups[1].names, 5)
    equal(pane.pageLabel.text, "1 / 1 页")
    M.Click(pane.clear)
    M.Accept()
    equal(#db.groups[1].names, 0)
    equal(next(M.macros), nil)
    equal(pane.searchPage.enabled, false)
end

function TEST.confirmation_never_erases_a_different_record()
    local pane, db = start()
    local names = addNames(6)
    M.Click(pane.previousPage)
    M.Click(pane.clear)
    M.Click(pane.rows[2].remove)
    M.Accept()
    equal(#db.groups[1].names, 5)
    equal(db.groups[1].names[2], names[3])
    equal(pane.status.text, "名单已变动，请重新选择要清理的记录。")
end

function TEST.clear_removes_matching_legacy_macros_and_copies()
    local db = M.Load({ groups = {{ names = { "暮刃 枫影", "踏雪 银松" } }} }, false, true)
    local first, second = "/tar 暮刃 枫影", "/tar 踏雪 银松"
    M.macros[1] = { name = "WP_Target1", body = first, icon = 134400 }
    M.macros[121] = { name = "WP_Target1", body = first, icon = 134400 }
    M.macros[122] = { name = "WP_Target1_1", body = first .. "\r\n", icon = 134400 }
    M.macros[123] = { name = "WP_Target2", body = second, icon = 134400 }
    M.macros[124] = { name = "WP_Target6", body = first .. "\n" .. second, icon = 134400 }
    M.macros[125] = { name = "WP_Target6_1", body = first, icon = 134400 }
    M.macros[126] = { name = "WP_Target6_2", body = first .. "\n/tar 其他 路人", icon = 134400 }
    M.macros[127] = { name = "WP_Target1_2", body = first, icon = 123456 }
    M.macros[128] = { name = "tar", body = first, icon = 134400 }
    M.macros[129] = { name = "WP_Target2_1", body = second .. "\n/say edited", icon = 134400 }
    local pane = M.Open()
    M.Click(pane.clear)
    equal(select(2, GetNumMacros()), 9)
    M.Accept()
    equal(#db.groups[1].names, 0)
    equal(select(2, GetNumMacros()), 4)
    equal(next(db.macros), nil)
    equal(db.macroCleanup, nil)
    equal(pane.searchPage.enabled, false)
    equal(M.macros[1].name, "WP_Target1")
    equal(M.macros[121].name, "WP_Target6_2")
    equal(M.macros[122].name, "WP_Target1_2")
    equal(M.macros[123].name, "tar")
    equal(M.macros[124].name, "WP_Target2_1")
end

function TEST.clear_waits_for_macro_editor_and_checks_changes_again()
    local pane, db = start()
    M.Paste("暮刃 枫影")
    local editor = CreateFrame("Frame", "MacroFrame", UIParent)
    M.Click(pane.clear)
    M.Accept()
    equal(#db.groups[1].names, 0)
    equal(select(2, GetNumMacros()), 2)
    equal(pane.status.text, "关闭游戏宏窗口后清理查找宏。")
    assert(db.macroCleanup.WP_Target1 and db.macroCleanup.WP_Target6)
    M.macros[assert(GetMacroIndexByName("WP_Target1"))].icon = 123456
    M.Click(pane.close)
    editor:Hide()
    M.Tick()
    equal(select(2, GetNumMacros()), 1)
    equal(db.macroCleanup, nil)
    equal(M.macros[121].name, "WP_Target1")
    equal(M.macros[121].icon, 123456)
end

function TEST.login_and_reload_are_distinct()
    local _, db = start()
    addNames(2)
    M.Load(db, false, true)
    equal(#db.groups, 1)
    local pane = M.Open()
    equal(pane.rows[2].find.shown, true)
    M.Emit("PLAYER_ENTERING_WORLD", false, false)
    equal(#db.groups, 1)
    M.now = time() + 86400
    M.Load(db, true, false)
    pane = M.Open()
    equal(#db.groups, 2)
    equal(#db.groups[2].names, 0)
    equal(pane.previousGroup.hint, "上一组登录")
    assert(pane.previousGroup.enabled and not pane.nextGroup.enabled)
    M.Click(pane.previousGroup)
    equal(pane.rows[1].find.label.text, db.groups[1].names[1])
    assert(not pane.previousGroup.enabled and pane.nextGroup.enabled)
    equal(pane.nextGroup.hint, "下一组登录\n正在查看 " .. date("%m月%d日 %H:%M", db.groups[1].started))
    M.Click(pane.nextGroup)
    assert(pane.empty.shown)
    M.Click(pane.previousGroup)
    M.Paste("北郡 春霜")
    equal(pane.nextGroup.hint, "下一组登录")
    equal(#db.groups[1].names, 2)
    equal(db.groups[2].names[1], "北郡 春霜")
end

function TEST.nameplate_alert_can_match_a_saved_group_with_no_panel_or_target()
    local names = { "暮刃 枫影", "踏雪 银松", "深潮 暮羽", "荒歌 岩脊", "夜棘 灰烬", "River Stone" }
    M.Load({ groups = {
        { started = time() - 3600, names = names },
        { started = time(), names = { "晨星 晴川" } },
    } }, false, true)
    M.SetCombat(true)
    M.AddNameplate("nameplate1", { player = true, enemy = true, first = "river", last = "stone" })
    equal(#M.alerts, 1)
    equal(M.alerts[1], "通缉目标出现：river stone")
    equal(WantedPosterFrame, nil)
    equal(M.target, nil)
    equal(next(M.macros), nil)
    equal(#M.calls, 0)
    equal(#M.timers, 0)
    equal(#M.notices, 0)
end

function TEST.nameplate_alert_skips_unconfirmed_or_unreadable_identities()
    M.Load({ groups = { { started = time(), names = { "暮刃 枫影", "River Stone-Maple" } } } }, false, true)
    local wanted = { player = true, enemy = true, first = "暮刃 枫影" }
    M.Emit("NAME_PLATE_UNIT_ADDED", M.secret)
    M.AddNameplate("target", wanted)
    M.nameplates.nameplate1 = wanted
    M.Emit("FORBIDDEN_NAME_PLATE_UNIT_ADDED", "nameplate1")
    M.AddNameplate("nameplate1", { player = false, enemy = true, first = wanted.first })
    M.AddNameplate("nameplate1", { player = true, enemy = false, first = wanted.first })
    M.AddNameplate("nameplate1", { player = M.secret, enemy = true, first = wanted.first })
    M.AddNameplate("nameplate1", { player = true, enemy = M.secret, first = wanted.first })
    M.AddNameplate("nameplate1", { player = true, enemy = true, hidden = true, first = wanted.first })
    M.AddNameplate("nameplate1", { player = true, enemy = true, hidden = M.secret, first = wanted.first })
    equal(M.plateNameReads, 0)

    M.AddNameplate("nameplate1", { player = true, enemy = true, first = "暮刃 松歌" })
    M.AddNameplate("nameplate1", { player = true, enemy = true, first = wanted.first, last = "Other" })
    M.AddNameplate("nameplate1", { player = true, enemy = true, first = "River Stone-Oak", last = "Oak" })
    M.AddNameplate("nameplate1", { player = true, enemy = true, nameError = true })
    M.AddNameplate("nameplate1", { player = true, enemy = true, last = "枫影" })
    M.AddNameplate("nameplate1", { player = true, enemy = true, first = M.secret })
    M.AddNameplate("nameplate1", { player = true, enemy = true, first = wanted.first, last = M.secret })
    equal(#M.alerts, 0)

    M.AddNameplate("nameplate1", { player = true, enemy = true, first = "River Stone-Maple", last = "Maple" })
    equal(#M.alerts, 1)
    equal(M.alerts[1], "通缉目标出现：River Stone-Maple")
end

function TEST.nameplate_alert_deduplicates_appearances_and_handles_token_reuse()
    M.Load({ groups = { { started = time(), names = { "暮刃 枫影", "踏雪 银松" } } } }, false, true)
    local first = { player = true, enemy = true, first = "暮刃 枫影" }
    local second = { player = true, enemy = true, first = "踏雪 银松" }
    M.AddNameplate("nameplate1", first)
    M.Emit("NAME_PLATE_UNIT_ADDED", "nameplate1")
    equal(#M.alerts, 1)
    M.RemoveNameplate("nameplate1")
    M.uptime = 20
    M.AddNameplate("nameplate2", first)
    equal(#M.alerts, 1)
    M.AddNameplate("nameplate2", second)
    equal(#M.alerts, 2)
    M.AddNameplate("nameplate3", second)
    equal(#M.alerts, 2)
    M.uptime = 31
    M.AddNameplate("nameplate2", first)
    equal(#M.alerts, 3)
    M.uptime = 62
    M.Emit("NAME_PLATE_UNIT_ADDED", "nameplate2")
    equal(#M.alerts, 3)
    M.RemoveNameplate("nameplate2")
    M.AddNameplate("nameplate2", first)
    equal(#M.alerts, 4)
end

function TEST.nameplate_alert_reads_the_roster_after_an_entry_is_removed()
    local pane = start()
    M.Paste("暮刃 枫影")
    M.Paste("踏雪 银松")
    M.Click(pane.rows[1].remove)
    M.Click(pane.close)
    M.AddNameplate("nameplate1", { player = true, enemy = true, first = "暮刃 枫影" })
    equal(#M.alerts, 0)
    M.AddNameplate("nameplate1", { player = true, enemy = true, first = "踏雪 银松" })
    equal(#M.alerts, 1)
    equal(M.alerts[1], "通缉目标出现：踏雪 银松")
    equal(#M.calls, 0)
end

function TEST.combat_keeps_names_bound_and_queues_output()
    local pane, db = start()
    local names = addNames(5)
    M.SetCombat(true)
    M.Paste("北郡 春霜")
    setEnemy("晨星", "晴川")
    M.Click(pane.addTarget)
    equal(#db.groups[1].names, 7)
    equal(pane.status.text, "已记下，脱战后更新查找。")
    equal(pane.pageLabel.text, "1 / 1 页")
    equal(pane.clear.enabled, false)
    M.Click(pane.rows[3].find)
    equal(lastMacro(), "/tar " .. names[3])
    M.SetCombat(false)
    equal(pane.pageLabel.text, "2 / 2 页")
    M.Click(pane.searchPage)
    equal(lastMacro(), "/tar 北郡 春霜\n/tar 晨星 晴川")
end

function TEST.never_edits_user_macros_and_detects_changed_body()
    M.macros[1] = { name = "WP_Target6", body = "/say hello" }
    M.macros[121] = { name = "WP_Target1", body = "/dance" }
    local pane = start()
    addNames(1)
    equal(M.macros[1].body, "/say hello")
    equal(M.macros[121].body, "/dance")
    local index = pane.rows[1].find.attributes.macro
    local name = GetMacroInfo(index)
    equal(name == "WP_Target1", false)
    EditMacro(index, nil, nil, "/say kept")
    equal(pane.rows[1].find.enabled, false)
    local clicks = #M.calls
    M.Click(pane.rows[1].find)
    equal(#M.calls, clicks)
    SlashCmdList.WANTEDPOSTER()
    M.Open()
    M.Click(pane.rows[1].find)
    equal(lastMacro(), "/tar 暮刃 枫影")
    equal(select(3, GetMacroInfo(GetMacroIndexByName(name))), "/say kept")
end

function TEST.macro_editor_pause_and_resume()
    local pane = start()
    local editor = CreateFrame("Frame", "MacroFrame", UIParent)
    addNames(2)
    equal(pane.searchPage.enabled, false)
    equal(pane.status.text, "关闭游戏宏窗口后更新查找。")
    editor:Hide()
    M.Tick()
    M.Click(pane.searchPage)
    equal(lastMacro(), "/tar 暮刃 枫影\n/tar 踏雪 银松")
end

function TEST.existing_character_macros_bind_without_a_registry()
    local db = M.Load({ groups = {{ names = { "暮刃 枫影", "踏雪 银松" } }} }, false, true)
    M.missCharacterMacroNames = true
    M.macros[1] = { name = "WP_Target6", body = "/say unrelated" }
    M.macros[121] = { name = "WP_Target1", body = "/tar 暮刃 枫影" }
    M.macros[122] = { name = "WP_Target2", body = "/tar 踏雪 银松" }
    M.macros[123] = { name = "WP_Target6", body = "/tar 暮刃 枫影\r\n/tar 踏雪 银松\n" }
    local editor = CreateFrame("Frame", "MacroFrame", UIParent)
    local pane = M.Open()
    equal(pane.searchPage.enabled, true)
    equal(pane.rows[1].find.enabled, true)
    M.Click(pane.searchPage)
    equal(lastMacro(), M.macros[123].body)
    M.Click(pane.rows[1].find)
    equal(lastMacro(), M.macros[121].body)
    editor:Hide()
    M.Tick()
    equal(pane.searchPage.enabled, true)
    equal(pane.status.text, "本组共 2 人")
    equal(next(db.macros), nil)
    equal(M.macros[124], nil)
end

function TEST.macro_readback_can_finish_after_creation()
    local pane = start()
    local readNow = false
    local readMacro = GetMacroInfo
    GetMacroInfo = function(index)
        if not readNow then return nil end
        return readMacro(index)
    end
    M.Paste("暮刃 枫影")
    equal(pane.status.text, "正在同步查找宏。")
    equal(pane.searchPage.enabled, false)
    readNow = true
    M.Tick()
    equal(pane.searchPage.enabled, true)
    equal(pane.rows[1].find.enabled, true)
    M.Click(pane.searchPage)
    equal(lastMacro(), "/tar 暮刃 枫影")
    local _, character = GetNumMacros()
    equal(character, 2)
end

function TEST.full_macro_bank_keeps_roster_and_safe_search()
    M.macroLimit = 1
    local pane, db = start()
    addNames(3)
    equal(#db.groups[1].names, 3)
    equal(pane.rows[1].find.enabled, false)
    M.Click(pane.searchPage)
    equal(lastMacro(), "/tar 暮刃 枫影\n/tar 踏雪 银松\n/tar 深潮 暮羽")
    M.macroLimit = 18
    SlashCmdList.WANTEDPOSTER()
    M.Open()
    M.Click(pane.rows[1].find)
    equal(lastMacro(), "/tar 暮刃 枫影")
end
