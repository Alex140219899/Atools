---@diagnostic disable: undefined-global, lowercase-global
--[[
  Tools Menu — MoonLoader / SAMP
  /tools — меню в стиле modern cheat UI (sidebar + subtabs + 2 columns)
  Данные: moonloader/Tools/
]]

script_name("Tools Menu")
script_description("Tools: /tools — меню с кастомизацией и обновлением с GitHub")
script_author("Alex140219899")
script_version("1.0.1")

require("lib.moonloader")
require("encoding").default = "CP1251"
local u8 = require("encoding").UTF8
local ffi = require("ffi")
local imgui = require("mimgui")

pcall(require, "dkjson")

local sizeX, sizeY = getScreenResolution()
local worked_dir = getWorkingDirectory():gsub("\\", "/")
local SCRIPT_VERSION_TEXT = "1.0.1"
local DATA_DIR_NAME = "Tools"
local message_color = 0x009EFF

local UPDATE_MANIFEST_URL = "https://raw.githubusercontent.com/Alex140219899/Atools/main/ToolsUpdate.json"
local UPDATE_MANIFEST_URL_JS = "https://cdn.jsdelivr.net/gh/Alex140219899/Atools@main/ToolsUpdate.json"
local UPDATE_SCRIPT_URL_JS = "https://cdn.jsdelivr.net/gh/Alex140219899/Atools@main/Tools.lua"
local SETTINGS_DEFAULT_URL = "https://raw.githubusercontent.com/Alex140219899/Atools/main/Tools/SettingsDefault.json"
local SETTINGS_DEFAULT_URL_JS = "https://cdn.jsdelivr.net/gh/Alex140219899/Atools@main/Tools/SettingsDefault.json"

local function im_utf8(s)
	return s == nil and "" or tostring(s)
end

local function chat_utf8(text)
	local ok, r = pcall(function()
		return u8:decode(tostring(text or ""))
	end)
	return (ok and type(r) == "string") and r or tostring(text or "")
end

local function sampChat(text)
	sampAddChatMessage(chat_utf8(text), message_color)
end

local function log_msg(text)
	print(chat_utf8(text))
end

local function get_data_dir()
	return (worked_dir .. "/" .. DATA_DIR_NAME):gsub("\\", "/")
end

local configDirectory = get_data_dir()
local path_settings = configDirectory .. "/Settings.json"

local default_settings = {
	general = {
		version = SCRIPT_VERSION_TEXT,
		installed = false,
		data_version = "0",
		custom_dpi = 1.0,
		accent_r = 0.35,
		accent_g = 0.55,
		accent_b = 1.0,
		window_alpha = 0.98,
		rounded_ui = true,
		dark_theme = true,
	},
	windows_pos = {
		main_menu = { x = 0, y = 0 },
	},
}

local settings = {}
local custom_dpi = 1.0
local data_dir_ready = false
local needs_install = false
local last_manifest_cache = nil
local theme_applied = false

local Menu = {
	Window = imgui.new.bool(),
	InstallWindow = imgui.new.bool(),
	UpdateWindow = imgui.new.bool(),
	sidebar = 0,
	subtab = 0,
}

local UpdateUi = {
	busy = false,
	need_script = false,
	remote_script_ver = "",
	changelog = "",
	script_url = "",
	pending_check = false,
	pending_update = false,
	pending_install = false,
	status_text = "",
	install_status = "",
}

local updateVer = ""
local updateInfoText = ""

local accent_col = imgui.new.float[3](0.35, 0.55, 1.0)
local slider_alpha = imgui.new.float(0.98)
local checkbox_rounded = imgui.new.bool(true)
local checkbox_dark = imgui.new.bool(true)
local slider_dpi = imgui.new.float(1.0)

--- Демо-виджеты (заглушки под будущий функционал)
local Demo = {
	godmode = imgui.new.bool(false),
	no_ragdoll = imgui.new.bool(false),
	seat_belt = imgui.new.bool(false),
	health_val = imgui.new.int(100),
	armor_val = imgui.new.int(100),
	health_cb = imgui.new.bool(false),
	speedhack = imgui.new.bool(false),
	noclip = imgui.new.bool(false),
	super_jump = imgui.new.bool(false),
	freeze_pos = imgui.new.bool(false),
	esp_player = imgui.new.bool(false),
	esp_vehicle = imgui.new.bool(false),
	esp_health = imgui.new.bool(false),
	esp_box = imgui.new.bool(false),
	esp_gun = imgui.new.bool(false),
	col_player = imgui.new.float[3](0.35, 0.55, 1.0),
	col_vehicle = imgui.new.float[3](1.0, 0.85, 0.2),
	col_health = imgui.new.float[3](1.0, 0.35, 0.65),
	col_box = imgui.new.float[3](0.2, 0.9, 1.0),
	col_gun = imgui.new.float[3](0.3, 1.0, 0.45),
}

local SIDEBAR = {
	{ id = "aimbot", label = "Aimbot", page = 0 },
	{ id = "visuals", label = "Visuals", page = 1 },
	{ id = "trigger", label = "Trigger", page = 2 },
	{ id = "user", label = "User", page = 3 },
	{ id = "pools", label = "Pools", page = 4 },
	{ id = "world", label = "World", page = 5 },
	{ id = "misc", label = "Misc", page = 6 },
	{ id = "script", label = "Script", page = 7 },
}

