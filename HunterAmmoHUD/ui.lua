--------------------------------------------------------------------
-- HunterAmmoHUD - ui.lua
-- 科技感 HUD：霓虹边框 / 角标 / 网格 / 扫描线 / 分段量条 / 脉冲预警
--------------------------------------------------------------------

local FONT = [[Fonts\ARIALN.TTF]]
local W, H = 244, 100
local BAR_W = 216

local f, icon, icon_frame, num_fs, unit_fs, info_fs, fill, dot, low_fs, scanline
local tick_tex = {}
local next_tick = 0
local scan_offset = 0

--------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------

local function comma(n)
	local s = tostring(n or 0)
	local out = ''
	while strlen(s) > 3 do
		out = ',' .. strsub(s, -3) .. out
		s = strsub(s, 1, -4)
	end
	return s .. out
end

local function fmt_time(sec)
	sec = floor((sec or 0) + 0.5)
	local m = floor(sec / 60)
	local s = mod(sec, 60)
	if m >= 60 then
		local h = floor(m / 60)
		return h .. ':' .. string.format('%02d', mod(m, 60)) .. ':' .. string.format('%02d', s)
	end
	return string.format('%02d:%02d', m, s)
end

local function save_pos()
	pcall(function()
		local p, rt, rp, x, y = f:GetPoint(1)
		HAH.db.pos = { p = p, rp = rp, x = x, y = y }
	end)
end

--------------------------------------------------------------------
-- 创建 HUD
--------------------------------------------------------------------

local function create()
	f = CreateFrame('Frame', 'HunterAmmoHUDFrame', UIParent)
	f:SetWidth(W)
	f:SetHeight(H)
	f:SetFrameStrata('MEDIUM')
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag('LeftButton')
	f:SetBackdrop({
		bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
		edgeSize = 10,
		tile = true,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0.015, 0.04, 0.055, 0.84)
	f:SetBackdropBorderColor(0.1, 0.85, 0.95, 0.85)
	f:SetScript('OnDragStart', function()
		if HAH.db and not HAH.db.locked then
			this:StartMoving()
		end
	end)
	f:SetScript('OnDragStop', function()
		this:StopMovingOrSizing()
		save_pos()
	end)

	-- 恢复位置
	if HAH.db.pos then
		f:SetPoint(HAH.db.pos.p or 'CENTER', UIParent, HAH.db.pos.rp or 'CENTER', HAH.db.pos.x or 0, HAH.db.pos.y or 0)
	else
		f:SetPoint('TOP', UIParent, 'TOP', 0, -170)
	end
	f:SetScale(HAH.db.scale or 1)

	-- 科技网格（竖线）
	for i = 1, 7 do
		local line = f:CreateTexture(nil, 'BACKGROUND')
		line:SetTexture(0.2, 0.9, 1, 0.05)
		line:SetWidth(1)
		line:SetHeight(H - 8)
		line:SetPoint('TOPLEFT', f, 'TOPLEFT', i * 30, -4)
	end

	-- 四角角标
	local corners = {
		{ 'TOPLEFT', 1, 1 }, { 'TOPRIGHT', -1, 1 },
		{ 'BOTTOMLEFT', 1, -1 }, { 'BOTTOMRIGHT', -1, -1 },
	}
	for _, c in ipairs(corners) do
		local point, sx, sy = c[1], c[2], c[3]
		local hline = f:CreateTexture(nil, 'OVERLAY')
		hline:SetTexture(0.2, 1, 1, 0.9)
		hline:SetWidth(14)
		hline:SetHeight(1)
		local vline = f:CreateTexture(nil, 'OVERLAY')
		vline:SetTexture(0.2, 1, 1, 0.9)
		vline:SetWidth(1)
		vline:SetHeight(14)
		hline:SetPoint(point, f, point, 0, 0)
		vline:SetPoint(point, f, point, 0, 0)
	end

	-- 标题
	local title = f:CreateFontString(nil, 'OVERLAY')
	title:SetFont(FONT, 13)
	title:SetText('AMMO')
	title:SetTextColor(0.2, 1, 1, 0.95)
	title:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, -7)

	-- 低弹药标识（默认隐藏）
	low_fs = f:CreateFontString(nil, 'OVERLAY')
	low_fs:SetFont(FONT, 11)
	low_fs:SetText('LOW!')
	low_fs:SetTextColor(1, 0.3, 0.2, 1)
	low_fs:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -26, -8)
	low_fs:Hide()

	-- 状态点（脉冲）
	dot = f:CreateTexture(nil, 'OVERLAY')
	dot:SetTexture(0.35, 1, 0.5, 1)
	dot:SetWidth(6)
	dot:SetHeight(6)
	dot:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -14, -11)

	-- 图标与图标框
	icon_frame = f:CreateTexture(nil, 'ARTWORK')
	icon_frame:SetTexture(0.1, 0.9, 1, 0.25)
	icon_frame:SetWidth(30)
	icon_frame:SetHeight(30)
	icon_frame:SetPoint('TOPLEFT', f, 'TOPLEFT', 10, -24)
	icon = f:CreateTexture(nil, 'ARTWORK')
	icon:SetTexture([[Interface\Icons\INV_Ammo_Arrow_02]])
	icon:SetWidth(26)
	icon:SetHeight(26)
	icon:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, -26)

	-- 大数字
	num_fs = f:CreateFontString(nil, 'OVERLAY')
	num_fs:SetFont(FONT, 24)
	num_fs:SetJustifyH('LEFT')
	num_fs:SetText('0')
	num_fs:SetTextColor(0.4, 1, 0.5, 1)
	num_fs:SetPoint('TOPLEFT', f, 'TOPLEFT', 52, -26)
	num_fs:SetWidth(130)
	num_fs:SetHeight(26)

	-- 单位
	unit_fs = f:CreateFontString(nil, 'OVERLAY')
	unit_fs:SetFont(FONT, 11)
	unit_fs:SetText('发')
	unit_fs:SetTextColor(0.5, 0.8, 0.85, 0.9)
	unit_fs:SetPoint('TOPLEFT', f, 'TOPLEFT', 186, -40)

	-- 量条
	local bar = CreateFrame('Frame', nil, f)
	bar:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, -66)
	bar:SetWidth(BAR_W)
	bar:SetHeight(9)
	local bar_bg = bar:CreateTexture(nil, 'BACKGROUND')
	bar_bg:SetAllPoints()
	bar_bg:SetTexture(0.02, 0.1, 0.12, 0.95)
	fill = bar:CreateTexture(nil, 'ARTWORK')
	fill:SetPoint('TOPLEFT', bar, 'TOPLEFT', 0, 0)
	fill:SetWidth(2)
	fill:SetHeight(9)
	fill:SetTexture(0.25, 1, 0.55, 0.85)
	-- 分段刻度
	for i = 1, 17 do
		local tick = bar:CreateTexture(nil, 'OVERLAY')
		tick:SetTexture(0.02, 0.06, 0.08, 0.9)
		tick:SetWidth(1)
		tick:SetHeight(9)
		tick:SetPoint('TOPLEFT', bar, 'TOPLEFT', i * 12, 0)
		tinsert(tick_tex, tick)
	end

	-- 信息行
	info_fs = f:CreateFontString(nil, 'OVERLAY')
	info_fs:SetFont(FONT, 11)
	info_fs:SetText('x0组   0.00/s   ETA --:--')
	info_fs:SetTextColor(0.45, 0.85, 0.9, 1)
	info_fs:SetPoint('TOPLEFT', f, 'TOPLEFT', 12, -81)

	-- 扫描线
	scanline = f:CreateTexture(nil, 'ARTWORK')
	scanline:SetTexture(0.3, 1, 1, 0.05)
	scanline:SetWidth(BAR_W)
	scanline:SetHeight(2)
	scanline:SetPoint('TOPLEFT', f, 'TOPLEFT', 14, -20)
