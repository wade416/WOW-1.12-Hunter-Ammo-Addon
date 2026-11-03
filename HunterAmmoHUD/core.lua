--------------------------------------------------------------------
-- HunterAmmoHUD - core.lua
-- 猎人弹药统计核心
--   剩余弹药 / 堆叠数 / 消耗速率 / 剩余时间预估 / 低弹药预警
-- 主数据源: GetInventoryItemCount('player', 0)
--   （1.12 客户端自身对弹药槽的计数，与远程攻击按钮显示的弹药数一致）
-- 兜底数据源: 扫描背包中的弹药（equipLoc == INVTYPE_AMMO 或名称含 箭/弹）
--------------------------------------------------------------------

HAH = HAH or {}

HAH.state = {
	count = 0,        -- 剩余弹药数
	stacks = 0,       -- 堆叠组数（背包实存，仅参考）
	groups = 0,       -- 弹药组数（每200发一组）
	remainder = 0,    -- 满组后剩余的发数
	texture = nil,    -- 弹药图标
	name = nil,       -- 弹药名
	total_bag = 0,    -- 背包扫描总量（兜底用）
	rate = 0,         -- 消耗速率（发/秒）
	eta = nil,        -- 预计剩余时间（秒）
	max_seen = 0,     -- 本次登录后看到的最大弹药数（量条参考）
	last_count = 0,
	last_time = 0,
	window_shots = 0, -- 统计窗口内消耗
	window_start = 0,
	warned = false,
}

function HAH.IsHunter()
	local c1, c2 = UnitClass('player')
	return c1 == 'HUNTER' or c1 == '猎人' or c2 == 'HUNTER' or c2 == '猎人'
end

-- 根据远程武器判定所需弹药类型：弓/弩→箭，枪→弹
local function ammo_kind()
	local link = GetInventoryItemLink('player', 18)
	if not link then return nil end
	local _, _, _, _, _, subclass = GetItemInfo(link)
	subclass = subclass or ''
	if strfind(subclass, '弓') or strfind(subclass, '弩')
		or strfind(subclass, 'Bow') or strfind(subclass, 'Crossbow') then
		return '箭'
	elseif strfind(subclass, '枪') or strfind(subclass, 'Gun') then
		return '弹'
	end
	return nil
end

local function is_ammo_link(link)
	local name, _, _, _, class, _, _, equipLoc = GetItemInfo(link)
	-- 唯一权威判定：装备位置为弹药槽（不会误判箭袋/弹药袋等容器）
	if equipLoc == 'INVTYPE_AMMO' then
		return true, name
	end
	-- 备用判定：物品类别为"抛射物"（Projectile）
	if class == '抛射物' or class == 'Projectile' then
		return true, name
	end
	return false, name
end

-- 扫描背包弹药：返回 纹理, 名称, 堆叠组数, 总数量
--   want_texture  当前弹药图标（优先按图标精确匹配同类型弹药）
--   kind          弹药类型关键字（'箭' / '弹'，作为次级过滤）
function HAH.scan_ammo(kind, want_texture)
	local stacks, total, texture, name = 0, 0, nil, nil
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local ok, aname = is_ammo_link(link)
				if ok then
					local tex, count = GetContainerItemInfo(bag, slot)
					count = count or 1
					local match
					if want_texture and tex then
						match = (tex == want_texture)
					elseif kind and aname then
						match = strfind(aname, kind, 1, 1) ~= nil
					else
						match = true
					end
					if match then
						total = total + count
						stacks = stacks + 1
						if not texture then
							texture = tex
							name = aname
						end
					end
				end
			end
		end
	end
	return texture, name, stacks, total
end

-- 背包扫描（事件驱动：拾取/使用/换装时调用）
function HAH.refresh_info()
	local s = HAH.state
	-- 当前弹药图标（客户端弹药槽记录的弹药类型，可能为 nil）
	local want_tex
	if GetInventoryItemTexture then
		local ok, tex = pcall(GetInventoryItemTexture, 'player', 0)
		if ok and tex and tex ~= '' then
			want_tex = tex
		end
	end
	local tex, name, stacks, total = HAH.scan_ammo(ammo_kind(), want_tex)
	if stacks == 0 then
		-- 图标对不上（弹药类型变化等），退回按类型关键字
		tex, name, stacks, total = HAH.scan_ammo(ammo_kind(), nil)
	end
	if stacks == 0 then
		-- 仍找不到则按全部弹药统计
		tex, name, stacks, total = HAH.scan_ammo(nil, nil)
	end
	if tex then s.texture = tex end
	if name then s.name = name end
	s.stacks = stacks
	s.total_bag = total