local SUBTABS = { "Subtab One", "Subtab Two", "Subtab Three" }

local function ensure_data_dir()
	if data_dir_ready then
		return
	end
	data_dir_ready = true
	pcall(createDirectory, configDirectory)
end

local function decode_json_str(txt)
	if type(txt) ~= "string" or txt == "" then
		return nil
	end
	local ok, data = pcall(decodeJson, txt)
	return (ok and type(data) == "table") and data or nil
end

local function read_json_file(path)
	if not doesFileExist(path) then
		return nil
	end
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local txt = f:read("*a") or ""
	f:close()
	return decode_json_str(txt)
end

local function write_json_file(path, tbl)
	local ok_json, encoded = pcall(encodeJson, tbl)
	if not ok_json or type(encoded) ~= "string" then
		return false
	end
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(encoded)
	f:close()
	return true
end

local function merge_defaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			merge_defaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function save_settings()
	ensure_data_dir()
	write_json_file(path_settings, settings)
end

local function get_local_script_version()
	if thisScript and thisScript().version and tostring(thisScript().version) ~= "" then
		return tostring(thisScript().version):match("^%s*(.-)%s*$") or SCRIPT_VERSION_TEXT
	end
	return SCRIPT_VERSION_TEXT
end

local function load_settings()
	ensure_data_dir()
	if not doesFileExist(path_settings) then
		settings = {}
		merge_defaults(settings, default_settings)
		needs_install = true
		log_msg("[Tools] Settings.json не найден — требуется установка.")
		return
	end
	local loaded = read_json_file(path_settings)
	if not loaded then
		settings = {}
		merge_defaults(settings, default_settings)
		needs_install = true
		log_msg("[Tools] Не удалось прочитать Settings.json — требуется установка.")
		return
	end
	settings = loaded
	merge_defaults(settings, default_settings)
	if not settings.general.installed then
		needs_install = true
	end
	custom_dpi = tonumber(settings.general.custom_dpi) or 1.0
end

local function sync_customization_bufs()
	accent_col[0] = tonumber(settings.general.accent_r) or 0.35
	accent_col[1] = tonumber(settings.general.accent_g) or 0.55
	accent_col[2] = tonumber(settings.general.accent_b) or 1.0
	slider_alpha[0] = tonumber(settings.general.window_alpha) or 0.98
	checkbox_rounded[0] = settings.general.rounded_ui ~= false
	checkbox_dark[0] = settings.general.dark_theme ~= false
	slider_dpi[0] = custom_dpi
end

local function apply_customization_from_bufs()
	settings.general.accent_r = accent_col[0]
	settings.general.accent_g = accent_col[1]
	settings.general.accent_b = accent_col[2]
	settings.general.window_alpha = slider_alpha[0]
	settings.general.rounded_ui = checkbox_rounded[0]
	settings.general.dark_theme = checkbox_dark[0]
	settings.general.custom_dpi = slider_dpi[0]
	custom_dpi = slider_dpi[0]
	save_settings()
end

local function accent(a)
	a = a or 1.0
	return imgui.ImVec4(accent_col[0], accent_col[1], accent_col[2], a)
end