end

--------------------------------------------------------------------
-- 显示更新
--------------------------------------------------------------------

local function update_display()
	local s = HAH.state
	local db = HAH.db
	local t = GetTime()

	local low = db.warn and db.warn > 0 and s.count > 0 and s.count <= db.warn
	local pulse = 0.65 + 0.35 * abs(sin(t * 5))

	-- 图标
	if s.texture then
		icon:SetTexture(s.texture)
	else
		icon:SetTexture([[Interface\Icons\INV_Ammo_Arrow_02]])
	end

	-- 大数字
	num_fs:SetText(comma(s.count))
	if low then
		num_fs:SetTextColor(1, 0.3, 0.25, pulse)
		f:SetBackdropBorderColor(1, 0.2, 0.2, 0.5 + 0.4 * pulse)
		dot:SetTexture(1, 0.25, 0.2, pulse)
		low_fs:Show()
	else
		num_fs:SetTextColor(0.4, 1, 0.5, 1)
		f:SetBackdropBorderColor(0.1, 0.85, 0.95, 0.85)
		dot:SetTexture(0.35, 1, 0.5, 0.5 + 0.5 * abs(sin(t * 2)))
		low_fs:Hide()
	end

	-- 量条
	local ratio = 0
	if s.max_seen and s.max_seen > 1 then
		ratio = s.count / s.max_seen
	end
	if ratio > 1 then ratio = 1 end
	if ratio < 0 then ratio = 0 end
	local w = floor(BAR_W * ratio)
	if w < 2 then w = 2 end
	fill:SetWidth(w)
	if ratio > 0.5 then
		fill:SetTexture(0.25, 1, 0.55, 0.85)
	elseif ratio > 0.2 then
		fill:SetTexture(1, 0.85, 0.2, 0.85)
	else
		fill:SetTexture(1, 0.3, 0.2, 0.85)
	end

	-- 信息行：组数（每200发一组）+ 速率 + 预计剩余
	local rate_txt = string.format('%.2f', s.rate or 0)
	local eta_txt = s.eta and ('ETA ' .. fmt_time(s.eta)) or 'ETA --:--'
	local group_txt = 'x' .. (s.groups or 0) .. '组'
	if (s.remainder or 0) > 0 then
		group_txt = group_txt .. '+' .. s.remainder
	end
	info_fs:SetText(group_txt .. '   ' .. rate_txt .. '/s   ' .. eta_txt)

