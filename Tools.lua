---@diagnostic disable: undefined-global, lowercase-global
--[[
  Tools Menu — MoonLoader / SAMP
  /tools — меню с логотипом, разделами и кнопкой закрытия
  Данные: moonloader/Tools/
]]

script_name("Tools Menu")
script_description("Tools: /tools — меню с обновлением с GitHub")
script_author("Alex140219899")
script_version("1.0.15")

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

local dkok, dkjson = pcall(require, "lib.dkjson")
if not dkok then
	dkok, dkjson = pcall(require, "dkjson")
end

ffi.cdef("void __stdcall ExitProcess(unsigned int uExitCode);")
local ffi_string = ffi.string
local inicfg = require("inicfg")
local sampev = require("lib.samp.events")

local sizeX, sizeY = getScreenResolution()
local worked_dir = getWorkingDirectory():gsub("\\", "/")
local SCRIPT_VERSION_TEXT = "1.0.15"
local DATA_DIR_NAME = "Tools"
local message_color = 0x009EFF

local UPDATE_MANIFEST_URL = "https://raw.githubusercontent.com/Alex140219899/Atools/main/ToolsUpdate.json"
local UPDATE_MANIFEST_URL_JS = "https://cdn.jsdelivr.net/gh/Alex140219899/Atools@main/ToolsUpdate.json"
local UPDATE_SCRIPT_URL = "https://raw.githubusercontent.com/Alex140219899/Atools/main/Tools.lua"
local UPDATE_SCRIPT_URL_JS = "https://cdn.jsdelivr.net/gh/Alex140219899/Atools@main/Tools.lua"
local SETTINGS_DEFAULT_URL = "https://raw.githubusercontent.com/Alex140219899/Atools/main/Tools/SettingsDefault.json"
local SETTINGS_DEFAULT_URL_JS = "https://cdn.jsdelivr.net/gh/Alex140219899/Atools@main/Tools/SettingsDefault.json"
local LOGO_URL = "https://raw.githubusercontent.com/Alex140219899/Atools/main/Tools/logo.png"
local LOGO_URL_JS = "https://cdn.jsdelivr.net/gh/Alex140219899/Atools@main/Tools/logo.png"

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
local path_logo = configDirectory .. "/logo.png"
local path_offme_ini = configDirectory .. "/OFFme.ini"
local path_offme_ini_legacy = worked_dir .. "/OFFme.ini"

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
}

local SIDEBAR = {
	{ id = "update", label = "GitHub", page = 0 },
	{ id = "notify", label = "Уведомление", page = 1 },
}

local Offme = {
	script_state = false,
	repeat_state = false,
	time_settings = false,
	repeat_settings = false,
	text_settings = false,
	go_off = false,
	settings = nil,
	whenDo = {
		"Через время",
		"В опред. время",
		"После ПейДея",
		"После опред. сообщения в чат",
		"При потере соединения с сервером",
		"При опред. игроке в зоне стрима",
	},
	whatDo = {
		"Выключить ПК",
		"Выйти из игры",
		"Крашнуть игру",
		"Написать в чат (видно всем)",
		"Уведомление в чат (видно только вам)",
		"Перезайти на сервер",
	},
	buf = nil,
}

local logo_texture = nil
local logo_load_tried = false

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
	if dkok and dkjson and dkjson.decode then
		local ok, data = pcall(dkjson.decode, txt)
		if ok and type(data) == "table" then
			return data
		end
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

local function version_trim(s)
	s = tostring(s or ""):match("^%s*(.-)%s*$") or ""
	return s
end

local function read_script_version_from_path(path)
	path = tostring(path or "")
	if path == "" then
		return nil
	end
	for _, pv in ipairs({ path, path:gsub("\\", "/"), path:gsub("/", "\\") }) do
		local f = io.open(pv, "rb")
		if f then
			local head = f:read(65536) or ""
			f:close()
			local v = head:match("script_version%s*%(%s*[\"']([^\"']+)[\"']%s*%)")
			if v and v ~= "" then
				return version_trim(v)
			end
		end
	end
	return nil
end

local function get_local_script_version()
	local p = thisScript and thisScript().path
	local from_disk = p and read_script_version_from_path(p)
	if from_disk then
		return from_disk
	end
	if thisScript and thisScript().version and tostring(thisScript().version) ~= "" then
		return version_trim(thisScript().version)
	end
	return version_trim(SCRIPT_VERSION_TEXT)
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
	s.Colors[imgui.Col.ButtonHovered] = accent(0.55)
	s.Colors[imgui.Col.ButtonActive] = accent(0.75)
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