local function apply_theme_core()
	local dark = checkbox_dark[0]
	local a = slider_alpha[0]
	local dpi = custom_dpi
	local s = imgui.GetStyle()
	local round = checkbox_rounded[0] and (10 * dpi) or 0

	s.WindowPadding = imgui.ImVec2(0, 0)
	s.FramePadding = imgui.ImVec2(8 * dpi, 5 * dpi)
	s.ItemSpacing = imgui.ImVec2(8 * dpi, 7 * dpi)
	s.ItemInnerSpacing = imgui.ImVec2(6 * dpi, 4 * dpi)
	s.ScrollbarSize = 8 * dpi
	s.WindowRounding = round
	s.ChildRounding = round > 0 and (8 * dpi) or 0
	s.FrameRounding = round > 0 and (6 * dpi) or 0
	s.GrabRounding = round > 0 and (12 * dpi) or 0
	s.PopupRounding = round
	s.TabRounding = 0

	local bg = dark and imgui.ImVec4(0.07, 0.075, 0.085, a) or imgui.ImVec4(0.96, 0.965, 0.97, a)
	local child = dark and imgui.ImVec4(0.09, 0.095, 0.105, a) or imgui.ImVec4(0.99, 0.99, 1.0, a)
	local sidebar = dark and imgui.ImVec4(0.055, 0.06, 0.07, a) or imgui.ImVec4(0.94, 0.945, 0.95, a)
	local frame = dark and imgui.ImVec4(0.12, 0.125, 0.14, a) or imgui.ImVec4(0.88, 0.89, 0.91, a)
	local text = dark and imgui.ImVec4(0.93, 0.94, 0.96, 1.0) or imgui.ImVec4(0.12, 0.13, 0.15, 1.0)
	local text_dim = dark and imgui.ImVec4(0.5, 0.52, 0.56, 1.0) or imgui.ImVec4(0.45, 0.47, 0.5, 1.0)

	s.Colors[imgui.Col.Text] = text
	s.Colors[imgui.Col.TextDisabled] = text_dim
	s.Colors[imgui.Col.WindowBg] = bg
	s.Colors[imgui.Col.ChildBg] = child
	s.Colors[imgui.Col.PopupBg] = child
	s.Colors[imgui.Col.Border] = dark and imgui.ImVec4(0.16, 0.17, 0.2, 0.55) or imgui.ImVec4(0.82, 0.84, 0.87, 0.8)
	s.Colors[imgui.Col.FrameBg] = frame
	s.Colors[imgui.Col.FrameBgHovered] = dark and imgui.ImVec4(0.16, 0.17, 0.2, a) or imgui.ImVec4(0.84, 0.86, 0.89, a)
	s.Colors[imgui.Col.FrameBgActive] = dark and imgui.ImVec4(0.18, 0.19, 0.23, a) or imgui.ImVec4(0.8, 0.82, 0.86, a)
	s.Colors[imgui.Col.Button] = frame
	s.Colors[imgui.Col.ButtonHovered] = accent(0.35)
	s.Colors[imgui.Col.ButtonActive] = accent(0.55)
	s.Colors[imgui.Col.Header] = accent(0.18)
	s.Colors[imgui.Col.HeaderHovered] = accent(0.28)
	s.Colors[imgui.Col.HeaderActive] = accent(0.38)
	s.Colors[imgui.Col.Separator] = dark and imgui.ImVec4(0.2, 0.21, 0.24, 0.7) or imgui.ImVec4(0.85, 0.86, 0.88, 0.9)
	s.Colors[imgui.Col.CheckMark] = accent(1.0)
	s.Colors[imgui.Col.SliderGrab] = accent(0.95)
	s.Colors[imgui.Col.SliderGrabActive] = accent(1.0)
	s.Colors[imgui.Col.Tab] = imgui.ImVec4(0, 0, 0, 0)
	s.Colors[imgui.Col.TabHovered] = accent(0.2)
	s.Colors[imgui.Col.TabActive] = imgui.ImVec4(0, 0, 0, 0)
	s.Colors[imgui.Col.ModalWindowDimBg] = imgui.ImVec4(0, 0, 0, 0.55)

	Menu._sidebar_col = sidebar
end

local function ensure_theme_once()
	if not theme_applied then
		theme_applied = true
		pcall(function()
			imgui.SwitchContext()
		end)
	end
	apply_theme_core()
end