end

--------------------------------------------------------------------
-- 主循环
--------------------------------------------------------------------

local loop = CreateFrame('Frame')
loop:SetScript('OnUpdate', function()
	if not (f and HAH.db) then return end
	local t = GetTime()
	if t >= next_tick then
		next_tick = t + 0.5
		HAH.tick()
		update_display()
	else
		-- 平滑扫描线
		scan_offset = scan_offset + 1.6
		if scan_offset > (H - 34) then
			scan_offset = 0
		end
		scanline:SetPoint('TOPLEFT', f, 'TOPLEFT', 14, -20 - scan_offset)
	end
end)

--------------------------------------------------------------------
-- 可见性与鼠标（锁定后点击穿透）
--------------------------------------------------------------------

local function apply_visible()
	if not f then return end
	if HAH.db.force or HAH.IsHunter() then
		f:Show()
	else
		f:Hide()
	end
end

local function apply_mouse()
	if not f then return end
	if HAH.db.locked then
		f:EnableMouse(false)
	else
		f:EnableMouse(true)
	end
end

--------------------------------------------------------------------
-- 斜杠命令
--------------------------------------------------------------------

SLASH_HAH1 = '/ammo'
SLASH_HAH2 = '/弹药'
SlashCmdList['HAH'] = function(msg)
	if not HAH.db then return end
	if not f then return end
	local _, _, cmd, rest = strfind(strlower(msg or ''), '^(%S*)%s*(.*)$')
	cmd = cmd or ''
	rest = rest or ''
	local db = HAH.db
	if cmd == 'lock' then
		db.locked = not db.locked
		apply_mouse()
		print('|cff33ffcc<弹药>|r 锁定: ' .. (db.locked and '|cff33ff33开|r' or '|cffff5555关|r'))
	elseif cmd == 'warn' then
		local v = tonumber(rest)
		if v and v >= 0 then
			db.warn = floor(v)
			print('|cff33ffcc<弹药>|r 低弹药阈值: ' .. v .. ' 发')
		else
			print('|cff33ffcc<弹药>|r 用法: /ammo warn 200')
		end
	elseif cmd == 'scale' then
		local v = tonumber(rest)
		if v then
			if v < 0.5 then v = 0.5 end
			if v > 2 then v = 2 end
			db.scale = v
			f:SetScale(v)
			print('|cff33ffcc<弹药>|r 缩放: ' .. v)
		else
			print('|cff33ffcc<弹药>|r 用法: /ammo scale 1.2')
		end
	elseif cmd == 'sound' then
		db.sound = not db.sound
		print('|cff33ffcc<弹药>|r 预警音: ' .. (db.sound and '开' or '关'))
	elseif cmd == 'test' then
		db.force = not db.force
		apply_visible()
		print('|cff33ffcc<弹药>|r 强制显示: ' .. (db.force and '开' or '关'))
	elseif cmd == 'reset' then
		db.pos = nil
		f:ClearAllPoints()
		f:SetPoint('TOP', UIParent, 'TOP', 0, -170)
		print('|cff33ffcc<弹药>|r 位置已重置')
	else
		print('|cff33ffcc<弹药>|r 命令:')
		print('  |cffffff00/ammo lock|r 锁定/解锁(锁定后点击穿透)')
		print('  |cffffff00/ammo warn 200|r 低弹药阈值(发)')
		print('  |cffffff00/ammo scale 1.2|r 缩放 0.5~2')
		print('  |cffffff00/ammo sound|r 预警音开关')
		print('  |cffffff00/ammo test|r 非猎人强制显示')
		print('  |cffffff00/ammo reset|r 重置位置')
	end
end

--------------------------------------------------------------------
-- 初始化
--------------------------------------------------------------------

local init = CreateFrame('Frame')
init:RegisterEvent('PLAYER_LOGIN')
init:RegisterEvent('PLAYER_ENTERING_WORLD')
init:SetScript('OnEvent', function()
	if not HAH.db then return end
	if not f then
		create()
	end
	apply_visible()
	apply_mouse()
	HAH.refresh_info()
	HAH.tick()
	update_display()
end)