end

--------------------------------------------------------------------
-- 初始化与事件
--------------------------------------------------------------------

local function init_db()
	if not HunterAmmoHUDDB then HunterAmmoHUDDB = {} end
	local db = HunterAmmoHUDDB
	if db.locked == nil then db.locked = false end
	if db.warn == nil then db.warn = 200 end       -- 低弹药阈值（发）
	if db.scale == nil then db.scale = 1 end
	if db.sound == nil then db.sound = true end
	if db.force == nil then db.force = false end   -- 非猎人强制显示（调试）
	HAH.db = db
end

--------------------------------------------------------------------
-- 主统计 tick（ui.lua 的 OnUpdate 每 0.5 秒驱动一次，事件也会触发）
--------------------------------------------------------------------

function HAH.tick()
	if not HAH.db then return end
	local s = HAH.state
	local now = GetTime()

	local prim = GetInventoryItemCount('player', 0) or 0
	local count = prim
	if count <= 0 then
		count = s.total_bag
	end
	if count < 0 then count = 0 end

	if count > s.max_seen then
		s.max_seen = count
	end

	-- 消耗速率（30秒统计窗口）
	if s.last_time > 0 and now > s.last_time then
		if count < s.last_count then
			s.window_shots = s.window_shots + (s.last_count - count)
		elseif count > s.last_count then
			-- 补弹：重置统计窗口
			s.window_shots = 0
			s.window_start = now
		end
	end
	if s.window_start == 0 then s.window_start = now end
	local elapsed = now - s.window_start
	if elapsed >= 30 then
		s.rate = s.window_shots / elapsed
		s.window_shots = 0
		s.window_start = now
	end

	s.count = count
	-- 组数：每 200 发为一组
	s.groups = floor(count / 200)
	s.remainder = count - s.groups * 200
	s.last_count = count
	s.last_time = now
	s.eta = (s.rate > 0.02 and count > 0) and (count / s.rate) or nil

	-- 低弹药预警（每次跌破阈值提醒一次）
	local warn_at = HAH.db.warn
	if warn_at and warn_at > 0 and count > 0 and count <= warn_at then
		if not s.warned then
			s.warned = true
			if HAH.db.sound then
				pcall(PlaySound, 'ig_mainmenu_button_click')
			end
			if DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage('|cff33ffcc<弹药>|r |cffff3333弹药不足！|r 剩余 ' .. count .. ' 发')
			end
		end
	else
		s.warned = false
	end

	if HAH.on_update then HAH.on_update() end
end

local ev = CreateFrame('Frame')
ev:RegisterEvent('VARIABLES_LOADED')
ev:RegisterEvent('PLAYER_LOGIN')
ev:RegisterEvent('PLAYER_ENTERING_WORLD')
ev:RegisterEvent('BAG_UPDATE')
ev:RegisterEvent('UNIT_INVENTORY_CHANGED')
ev:RegisterEvent('PLAYER_EQUIPMENT_CHANGED')
ev:SetScript('OnEvent', function()
	if event == 'VARIABLES_LOADED' then
		init_db()
	elseif event == 'PLAYER_LOGIN' or event == 'PLAYER_ENTERING_WORLD' then
		if HAH.db then
			HAH.refresh_info()
			HAH.tick()
		end
	elseif event == 'BAG_UPDATE' then
		if HAH.db then
			HAH.refresh_info()
			HAH.tick()
		end
	elseif event == 'UNIT_INVENTORY_CHANGED' then
		if HAH.db and (arg1 == nil or arg1 == 'player') then
			HAH.refresh_info()
			HAH.tick()
		end
	elseif event == 'PLAYER_EQUIPMENT_CHANGED' then
		if HAH.db then
			HAH.refresh_info()
			HAH.tick()
		end
	end
end)