local function vig_compare_versions(a, b)
	local pa, pb = {}, {}
	for n in tostring(a):gmatch("%d+") do
		pa[#pa + 1] = tonumber(n) or 0
	end
	for n in tostring(b):gmatch("%d+") do
		pb[#pb + 1] = tonumber(n) or 0
	end
	local n = math.max(#pa, #pb)
	for i = 1, n do
		local va, vb = pa[i] or 0, pb[i] or 0
		if va ~= vb then
			return va > vb and 1 or -1
		end
	end
	return 0
end

local function download_url_to_file_sync(dest, url, timeout_sec)
	if type(downloadUrlToFile) ~= "function" then
		return false, "downloadUrlToFile недоступна"
	end
	local ml = package.loaded["moonloader"] or require("moonloader")
	local st = ml and ml.download_status
	if not st then
		return false, "download_status недоступен"
	end
	local done, ok = false, false
	pcall(function()
		downloadUrlToFile(url, dest, function(_id, status)
			if status == st.STATUS_ENDDOWNLOADDATA or tonumber(status) == 6 then
				ok = true
				done = true
			elseif st.STATUS_ENDDOWNLOADERR and status == st.STATUS_ENDDOWNLOADERR then
				done = true
			end
		end)
	end)
	local n, lim = 0, math.floor((timeout_sec or 30) * 10)
	while not done and n < lim do
		wait(100)
		n = n + 1
	end
	if not done then
		pcall(os.remove, dest)
		return false, "таймаут"
	end
	return ok and doesFileExist(dest), ok and "ok" or "ошибка загрузки"
end

local function url_cache_bust(u)
	u = tostring(u or "")
	if u == "" then
		return u
	end
	return u .. (u:find("?", 1, true) and "&" or "?") .. "t=" .. os.time()
end

local function build_urls(jsdelivr, raw)
	local out, seen = {}, {}
	for _, u in ipairs({ url_cache_bust(raw), raw, url_cache_bust(jsdelivr), jsdelivr }) do
		if u and u ~= "" and not seen[u] then
			seen[u] = true
			out[#out + 1] = u
		end
	end
	return out
end

local function fetch_update_manifest()
	local tmp = worked_dir .. "/.tools_manifest_tmp.json"
	for _, u in ipairs(build_urls(UPDATE_MANIFEST_URL_JS, UPDATE_MANIFEST_URL)) do
		pcall(os.remove, tmp)
		local ok = select(1, download_url_to_file_sync(tmp, u, 35))
		if ok then
			local data = read_json_file(tmp)
			pcall(os.remove, tmp)
			if data and data.current_version then
				last_manifest_cache = data
				return data
			end
		end
	end
	return nil
end

local function try_reload_script()
	pcall(function()
		local ts = thisScript()
		if ts and ts.reload then
			ts:reload()
		end
	end)
end

local function install_local_defaults()
	ensure_data_dir()
	settings = {}
	merge_defaults(settings, default_settings)
	settings.general.installed = true
	settings.general.version = get_local_script_version()
	save_settings()
	needs_install = false
	custom_dpi = settings.general.custom_dpi
	sync_customization_bufs()
	return true
end

local function finish_install(data)
	data.general = data.general or {}
	data.general.installed = true
	data.general.version = get_local_script_version()
	if last_manifest_cache and last_manifest_cache.data_version then
		data.general.data_version = tostring(last_manifest_cache.data_version)
	end
	if not write_json_file(path_settings, data) then
		return false, "не удалось записать Settings.json"
	end
	settings = data
	merge_defaults(settings, default_settings)
	needs_install = false
	custom_dpi = settings.general.custom_dpi
	sync_customization_bufs()
	return true, "ok"
end

local function do_install_data_files()
	UpdateUi.install_status = "Подключение к GitHub…"
	local m = last_manifest_cache or fetch_update_manifest()
	last_manifest_cache = m
	local settings_url = (m and m.settings_url) or SETTINGS_DEFAULT_URL
	local urls = build_urls(SETTINGS_DEFAULT_URL_JS, settings_url)
	local tmp = worked_dir .. "/.tools_settings_tmp.json"
	local ok_dl = false
	for i, u in ipairs(urls) do
		UpdateUi.install_status = "Скачивание (" .. i .. "/" .. #urls .. ")…"
		pcall(os.remove, tmp)
		ok_dl = select(1, download_url_to_file_sync(tmp, u, 35))
		if ok_dl then
			break
		end
	end
	if ok_dl then
		local data = read_json_file(tmp)
		pcall(os.remove, tmp)
		if data then
			local ok, err = finish_install(data)
			if ok then
				UpdateUi.install_status = "Готово!"
				sampChat("{009EFF}[Tools]{ffffff} Установка с GitHub завершена. Перезагрузка…")
				wait(700)
				try_reload_script()
				return true
			end
			UpdateUi.install_status = err or "ошибка записи"
			return false
		end
	end
	UpdateUi.install_status = "GitHub недоступен — локальная установка…"
	log_msg("[Tools] GitHub недоступен, ставим локальные настройки.")
	install_local_defaults()
	sampChat("{009EFF}[Tools]{ffffff} Установлено локально (без GitHub). Перезагрузка…")
	wait(700)
	try_reload_script()
	return true
end

local function apply_manifest(m)
	if not m then
		return
	end
	local rem = tostring(m.current_version or "")
	local loc = get_local_script_version()
	UpdateUi.need_script = rem ~= "" and vig_compare_versions(rem, loc) > 0
	UpdateUi.remote_script_ver = rem
	UpdateUi.changelog = m.update_info or ""
	UpdateUi.script_url = m.update_url or ""
end

local function do_download_script()
	local url = UpdateUi.script_url ~= "" and UpdateUi.script_url or UPDATE_MANIFEST_URL:gsub("ToolsUpdate%.json", "Tools.lua")
	local sp = thisScript().path
	local tmp = worked_dir .. "/.tools_new.lua"
	local body
	for _, u in ipairs(build_urls(UPDATE_SCRIPT_URL_JS, url)) do
		pcall(os.remove, tmp)
		if select(1, download_url_to_file_sync(tmp, u, 60)) then
			local f = io.open(tmp, "rb")
			if f then
				body = f:read("*a")
				f:close()
				break
			end
		end
	end
	if not body or body == "" then
		sampChat("{009EFF}[Tools]{ffffff} Не удалось скачать Tools.lua.")
		return
	end
	local out = io.open(sp, "wb")
	if not out then
		sampChat("{009EFF}[Tools]{ffffff} Нет прав на запись Tools.lua.")
		return
	end
	out:write(body)
	out:close()
	sampChat("{009EFF}[Tools]{ffffff} Обновлено. Перезагрузка…")
	wait(700)
	try_reload_script()
end

local function do_check_updates()
	UpdateUi.busy = true
	local m = fetch_update_manifest()
	if not m then
		UpdateUi.status_text = "Не удалось получить ToolsUpdate.json"
		sampChat("{009EFF}[Tools]{ffffff} " .. UpdateUi.status_text)
	else
		apply_manifest(m)
		local loc, rem = get_local_script_version(), UpdateUi.remote_script_ver
		if UpdateUi.need_script then
			UpdateUi.status_text = "Доступно v." .. rem .. " (у вас v." .. loc .. ")"
			sampChat("{009EFF}[Tools]{ffffff} Доступно обновление v." .. rem)
		else
			UpdateUi.status_text = "Актуально: v." .. loc
			sampChat("{009EFF}[Tools]{ffffff} Обновлений нет. v." .. loc)
		end
	end
	UpdateUi.busy = false
end

local function do_github_update()
	UpdateUi.busy = true
	local m = fetch_update_manifest()
	if m then
		last_manifest_cache = m
		apply_manifest(m)
	end
	if UpdateUi.need_script then
		do_download_script()
	else
		UpdateUi.status_text = "Уже актуально"
		sampChat("{009EFF}[Tools]{ffffff} Уже актуальная версия.")
	end
	UpdateUi.busy = false
end

local function do_install()
	UpdateUi.busy = true
	local ok, err = pcall(do_install_data_files)
	if not ok then
		UpdateUi.install_status = "Ошибка: " .. tostring(err)
		sampChat("{009EFF}[Tools]{ffffff} Ошибка установки.")
		log_msg("[Tools] install: " .. tostring(err))
	end
	UpdateUi.busy = false
end

local function process_pending()
	if UpdateUi.busy then
		return
	end
	if UpdateUi.pending_check then
		UpdateUi.pending_check = false
		if lua_thread and lua_thread.create then
			lua_thread.create(do_check_updates)
		else
			do_check_updates()
		end
	elseif UpdateUi.pending_update then
		UpdateUi.pending_update = false
		if lua_thread and lua_thread.create then
			lua_thread.create(do_github_update)
		else
			do_github_update()
		end
	elseif UpdateUi.pending_install then
		UpdateUi.pending_install = false
		if lua_thread and lua_thread.create then
			lua_thread.create(do_install)
		else
			do_install()
		end
	end
end

local function draw_logo(dl, cx, cy, sz)
	local p1 = imgui.ImVec2(cx, cy - sz)
	local p2 = imgui.ImVec2(cx - sz * 0.9, cy + sz * 0.75)
	local p3 = imgui.ImVec2(cx + sz * 0.9, cy + sz * 0.75)
	dl:AddTriangleFilled(p1, p2, p3, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.55, 0.35, 1.0, 1.0)))
	dl:AddTriangleFilled(
		imgui.ImVec2(cx, cy - sz * 0.55),
		imgui.ImVec2(cx - sz * 0.45, cy + sz * 0.2),
		imgui.ImVec2(cx + sz * 0.45, cy + sz * 0.2),
		imgui.ColorConvertFloat4ToU32(accent(0.95))
	)
end

local function draw_section_title(title)
	local dpi = custom_dpi
	local avail = imgui.GetContentRegionAvail().x
	local tw = imgui.CalcTextSize(im_utf8(title)).x
	local pad = 10 * dpi
	local line_w = math.max(20 * dpi, (avail - tw - pad * 2) * 0.5)
	imgui.Dummy(imgui.ImVec2(0, 4 * dpi))
	local y = imgui.GetCursorScreenPos().y + imgui.GetTextLineHeight() * 0.5
	local x0 = imgui.GetCursorScreenPos().x
	local dl = imgui.GetWindowDrawList()
	dl:AddLine(
		imgui.ImVec2(x0, y),
		imgui.ImVec2(x0 + line_w, y),
		imgui.ColorConvertFloat4ToU32(accent(0.55)),
		1.0
	)
	imgui.SetCursorScreenPos(imgui.ImVec2(x0 + line_w + pad, imgui.GetCursorScreenPos().y))
	imgui.TextColored(accent(0.95), im_utf8(title))
	local x1 = x0 + line_w + pad + tw + pad
	dl:AddLine(
		imgui.ImVec2(x1, y),
		imgui.ImVec2(x0 + avail, y),
		imgui.ColorConvertFloat4ToU32(accent(0.55)),
		1.0
	)
	imgui.Dummy(imgui.ImVec2(0, 8 * dpi))
end

local function row_checkbox(label, var, right)
	local dpi = custom_dpi
	imgui.PushID(label)
	imgui.AlignTextToFramePadding()
	imgui.Text(im_utf8(label))
	if right then
		local rw = imgui.CalcTextSize(im_utf8(right)).x
		imgui.SameLine(imgui.GetWindowContentRegionMax().x - rw - 8 * dpi)
		imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1.0), im_utf8(right))
	else
		imgui.SameLine(imgui.GetWindowContentRegionMax().x - 24 * dpi)
		imgui.TextColored(imgui.ImVec4(0.45, 0.48, 0.55, 0.8), im_utf8("⌨"))
	end
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - 52 * dpi)
	imgui.Checkbox("##cb", var)
	imgui.PopID()
