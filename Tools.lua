---@diagnostic disable: undefined-global, lowercase-global
--[[
  Tools Menu — MoonLoader / SAMP
  /tools — пустое меню с кнопкой закрытия
  Данные: moonloader/Tools/
]]

script_name("Tools Menu")
script_description("Tools: /tools — меню с обновлением с GitHub")
script_author("Alex140219899")
script_version("1.0.1")

require("lib.moonloader")
require("encoding").default = "CP1251"
local u8 = require("encoding").UTF8
local ffi = require("ffi")
local imgui = require("mimgui")

if not imgui.PushID then
	imgui.PushID = function(id)
		if type(id) == "string" then
			imgui.PushIDStr(id)
		elseif type(id) == "number" then
			imgui.PushIDInt(id)
		else
			imgui.PushIDPtr(ffi.cast("void*", id))
		end
	end
end

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

local function accent_button(label, w, h)
	imgui.PushStyleColor(imgui.Col.Button, accent(0.85))
	imgui.PushStyleColor(imgui.Col.ButtonHovered, accent(0.95))
	imgui.PushStyleColor(imgui.Col.ButtonActive, accent(1.0))
	imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
	local pressed = imgui.Button(im_utf8(label), imgui.ImVec2(w, h))
	imgui.PopStyleColor(4)
	return pressed
end

local function draw_close_button()
	local dpi = custom_dpi
	local btn_sz = 26 * dpi
	local pad = 8 * dpi
	local max = imgui.GetWindowContentRegionMax()
	imgui.SetCursorPos(imgui.ImVec2(max.x - btn_sz - pad, pad))
	imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
	imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.22, 0.28, 0.9))
	imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.95, 0.15, 0.2, 1))
	imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.85, 0.88, 0.92, 1))
	local closed = imgui.Button(im_utf8("×##tools_close"), imgui.ImVec2(btn_sz, btn_sz))
	imgui.PopStyleColor(4)
	if closed then
		Menu.Window[0] = false
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
			imgui.SetNextWindowSize(imgui.ImVec2(420 * dpi, 280 * dpi), imgui.Cond.FirstUseEver)
			imgui.SetNextWindowPos(imgui.ImVec2(sizeX * 0.5, sizeY * 0.5), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
			local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoScrollbar
			if imgui.Begin("##tools_main_win", Menu.Window, flags) then
				draw_close_button()
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