local function urls_dedupe(urls)
	local seen, out = {}, {}
	for _, u in ipairs(urls) do
		u = tostring(u or ""):match("^%s*(.-)%s*$") or ""
		if u ~= "" and not seen[u] then
			seen[u] = true
			out[#out + 1] = u
		end
	end
	return out
end

local function build_download_urls(jsdelivr, manifest_url, version_tag)
	local raw = {}
	if manifest_url and manifest_url ~= "" then
		if version_tag and version_tag ~= "" then
			local sep = manifest_url:find("?", 1, true) and "&" or "?"
			raw[#raw + 1] = manifest_url .. sep .. "v=" .. tostring(version_tag)
		end
		raw[#raw + 1] = url_cache_bust(manifest_url)
		raw[#raw + 1] = manifest_url
	end
	if jsdelivr and jsdelivr ~= "" then
		if version_tag and version_tag ~= "" then
			local sep = jsdelivr:find("?", 1, true) and "&" or "?"
			raw[#raw + 1] = jsdelivr .. sep .. "v=" .. tostring(version_tag)
		end
		raw[#raw + 1] = url_cache_bust(jsdelivr)
		raw[#raw + 1] = jsdelivr
	end
	return urls_dedupe(raw)
end

local function build_urls(jsdelivr, raw)
	return build_download_urls(jsdelivr, raw, "")
end

local function build_manifest_urls()
	local raw_urls = {}
	local u = UPDATE_MANIFEST_URL
	raw_urls[#raw_urls + 1] = url_cache_bust(u)
	raw_urls[#raw_urls + 1] = u
	raw_urls[#raw_urls + 1] = url_cache_bust(UPDATE_MANIFEST_URL_JS)
	raw_urls[#raw_urls + 1] = UPDATE_MANIFEST_URL_JS
	if u:find("/main/", 1, true) then
		local m = u:gsub("/main/", "/master/", 1)
		local mjs = UPDATE_MANIFEST_URL_JS:gsub("@main/", "@master/", 1)
		raw_urls[#raw_urls + 1] = url_cache_bust(m)
		raw_urls[#raw_urls + 1] = m
		raw_urls[#raw_urls + 1] = url_cache_bust(mjs)
		raw_urls[#raw_urls + 1] = mjs
	elseif u:find("/master/", 1, true) then
		local m = u:gsub("/master/", "/main/", 1)
		local mjs = UPDATE_MANIFEST_URL_JS:gsub("@master/", "@main/", 1)
		raw_urls[#raw_urls + 1] = url_cache_bust(m)
		raw_urls[#raw_urls + 1] = m
		raw_urls[#raw_urls + 1] = url_cache_bust(mjs)
		raw_urls[#raw_urls + 1] = mjs
	end
	return urls_dedupe(raw_urls)
end

local function fetch_update_manifest()
	local tmp = worked_dir .. "/.tools_manifest_tmp.json"
	if doesFileExist(tmp) then
		pcall(os.remove, tmp)
	end
	local urls = build_manifest_urls()
	local last_err = "не удалось скачать ToolsUpdate.json (GitHub и зеркало)"
	local best_data, best_src = nil, nil
	for _, manifest_url in ipairs(urls) do
		if doesFileExist(tmp) then
			pcall(os.remove, tmp)
		end
		if download_url_to_file_sync(tmp, manifest_url, 55) then
			local f = io.open(tmp, "r")
			if f then
				local txt = f:read("*a") or ""
				f:close()
				pcall(os.remove, tmp)
				local data = decode_json_str(txt)
				if type(data) == "table" and data.current_version ~= nil and tostring(data.current_version) ~= "" then
					local ver = version_trim(data.current_version)
					local pick = false
					if not best_data then
						pick = true
					elseif vig_compare_versions(ver, version_trim(best_data.current_version)) > 0 then
						pick = true
					end
					if pick then
						best_data = data
						best_src = manifest_url
					end
					log_msg("[Tools] ToolsUpdate.json v." .. ver .. " <- " .. tostring(manifest_url))
				else
					last_err = "в манифесте нет current_version или JSON не читается"
				end
			end
		end
	end
	if best_data then
		last_manifest_cache = best_data
		log_msg(
			"[Tools] выбран манифест v."
				.. version_trim(best_data.current_version)
				.. " <- "
				.. tostring(best_src)
		)
		return best_data, nil
	end
	return nil, last_err
end

local function probe_remote_script_max_version(update_url)
	update_url = tostring(update_url or "")
	if update_url == "" then
		update_url = UPDATE_SCRIPT_URL
	end
	local tmp = (worked_dir .. "/.tools_probe.lua"):gsub("\\", "/")
	if doesFileExist(tmp) then
		pcall(os.remove, tmp)
	end
	local urls = build_download_urls(UPDATE_SCRIPT_URL_JS, update_url, "")
	local best_ver = nil
	local probe_limit = math.min(3, #urls)
	for i = 1, probe_limit do
		local su = urls[i]
		if doesFileExist(tmp) then
			pcall(os.remove, tmp)
		end
		if download_url_to_file_sync(tmp, su, 90) then
			local f = io.open(tmp, "rb")
			if f then
				local head = f:read(65536) or ""
				f:close()
				local ver = head:match("script_version%s*%(%s*[\"']([^\"']+)[\"']%s*%)")
				if ver and ver ~= "" then
					ver = version_trim(ver)
					log_msg("[Tools] probe Tools.lua v." .. ver .. " <- " .. tostring(su))
					if not best_ver or vig_compare_versions(ver, best_ver) > 0 then
						best_ver = ver
					end
				end
			end
		end
	end
	if doesFileExist(tmp) then
		pcall(os.remove, tmp)
	end
	return best_ver
end

local function manifest_with_fresh_script_version(m)
	if type(m) ~= "table" then
		return m
	end
	local update_url = type(m.update_url) == "string" and m.update_url or UPDATE_SCRIPT_URL
	local manifest_v = version_trim(m.current_version or "")
	local local_v = version_trim(get_local_script_version())
	if manifest_v ~= "" and vig_compare_versions(manifest_v, local_v) > 0 then
		return m
	end
	local probed = nil
	local probe_ok, probe_err = pcall(function()
		probed = probe_remote_script_max_version(update_url)
	end)
	if not probe_ok then
		log_msg("[Tools] probe Tools.lua: " .. tostring(probe_err))
		return m
	end
	if not probed or probed == "" then
		return m
	end
	if vig_compare_versions(probed, manifest_v) <= 0 and vig_compare_versions(probed, local_v) <= 0 then
		return m
	end
	if manifest_v ~= "" and vig_compare_versions(probed, manifest_v) > 0 then
		log_msg(
			"[Tools] ToolsUpdate.json v."
				.. manifest_v
				.. " устарел (CDN), в Tools.lua на GitHub v."
				.. probed
		)
	end
	local out = {}
	for k, v in pairs(m) do
		out[k] = v
	end
	out.current_version = probed
	return out
end

local function fetch_update_manifest_resolved()
	local m, err = fetch_update_manifest()
	if not m then
		return nil, err
	end
	return manifest_with_fresh_script_version(m), nil
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
	local m = last_manifest_cache or select(1, fetch_update_manifest())
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
	ensure_logo_asset()
	sampChat("{009EFF}[Tools]{ffffff} Установлено локально (без GitHub). Перезагрузка…")
	wait(700)
	try_reload_script()
	return true
end

local function apply_manifest(m)
	if not m then
		return
	end
	local rem = version_trim(m.current_version or "")
	local loc = version_trim(get_local_script_version())
	UpdateUi.need_script = rem ~= "" and vig_compare_versions(rem, loc) > 0
	UpdateUi.remote_script_ver = rem
	UpdateUi.changelog = m.update_info or ""
	UpdateUi.script_url = m.update_url or UPDATE_SCRIPT_URL
end

local function download_best_script(script_urls, tmp, local_v, manifest_v)
	local best_body, best_ver, best_url = nil, nil, nil
	for _, su in ipairs(script_urls) do
		if doesFileExist(tmp) then
			pcall(os.remove, tmp)
		end
		if download_url_to_file_sync(tmp, su, 120) then
			local f = io.open(tmp, "rb")
			if f then
				local body = f:read("*a") or ""
				f:close()
				local ver = body:match("script_version%s*%(%s*[\"']([^\"']+)[\"']%s*%)")
				if ver and ver ~= "" then
					ver = version_trim(ver)
					log_msg("[Tools] Tools.lua v." .. ver .. " <- " .. tostring(su))
					if vig_compare_versions(ver, local_v) > 0 then
						if manifest_v == "" or vig_compare_versions(ver, manifest_v) >= 0 then
							if not best_ver or vig_compare_versions(ver, best_ver) > 0 then
								best_body = body
								best_ver = ver
								best_url = su
							end
						end
					end
				end
			end
		end
	end
	if doesFileExist(tmp) then
		pcall(os.remove, tmp)
	end
	if best_ver then
		log_msg("[Tools] выбран Tools.lua v." .. best_ver .. " <- " .. tostring(best_url))
	end
	return best_body, best_ver, best_url
end

local function do_download_script()
	local url = UpdateUi.script_url ~= "" and UpdateUi.script_url or UPDATE_SCRIPT_URL
	local sp = thisScript().path
	local tmp = worked_dir .. "/.tools_new.lua"
	local local_v = version_trim(get_local_script_version())
	local manifest_v = version_trim(UpdateUi.remote_script_ver)
	local script_urls = build_download_urls(UPDATE_SCRIPT_URL_JS, url, manifest_v)
	local body = select(1, download_best_script(script_urls, tmp, local_v, manifest_v))
	if not body or body == "" then
		for _, u in ipairs(script_urls) do
			pcall(os.remove, tmp)
			if download_url_to_file_sync(tmp, u, 120) then
				local f = io.open(tmp, "rb")
				if f then
					body = f:read("*a")
					f:close()
					if body and body ~= "" then
						break
					end
				end
			end
		end
	end
	if not body or body == "" then
		sampChat("{009EFF}[Tools]{ffffff} Не удалось скачать Tools.lua (GitHub недоступен из игры).")
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
	local m, err = fetch_update_manifest_resolved()
	if not m then
		UpdateUi.status_text = err or "Не удалось получить ToolsUpdate.json"
		UpdateUi.remote_script_ver = ""
		sampChat("{009EFF}[Tools]{ffffff} " .. UpdateUi.status_text)
		log_msg("[Tools] проверка: " .. UpdateUi.status_text)
	else
		apply_manifest(m)
		local loc, rem = get_local_script_version(), UpdateUi.remote_script_ver
		if UpdateUi.need_script then
			UpdateUi.status_text = "Доступно v." .. rem .. " (у вас v." .. loc .. ")"
			sampChat("{009EFF}[Tools]{ffffff} Доступно обновление v." .. rem)
		else
			UpdateUi.status_text = "Актуально: v." .. loc .. " (GitHub: v." .. rem .. ")"
			sampChat("{009EFF}[Tools]{ffffff} Обновлений нет. v." .. loc)
		end
	end
	UpdateUi.busy = false
end

local function do_github_update()
	UpdateUi.busy = true
	local m, err = fetch_update_manifest_resolved()
	if m then
		last_manifest_cache = m
		apply_manifest(m)
	elseif err then
		UpdateUi.status_text = err
		sampChat("{009EFF}[Tools]{ffffff} " .. err)
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

local function ensure_logo_asset()
	ensure_data_dir()
	if doesFileExist(path_logo) then
		return true
	end
	for _, u in ipairs(build_urls(LOGO_URL_JS, LOGO_URL)) do
		if select(1, download_url_to_file_sync(path_logo, u, 25)) then
			return doesFileExist(path_logo)
		end
	end
	return false
end

local function ensure_logo_texture()
	if logo_texture or logo_load_tried then
		return logo_texture ~= nil
	end
	logo_load_tried = true
	ensure_logo_asset()
	if not doesFileExist(path_logo) then
		log_msg("[Tools] logo.png не найден в " .. configDirectory)
		return false
	end
	local ok, tex = pcall(function()
		imgui.SwitchContext()
		return imgui.CreateTextureFromFile(path_logo)
	end)
	if ok and tex then
		logo_texture = tex
		return true
	end
	log_msg("[Tools] Не удалось загрузить logo.png")
	return false
end

local function accent_button(label, w, h)
	imgui.PushStyleColor(imgui.Col.Button, accent(0.9))
	imgui.PushStyleColor(imgui.Col.ButtonHovered, accent(1.0))
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

local function draw_sidebar_logo(dpi, sidebar_w)
	local logo_sz = 68 * dpi
	local top_pad = 24 * dpi
	local pad = math.max(8 * dpi, (sidebar_w - logo_sz) * 0.5)
	imgui.Dummy(imgui.ImVec2(0, top_pad))
	imgui.SetCursorPosX(pad)
	if ensure_logo_texture() then
		imgui.Image(logo_texture, imgui.ImVec2(logo_sz, logo_sz))
	else
		imgui.Dummy(imgui.ImVec2(logo_sz, logo_sz))
	end
	imgui.Dummy(imgui.ImVec2(0, 10 * dpi))
end

local function draw_sidebar()
	local dpi = custom_dpi
	local w = 145 * dpi
	imgui.PushStyleColor(imgui.Col.ChildBg, Menu._sidebar_col or imgui.ImVec4(0.055, 0.06, 0.07, 1))
	imgui.BeginChild("##sidebar", imgui.ImVec2(w, -1), false)
	draw_sidebar_logo(dpi, w)
	for _, item in ipairs(SIDEBAR) do
		local sel = Menu.sidebar == item.page
		local pad = 8 * dpi
		local bw, bh = w - pad * 2, 34 * dpi
		local p = imgui.GetCursorScreenPos()
		local dl = imgui.GetWindowDrawList()
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
		imgui.PushStyleColor(imgui.Col.ButtonHovered, accent(0.38))
		imgui.PushStyleColor(imgui.Col.ButtonActive, accent(0.55))
		imgui.PushStyleColor(imgui.Col.Text, sel and accent(1.0) or imgui.ImVec4(0.72, 0.74, 0.78, 1.0))
		if imgui.Button(im_utf8(item.label .. "##nav_" .. item.id), imgui.ImVec2(bw, bh)) then
			Menu.sidebar = item.page
		end
		imgui.PopStyleColor(4)
	end
	imgui.EndChild()
	imgui.PopStyleColor()
end

local function offme_save()
	ensure_data_dir()
	inicfg.save(Offme.settings, path_offme_ini)
end

local function offme_sync_bufs()
	local s = Offme.settings.shit
	Offme.buf.hourTimer[0] = tonumber(s.hour) or 0
	Offme.buf.minTimer[0] = tonumber(s.min) or 0
	Offme.buf.secTimer[0] = tonumber(s.sec) or 0
end

local function offme_load_settings()
	ensure_data_dir()
	if not doesFileExist(path_offme_ini) and doesFileExist(path_offme_ini_legacy) then
		pcall(function()
			local rf = io.open(path_offme_ini_legacy, "rb")
			if rf then
				local data = rf:read("*a")
				rf:close()
				local wf = io.open(path_offme_ini, "wb")
				if wf then
					wf:write(data)
					wf:close()
				end
			end
		end)
	end
	Offme.settings = inicfg.load({
		shit = {
			whenDoIt = 0,
			whatDoIt = 0,
			hour = 0,
			min = 0,
			sec = 0,
		},
	}, path_offme_ini)
	Offme.buf = {
		hourTimer = imgui.new.int(Offme.settings.shit.hour),
		minTimer = imgui.new.int(Offme.settings.shit.min),
		secTimer = imgui.new.int(Offme.settings.shit.sec),
		hourCD = imgui.new.int(0),
		minCD = imgui.new.int(0),
		secCD = imgui.new.int(0),
		text = imgui.new.char[512](),
		findText = imgui.new.char[512](),
	}
	offme_sync_bufs()
end

local function offme_center_text(text)
	local tw = imgui.CalcTextSize(im_utf8(text)).x
	imgui.SetCursorPosX((imgui.GetWindowWidth() - tw) * 0.5)
	imgui.Text(im_utf8(text))
end

local function offme_colored_button(text, hex, trans, size)
	local r = tonumber("0x" .. hex:sub(1, 2))
	local g = tonumber("0x" .. hex:sub(3, 4))
	local b = tonumber("0x" .. hex:sub(5, 6))
	local a = 60
	local t = tonumber(trans)
	if t ~= nil and t > 0 and t < 101 then
		a = t
	end
	local fa = a / 100
	local col = imgui.ImVec4(r / 255, g / 255, b / 255, fa)
	imgui.PushStyleColor(imgui.Col.Button, col)
	imgui.PushStyleColor(imgui.Col.ButtonHovered, col)
	imgui.PushStyleColor(imgui.Col.ButtonActive, col)
	local pressed = imgui.Button(im_utf8(text), size)
	imgui.PopStyleColor(3)
	return pressed
end

local function offme_refresh_flags()
	local cfg = Offme.settings.shit
	Offme.repeat_settings = cfg.whatDoIt > 3 and cfg.whatDoIt < 6
	Offme.time_settings = cfg.whenDoIt <= 2 and cfg.whenDoIt > 0
	Offme.text_settings = cfg.whenDoIt == 4 or cfg.whenDoIt == 6
end

local function offme_decode_buf(buf)
	local ok, r = pcall(function()
		return u8:decode(ffi_string(buf))
	end)
	return (ok and type(r) == "string") and r or ffi_string(buf)
end

local function offme_execute_action()
	local cfg = Offme.settings.shit
	if cfg.whatDoIt == 1 then
		os.execute("shutdown /s /t 5")
	elseif cfg.whatDoIt == 2 then
		ffi.C.ExitProcess(0)
	elseif cfg.whatDoIt == 3 then
		deleteChar(1)
	elseif cfg.whatDoIt == 4 then
		sampProcessChatInput(offme_decode_buf(Offme.buf.text))
	elseif cfg.whatDoIt == 5 then
		sampAddChatMessage(offme_decode_buf(Offme.buf.text), -1)
	elseif cfg.whatDoIt == 6 then
		local ip, port = sampGetCurrentServerAddress()
		wait(1000)
		sampConnectToServer(ip, port)
	end
end

local function offme_tick()
	if Offme.script_state then
		local cfg = Offme.settings.shit
		if cfg.whenDoIt == 1 then
			wait(Offme.buf.hourTimer[0] * 3600000)
			wait(Offme.buf.minTimer[0] * 60000)
			wait(Offme.buf.secTimer[0] * 1000)
			Offme.go_off = true
		elseif cfg.whenDoIt == 2 then
			local target = string.format(
				"%02d:%02d:%02d",
				Offme.buf.hourTimer[0],
				Offme.buf.minTimer[0],
				Offme.buf.secTimer[0]
			)
			if os.date("%H:%M:%S") == target then
				Offme.go_off = true
			end
		elseif cfg.whenDoIt == 3 then
			if os.date("%M") == "01" then
				Offme.go_off = true
			end
		end
		if not Offme.script_state then
			sampAddChatMessage(chat_utf8("{FF634F}[{ffffff}OFFme{FF634F}] {ffffff}Активация {FF634F}отменена"), -1)
			Offme.go_off = false
		end
	end
	if Offme.go_off then
		offme_execute_action()
		Offme.go_off = false
		Offme.script_state = false
		if Offme.repeat_state then
			wait(Offme.buf.hourCD[0] * 3600000)
			wait(Offme.buf.minCD[0] * 60000)
			wait(Offme.buf.secCD[0] * 1000)
			Offme.go_off = true
		end
	end
end

local function render_notify_page()
	if not Offme.buf then
		offme_load_settings()
	end
	offme_refresh_flags()

	local dpi = custom_dpi
	local avail = imgui.GetContentRegionAvail()
	local gap = 10 * dpi
	local col_w = math.max(180 * dpi, (avail.x - gap) * 0.5)
	local col2_w = math.max(180 * dpi, avail.x - col_w - gap)
	local btn_w = col_w - 12 * dpi

	if imgui.BeginChild("##offme_when", imgui.ImVec2(col_w, 214 * dpi), true) then
		offme_center_text("Когда")
		imgui.Separator()
		for i = 1, 6 do
			local sel = Offme.settings.shit.whenDoIt == i
			if offme_colored_button(Offme.whenDo[i], "F94242", sel and 70 or 20, imgui.ImVec2(btn_w, 24 * dpi)) then
				if Offme.settings.shit.whenDoIt ~= i then
					Offme.settings.shit.whenDoIt = i
				else
					Offme.settings.shit.whenDoIt = 0
				end
				offme_save()
				offme_refresh_flags()
			end
		end
		imgui.EndChild()
	end
	imgui.SameLine(0, gap)
	if imgui.BeginChild("##offme_what", imgui.ImVec2(col2_w, 214 * dpi), true) then
		offme_center_text("Что сделать")
		imgui.Separator()
		for i = 1, 6 do
			local sel = Offme.settings.shit.whatDoIt == i
			if offme_colored_button(Offme.whatDo[i], "F94242", sel and 70 or 20, imgui.ImVec2(btn_w, 24 * dpi)) then
				if Offme.settings.shit.whatDoIt ~= i then
					Offme.settings.shit.whatDoIt = i
				else
					Offme.settings.shit.whatDoIt = 0
				end
				offme_save()
				offme_refresh_flags()
			end
		end
		imgui.EndChild()
	end

	if Offme.time_settings then
		if imgui.BeginChild("##offme_timer", imgui.ImVec2(col_w, 185 * dpi), true) then
			offme_center_text("Настройки времени")
			imgui.Separator()
			imgui.SliderInt(im_utf8("Часы"), Offme.buf.hourTimer, 0, 23)
			imgui.SliderInt(im_utf8("Минуты"), Offme.buf.minTimer, 0, 59)
			imgui.SliderInt(im_utf8("Секунды"), Offme.buf.secTimer, 0, 59)
			if imgui.Button(im_utf8("Сохранить"), imgui.ImVec2(btn_w, 24 * dpi)) then
				Offme.settings.shit.hour = Offme.buf.hourTimer[0]
				Offme.settings.shit.min = Offme.buf.minTimer[0]
				Offme.settings.shit.sec = Offme.buf.secTimer[0]
				offme_save()
			end
			if imgui.Button(im_utf8("Сброс времени"), imgui.ImVec2(btn_w, 24 * dpi)) then
				Offme.buf.hourTimer[0] = 0
				Offme.buf.minTimer[0] = 0
				Offme.buf.secTimer[0] = 0
				Offme.settings.shit.hour = 0
				Offme.settings.shit.min = 0
				Offme.settings.shit.sec = 0
				offme_save()
			end
			imgui.EndChild()
		end
		imgui.SameLine(0, gap)
	elseif Offme.text_settings then
		if imgui.BeginChild("##offme_find", imgui.ImVec2(col_w, 185 * dpi), true) then
			offme_center_text(Offme.settings.shit.whenDoIt == 6 and "Введите ник" or "Введите сообщение")
			imgui.Separator()
			imgui.PushItemWidth(btn_w)
			imgui.InputText("##offme_find_text", Offme.buf.findText, 512)
			imgui.PopItemWidth()
			imgui.Button(im_utf8("Сохранить"), imgui.ImVec2(btn_w, 24 * dpi))
			imgui.Separator()
			if Offme.settings.shit.whenDoIt == 6 then
				imgui.TextWrapped(im_utf8("Введите ник формата:\nNick_Name"))
			else
				imgui.TextWrapped(im_utf8("Функция чувствительна к регистру\n\nВ случае большого текста, рекомендуется применять регулярки"))
			end
			imgui.EndChild()
		end
		imgui.SameLine(0, gap)
	end

	if Offme.repeat_settings then
		if imgui.BeginChild("##offme_cd", imgui.ImVec2(col2_w, 185 * dpi), true) then
			offme_center_text("Настройки режима")
			imgui.Separator()
			offme_center_text("Введите текст")
			imgui.Separator()
			imgui.PushItemWidth(col2_w - 58 * dpi)
			imgui.InputText("##offme_action_text", Offme.buf.text, 512)
			imgui.PopItemWidth()
			imgui.SameLine()
			if offme_colored_button("Повтор", Offme.repeat_state and "32CD32" or "F94242", Offme.repeat_state, imgui.ImVec2(45 * dpi, 24 * dpi)) then
				Offme.repeat_state = not Offme.repeat_state
			end
			imgui.Separator()
			if Offme.repeat_state then
				imgui.SliderInt(im_utf8("Часы"), Offme.buf.hourCD, 0, 23)
				imgui.SliderInt(im_utf8("Минуты"), Offme.buf.minCD, 0, 59)
				imgui.SliderInt(im_utf8("Секунды"), Offme.buf.secCD, 0, 59)
			else
				imgui.TextWrapped(im_utf8("\nПоддерживаются команды других скриптов"))
			end
			imgui.EndChild()
		end
	end

	imgui.Spacing()
	if offme_colored_button(
		Offme.script_state and "Включено" or "Выключено",
		Offme.script_state and "32CD32" or "F94242",
		Offme.script_state,
		imgui.ImVec2(-1, 28 * dpi)
	) then
		Offme.script_state = not Offme.script_state
	end
end

local function render_update_page()
	local dpi = custom_dpi
	imgui.TextColored(accent(0.95), im_utf8("Обновление с GitHub"))
	imgui.Spacing()
	imgui.Text(im_utf8("Локально: v." .. get_local_script_version()))
	if UpdateUi.remote_script_ver ~= "" then
		imgui.Text(im_utf8("GitHub: v." .. UpdateUi.remote_script_ver))
	else
		imgui.TextColored(imgui.ImVec4(0.55, 0.57, 0.62, 1), im_utf8("GitHub: нажмите «Проверить обновление»"))
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
	imgui.Spacing()
	if UpdateUi.busy then
		imgui.Text(im_utf8("Идёт операция…"))
	else
		if accent_button("Проверить обновление##chk", -1, 36 * dpi) then
			UpdateUi.pending_check = true
		end
		imgui.Spacing()
		if accent_button("Обновить##run", -1, 36 * dpi) then
			UpdateUi.pending_update = true
		end
	end
end

local function render_content()
	if Menu.sidebar == 0 then
		render_update_page()
	elseif Menu.sidebar == 1 then
		local ok, err = pcall(render_notify_page)
		if not ok then
			imgui.TextColored(imgui.ImVec4(1, 0.35, 0.35, 1), im_utf8("Ошибка раздела Уведомление"))
			imgui.TextWrapped(im_utf8(tostring(err)))
			log_msg("[Tools] notify UI: " .. tostring(err))
		end
	end
end

local function tools_apply_menu_frame(frame)
	if not frame then
		return
	end
	frame.HideCursor = false
	frame.LockPlayer = true
end

local function register_imgui()
	imgui.OnInitialize(function()
		local io = imgui.GetIO()
		io.IniFilename = nil
		io.ConfigFlags = io.ConfigFlags + imgui.ConfigFlags.NoMouseCursorChange
	end)

	imgui.OnFrame(
		function()
			return Menu.Window[0]
		end,
		function(player)
			tools_apply_menu_frame(player)
			ensure_theme_once()
			local dpi = custom_dpi
			imgui.SetNextWindowSize(imgui.ImVec2(760 * dpi, 540 * dpi), imgui.Cond.FirstUseEver)
			imgui.SetNextWindowPos(imgui.ImVec2(sizeX * 0.5, sizeY * 0.5), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
			local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoScrollbar
			if imgui.Begin("##tools_main_win", Menu.Window, flags) then
				draw_sidebar()
				imgui.SameLine()
				imgui.BeginChild(
					"##main_area",
					imgui.ImVec2(0, -1),
					false,
					Menu.sidebar == 1 and 0 or imgui.WindowFlags.NoScrollbar
				)
				draw_close_button()
				imgui.SetCursorPos(imgui.ImVec2(14 * dpi, 44 * dpi))
				imgui.BeginChild("##content", imgui.ImVec2(-14 * dpi, -14 * dpi), false, Menu.sidebar == 1 and 0 or imgui.WindowFlags.NoScrollbar)
				render_content()
				imgui.EndChild()
				imgui.EndChild()
			end
			imgui.End()
		end
	)

	imgui.OnFrame(
		function()
			return Menu.InstallWindow[0]
		end,
		function(player)
			tools_apply_menu_frame(player)
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
		function(player)
			tools_apply_menu_frame(player)
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
	offme_load_settings()
	sampRegisterChatCommand("tools", open_tools_menu)
	pcall(register_imgui)

	sampChat("{009EFF}[Tools]{ffffff} v." .. get_local_script_version() .. " | /tools")
	log_msg("[Tools] v." .. get_local_script_version() .. " | " .. configDirectory)
	log_msg("[Tools] манифест обновлений: " .. UPDATE_MANIFEST_URL)

	if doesFileExist(worked_dir .. "/OFFme.lua") then
		sampChat("{009EFF}[Tools]{ffffff} OFFme.lua можно отключить — он уже в /tools → Уведомление")
	end

	if lua_thread and lua_thread.create then
		lua_thread.create(function()
			wait(4000)
			if needs_install then
				sampChat("{009EFF}[Tools]{ffffff} Не установлен — /tools → Установить (или Локально)")
				return
			end
			local m, err = fetch_update_manifest_resolved()
			if m then
				apply_manifest(m)
				if UpdateUi.need_script then
					updateVer = UpdateUi.remote_script_ver
					updateInfoText = UpdateUi.changelog
					Menu.UpdateWindow[0] = true
					sampChat("{009EFF}[Tools]{ffffff} Есть обновление v." .. updateVer)
				end
			elseif err then
				log_msg("[Tools] авто-проверка: " .. tostring(err))
			end
		end)
	end

	while true do
		wait(0)
		pcall(offme_tick)
		pcall(process_pending)
	end
end

function sampev.onPlayerStreamIn(playerId)
	if Offme.buf and Offme.settings and Offme.settings.shit.whenDoIt == 6 and Offme.script_state then
		if sampGetPlayerNickname(playerId) == offme_decode_buf(Offme.buf.findText) then
			Offme.go_off = true
		end
	end
end

function sampev.onServerMessage(color, text)
	if Offme.buf and Offme.settings and Offme.script_state and Offme.settings.shit.whenDoIt == 4 then
		if tostring(text):find(offme_decode_buf(Offme.buf.findText), 1, true) then
			Offme.go_off = true
		end
	end
end

function onReceivePacket(id)
	if id == 32 and Offme.settings and Offme.settings.shit.whenDoIt == 5 and Offme.script_state then
		Offme.go_off = true
	end
end

function onScriptTerminate()
	_G.TOOLS_MENU_LOADED = nil
	pcall(sampUnregisterChatCommand, "tools")
end