end

local function row_checkbox_color(label, var, col)
	local dpi = custom_dpi
	imgui.PushID(label)
	imgui.AlignTextToFramePadding()
	imgui.Text(im_utf8(label))
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - 78 * dpi)
	imgui.ColorEdit3("##col", col, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.NoLabel)
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - 52 * dpi)
	imgui.Checkbox("##cb", var)
	imgui.PopID()
end

local function row_slider(label, var, vmin, vmax, fmt)
	imgui.Text(im_utf8(label))
	imgui.SameLine()
	imgui.SetNextItemWidth(-1)
	imgui.SliderInt("##sl", var, vmin, vmax, fmt or "%d")
end

local function accent_button(label, w, h)
	imgui.PushStyleColor(imgui.Col.Button, accent(0.85))
	imgui.PushStyleColor(imgui.Col.ButtonHovered, accent(0.95))
	imgui.PushStyleColor(imgui.Col.ButtonActive, accent(1.0))
	imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
	local pressed = imgui.Button(im_utf8(label), imgui.ImVec2(w, h))
	imgui.PopStyleColor(4)
	return pressed
end

local function draw_sidebar()
	local dpi = custom_dpi
	local w = 118 * dpi
	imgui.PushStyleColor(imgui.Col.ChildBg, Menu._sidebar_col or imgui.ImVec4(0.055, 0.06, 0.07, 1))
	imgui.BeginChild("##sidebar", imgui.ImVec2(w, -1), false)
	local dl = imgui.GetWindowDrawList()
	local cx = imgui.GetCursorScreenPos().x + w * 0.5
	draw_logo(dl, cx, imgui.GetCursorScreenPos().y + 22 * dpi, 14 * dpi)
	imgui.Dummy(imgui.ImVec2(0, 52 * dpi))
	for _, item in ipairs(SIDEBAR) do
		local sel = Menu.sidebar == item.page
		local pad = 8 * dpi
		local bw, bh = w - pad * 2, 34 * dpi
		local p = imgui.GetCursorScreenPos()
		if sel then
			dl:AddRectFilled(
				imgui.ImVec2(p.x + pad, p.y),
				imgui.ImVec2(p.x + pad + bw, p.y + bh),
				imgui.ColorConvertFloat4ToU32(accent(0.22)),
				6 * dpi
			)
			dl:AddRectFilled(
				imgui.ImVec2(p.x + pad, p.y + 6 * dpi),
				imgui.ImVec2(p.x + pad + 3 * dpi, p.y + bh - 6 * dpi),
				imgui.ColorConvertFloat4ToU32(accent(1.0)),
				2 * dpi
			)
		end
		imgui.SetCursorScreenPos(imgui.ImVec2(p.x + pad, p.y))
		imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
		imgui.PushStyleColor(imgui.Col.ButtonHovered, accent(0.12))
		imgui.PushStyleColor(imgui.Col.ButtonActive, accent(0.2))
		imgui.PushStyleColor(imgui.Col.Text, sel and accent(1.0) or imgui.ImVec4(0.62, 0.64, 0.68, 1.0))
		if imgui.Button(im_utf8(item.label .. "##nav_" .. item.id), imgui.ImVec2(bw, bh)) then
			Menu.sidebar = item.page
			Menu.subtab = 0
		end
		imgui.PopStyleColor(4)
	end
	imgui.EndChild()
	imgui.PopStyleColor()
end

local function draw_subtabs()
	local dpi = custom_dpi
	imgui.BeginChild("##subtabs", imgui.ImVec2(0, 34 * dpi), false)
	local dl = imgui.GetWindowDrawList()
	for i, name in ipairs(SUBTABS) do
		local idx = i - 1
		local sel = Menu.subtab == idx
		if i > 1 then
			imgui.SameLine(0, 18 * dpi)
		end
		imgui.PushStyleColor(imgui.Col.Text, sel and imgui.ImVec4(1, 1, 1, 1) or imgui.ImVec4(0.55, 0.57, 0.62, 1.0))
		if imgui.Selectable(im_utf8(name .. "##st_" .. idx), sel, 0, imgui.ImVec2(0, 24 * dpi)) then
			Menu.subtab = idx
		end
		if sel then
			local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
			dl:AddLine(
				imgui.ImVec2(mn.x, mx.y - 1),
				imgui.ImVec2(mx.x, mx.y - 1),
				imgui.ColorConvertFloat4ToU32(accent(1.0)),
				2.0
			)
		end
		imgui.PopStyleColor()
	end
	local clock = os.date("%H:%M")
	local cw = imgui.CalcTextSize(clock).x + 16 * dpi
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - cw)
	local cp = imgui.GetCursorScreenPos()
	dl:AddCircleFilled(
		imgui.ImVec2(cp.x + 8 * dpi, cp.y + 12 * dpi),
		10 * dpi,
		imgui.ColorConvertFloat4ToU32(accent(0.9))
	)
	imgui.SetCursorScreenPos(imgui.ImVec2(cp.x + 18 * dpi, cp.y + 2 * dpi))
	imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), clock)
	imgui.EndChild()
	imgui.Separator()
end

local function draw_two_columns(left_fn, right_fn)
	local avail = imgui.GetContentRegionAvail()
	local gap = 10 * custom_dpi
	local col_w = (avail.x - gap) * 0.5
	imgui.BeginChild("##col_l", imgui.ImVec2(col_w, avail.y), true)
	left_fn()
	imgui.EndChild()
	imgui.SameLine(0, gap)
	imgui.BeginChild("##col_r", imgui.ImVec2(0, avail.y), true)
	right_fn()
	imgui.EndChild()
end

local function render_aimbot_page()
	draw_two_columns(
		function()
			draw_section_title("General")
			row_checkbox("Godmode", Demo.godmode, "L.Mouse")
			row_checkbox("No ragdoll", Demo.no_ragdoll)
			row_checkbox("Seat belt", Demo.seat_belt)
			imgui.Spacing()
			draw_section_title("Health")
			row_slider("Health value", Demo.health_val, 0, 100, "%d")
			row_slider("Armor value", Demo.armor_val, 0, 100, "%d")
			row_checkbox("Health", Demo.health_cb)
		end,
		function()
			draw_section_title("Movements")
			row_checkbox("Speedhack", Demo.speedhack, "L.Mouse")
			row_checkbox("Noclip", Demo.noclip)
			row_checkbox("Super Jump", Demo.super_jump)
			row_checkbox("Freeze position", Demo.freeze_pos)
			imgui.Spacing()
			accent_button("Suicide", -1, 32 * custom_dpi)
		end
	)
end

local function render_visuals_page()
	draw_two_columns(
		function()
			draw_section_title("Esp")
			row_checkbox_color("Esp Player", Demo.esp_player, Demo.col_player)
			row_checkbox_color("Esp Vehicle", Demo.esp_vehicle, Demo.col_vehicle)
			row_checkbox_color("Esp Health", Demo.esp_health, Demo.col_health)
			row_checkbox_color("Esp Box", Demo.esp_box, Demo.col_box)
			row_checkbox_color("Esp Gun", Demo.esp_gun, Demo.col_gun)
		end,
		function()
			draw_section_title("Preview")
			imgui.TextWrapped(im_utf8("Раздел Visuals — заглушка. Цвета и чекбоксы готовы для будущего ESP."))
			imgui.Spacing()
			imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), im_utf8("Subtab: " .. SUBTABS[Menu.subtab + 1]))
		end
	)
end

local function render_placeholder_page(title, desc)
	draw_two_columns(
		function()
			draw_section_title("General")
			imgui.TextWrapped(im_utf8(desc))
		end,
		function()
			draw_section_title("Options")
			imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), im_utf8("Модуль «" .. title .. "» — скоро."))
		end
	)
end

local function render_script_page()
	if Menu.subtab == 1 then
		draw_two_columns(
			function()
				draw_section_title("Theme")
				imgui.Checkbox(im_utf8("Тёмная тема"), checkbox_dark)
				imgui.Checkbox(im_utf8("Скругление UI"), checkbox_rounded)
				imgui.Text(im_utf8("Акцент"))
				imgui.ColorEdit3("##acc", accent_col)
				imgui.Text(im_utf8("Прозрачность"))
				imgui.SliderFloat("##alpha", slider_alpha, 0.75, 1.0, "%.2f")
			end,
			function()
				draw_section_title("Interface")
				imgui.Text(im_utf8("Масштаб UI"))
				imgui.SliderFloat("##dpi", slider_dpi, 0.8, 1.4, "%.2f")
				imgui.Spacing()
				if accent_button("Сохранить##save_custom", -1, 32 * custom_dpi) then
					apply_customization_from_bufs()
					apply_theme_core()
					sampChat("{009EFF}[Tools]{ffffff} Кастомизация сохранена.")
				end
			end
		)
		return
	end
	if Menu.subtab == 2 then
		draw_two_columns(
			function()
				draw_section_title("Version")
				imgui.Text(im_utf8("Локально: v." .. get_local_script_version()))
				if UpdateUi.remote_script_ver ~= "" then
					imgui.Text(im_utf8("GitHub: v." .. UpdateUi.remote_script_ver))
				end
				if UpdateUi.status_text ~= "" then
					imgui.Spacing()
					imgui.TextWrapped(im_utf8(UpdateUi.status_text))
				end
				if UpdateUi.changelog ~= "" then
					imgui.Spacing()
					imgui.TextColored(accent(1), im_utf8("Changelog"))
					imgui.TextWrapped(im_utf8(UpdateUi.changelog))
				end
			end,
			function()
				draw_section_title("Actions")
				if UpdateUi.busy then
					imgui.Text(im_utf8("Идёт операция…"))
				else
					if accent_button("Проверить обновление##chk", -1, 34 * custom_dpi) then
						UpdateUi.pending_check = true
					end
					imgui.Spacing()
					if accent_button("Обновить##run", -1, 34 * custom_dpi) then
						UpdateUi.pending_update = true
					end
				end
			end
		)
		return
	end
	draw_two_columns(
		function()
			draw_section_title("Script")
			imgui.Text(im_utf8("Tools Menu v." .. get_local_script_version()))
			imgui.Text(im_utf8("Команда: /tools"))
			imgui.Text(im_utf8("Данные: moonloader/Tools/"))
		end,
		function()
			draw_section_title("Info")
			imgui.TextWrapped(
				im_utf8("Subtab Two — настройки темы.\nSubtab Three — проверка и загрузка обновлений с GitHub.")
			)
		end
	)
end

local function render_content()
	if Menu.sidebar == 0 then
		render_aimbot_page()
	elseif Menu.sidebar == 1 then
		render_visuals_page()
	elseif Menu.sidebar == 2 then
		render_placeholder_page("Trigger", "Triggerbot и связанные настройки.")
	elseif Menu.sidebar == 3 then
		render_placeholder_page("User", "Профиль и пользовательские опции.")
	elseif Menu.sidebar == 4 then
		render_placeholder_page("Pools", "Пул объектов и кэш.")
	elseif Menu.sidebar == 5 then
		render_placeholder_page("World", "Мир, погода, время.")
	elseif Menu.sidebar == 6 then
		render_placeholder_page("Misc", "Разное.")
	else
		render_script_page()
	end
end

local function register_imgui()
	imgui.OnFrame(
		function()
			return Menu.Window[0]
		end,
		function()
			ensure_theme_once()
			local dpi = custom_dpi
			imgui.SetNextWindowSize(imgui.ImVec2(820 * dpi, 520 * dpi), imgui.Cond.FirstUseEver)
			imgui.SetNextWindowPos(imgui.ImVec2(sizeX * 0.5, sizeY * 0.5), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
			local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoScrollbar
			if imgui.Begin("##tools_main_win", Menu.Window, flags) then
				draw_sidebar()
				imgui.SameLine()
				imgui.BeginGroup()
				imgui.BeginChild("##main_area", imgui.ImVec2(0, -1), false, imgui.WindowFlags.NoScrollbar)
				imgui.SetCursorPos(imgui.ImVec2(14 * dpi, 10 * dpi))
				imgui.BeginGroup()
				draw_subtabs()
				imgui.SetCursorPosX(14 * dpi)
				imgui.BeginChild("##content", imgui.ImVec2(-14 * dpi, -10 * dpi), false)
				render_content()
				imgui.EndChild()
				imgui.EndGroup()
				imgui.EndChild()
				imgui.EndGroup()
			end
			imgui.End()
		end
	)

	imgui.OnFrame(
		function()
			return Menu.InstallWindow[0]
		end,
		function()
			ensure_theme_once()
			imgui.SetNextWindowPos(imgui.ImVec2(sizeX / 2, sizeY / 2), imgui.Cond.Appearing, imgui.ImVec2(0.5, 0.5))
			if
				imgui.Begin(
					im_utf8("Установка Tools##install"),
					Menu.InstallWindow,
					imgui.WindowFlags.NoCollapse + imgui.WindowFlags.AlwaysAutoResize
				)
			then
				imgui.TextWrapped(
					im_utf8("Скачать настройки с GitHub или установить локально, если GitHub недоступен из игры.")
				)
				if UpdateUi.install_status ~= "" then
					imgui.Spacing()
					imgui.TextColored(accent(1), im_utf8(UpdateUi.install_status))
				end
				imgui.Spacing()
				if UpdateUi.busy then
					imgui.Text(im_utf8("Подождите…"))
				else
					if accent_button("Установить с GitHub##ig", 200 * custom_dpi, 32 * custom_dpi) then
						UpdateUi.pending_install = true
					end
					imgui.SameLine()
					if imgui.Button(im_utf8("Локально##il"), imgui.ImVec2(120 * custom_dpi, 32 * custom_dpi)) then
						install_local_defaults()
						Menu.InstallWindow[0] = false
						sampChat("{009EFF}[Tools]{ffffff} Локальная установка OK. /tools")
					end
					imgui.Spacing()
					if imgui.Button(im_utf8("Отмена##ic"), imgui.ImVec2(-1, 28 * custom_dpi)) then
						Menu.InstallWindow[0] = false
					end
				end
			end
			imgui.End()
		end
	)

	imgui.OnFrame(
		function()
			return Menu.UpdateWindow[0]
		end,
		function()
			ensure_theme_once()
			imgui.SetNextWindowPos(imgui.ImVec2(sizeX / 2, sizeY / 2), imgui.Cond.Appearing, imgui.ImVec2(0.5, 0.5))
			if
				imgui.Begin(
					im_utf8("Обновление##upd_notify"),
					Menu.UpdateWindow,
					imgui.WindowFlags.NoCollapse + imgui.WindowFlags.AlwaysAutoResize
				)
			then
				imgui.Text(im_utf8("Доступна v." .. updateVer .. " (у вас v." .. get_local_script_version() .. ")"))
				if updateInfoText ~= "" then
					imgui.TextWrapped(im_utf8(updateInfoText))
				end
				if imgui.Button(im_utf8("Позже##us"), imgui.ImVec2(120 * custom_dpi, 28 * custom_dpi)) then
					Menu.UpdateWindow[0] = false
				end
				imgui.SameLine()
				if accent_button("Обновить##un", 120 * custom_dpi, 28 * custom_dpi) then
					Menu.UpdateWindow[0] = false
					UpdateUi.pending_update = true
				end
			end
			imgui.End()
		end
	)
end

local function open_tools_menu()
	if needs_install then
		Menu.InstallWindow[0] = true
		return
	end
	Menu.Window[0] = not Menu.Window[0]
end

function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then
		log_msg("[Tools] STOP: нужны SAMP и sampfuncs")
		return
	end
	while not isSampAvailable() do
		wait(0)
	end
	if _G.TOOLS_MENU_LOADED then
		return
	end
	_G.TOOLS_MENU_LOADED = true

	load_settings()
	sync_customization_bufs()
	sampRegisterChatCommand("tools", open_tools_menu)
	pcall(register_imgui)

	sampChat("{009EFF}[Tools]{ffffff} v." .. get_local_script_version() .. " | /tools")
	log_msg("[Tools] v." .. get_local_script_version() .. " | " .. configDirectory)

	if lua_thread and lua_thread.create then
		lua_thread.create(function()
			wait(4000)
			if needs_install then
				sampChat("{009EFF}[Tools]{ffffff} Не установлен — /tools → Установить (или Локально)")
				return
			end
			local m = fetch_update_manifest()
			if m then
				apply_manifest(m)
				if UpdateUi.need_script then
					updateVer = UpdateUi.remote_script_ver
					updateInfoText = UpdateUi.changelog
					Menu.UpdateWindow[0] = true
					sampChat("{009EFF}[Tools]{ffffff} Есть обновление v." .. updateVer)
				end
			end
		end)
	end

	while true do
		wait(0)
		pcall(process_pending)
	end
end

function onScriptTerminate()
	_G.TOOLS_MENU_LOADED = nil
	pcall(sampUnregisterChatCommand, "tools")
end
