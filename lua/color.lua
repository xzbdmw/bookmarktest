Color = {}
Color.__index = Color

function get_hl_value(name, attr)
	local ok, hl = pcall(vim.api.nvim_get_hl_by_name, name, true)

	if not ok then
		return "NONE"
	end

	hl.foreground = hl.foreground and "#" .. bit.tohex(hl.foreground, 6)
	hl.background = hl.background and "#" .. bit.tohex(hl.background, 6)

	if hl.reverse then
		local normal_bg = get_hl_value("Normal", "bg")
		hl.background = hl.foreground
		hl.foreground = normal_bg
	end

	if attr then
		attr = ({ bg = "background", fg = "foreground" })[attr] or attr
		return hl[attr] or "NONE"
	end

	return hl.background, hl.foreground
end

local function setup_highlights(mode)
	local bg_normal_value, fg_normal_value = get_hl_value("Normal")
	local bg_normal = Color.new(bg_normal_value)
	local fg_normal = Color.new(fg_normal_value)
	local cursor_line = Color.new(get_hl_value("CursorLine", "bg"))
	local fg_border_value = get_hl_value("FloatBorder", "fg")
	local line_nr = Color.new(get_hl_value("LineNr", "fg"))

	if mode == "brighten" then
		local preview_bg = bg_normal:brighten(0.28)
		local preview_cursor_line = cursor_line:brighten(0.28)
		local preview_line_nr = line_nr:brighten(0.28)
		local list_bg = bg_normal:brighten(0.43)
		local list_filepath = fg_normal:darken(1.2)
		local list_cursor_line = cursor_line:brighten(0.43)
		local winbar_bg = bg_normal:brighten(0.53)
		local indent = line_nr:brighten(0.15)

		set_hl("PreviewNormal", { bg = preview_bg })
		set_hl("PreviewCursorLine", { bg = preview_cursor_line })
		set_hl("PreviewLineNr", { fg = preview_line_nr })
		set_hl("PreviewSignColumn", { fg = preview_bg })
		set_hl("ListCursorLine", { bg = list_cursor_line })
		set_hl("ListNormal", { bg = list_bg, fg = fg_normal_value })
		set_hl("ListFilepath", { fg = list_filepath })
		set_hl("WinBarFilename", { bg = winbar_bg, fg = fg_normal_value })
		set_hl("WinBarFilepath", { bg = winbar_bg, fg = fg_normal:darken(1.15) })
		set_hl("WinBarTitle", { bg = winbar_bg, fg = fg_normal_value })
		set_hl("Indent", { fg = indent })
		set_hl("FoldIcon", { fg = list_filepath })
		-- set_hl('ListEndOfBuffer', { bg = list_bg, fg = list_bg })
		-- set_hl('PreviewEndOfBuffer', { bg = preview_bg, fg = preview_bg })
		set_hl("BorderTop", { bg = winbar_bg, fg = fg_border_value })
		set_hl("ListBorderBottom", { bg = list_bg, fg = fg_border_value })
		set_hl("PreviewBorderBottom", { bg = preview_bg, fg = fg_border_value })
	else
		local preview_bg = bg_normal:darken(0.25)
		local preview_cursor_line = cursor_line:darken(0.25)
		local list_bg = bg_normal:darken(0.4)
		local list_filepath = fg_normal:darken(1.3)
		local list_cursor_line = cursor_line:darken(0.4)
		local winbar_bg = bg_normal:darken(0.5)
		local indent = line_nr:darken(0.3)

		set_hl("PreviewNormal", { bg = preview_bg })
		set_hl("PreviewCursorLine", { bg = preview_cursor_line })
		set_hl("PreviewSignColumn", { fg = preview_bg })
		set_hl("ListCursorLine", { bg = list_cursor_line })
		set_hl("ListNormal", { bg = list_bg, fg = fg_normal_value })
		set_hl("ListFilepath", { fg = list_filepath })
		set_hl("WinBarFilename", { bg = winbar_bg, fg = fg_normal_value })
		set_hl("WinBarFilepath", { bg = winbar_bg, fg = fg_normal:darken(1.2) })
		set_hl("WinBarTitle", { bg = winbar_bg, fg = fg_normal_value })
		set_hl("Indent", { fg = indent })
		set_hl("FoldIcon", { fg = list_filepath })
		-- set_hl('ListEndOfBuffer', { bg = list_bg, fg = list_bg })
		-- set_hl('PreviewEndOfBuffer', { bg = preview_bg, fg = preview_bg })
		set_hl("BorderTop", { bg = winbar_bg, fg = fg_border_value })
		set_hl("ListBorderBottom", { bg = list_bg, fg = fg_border_value })
		set_hl("PreviewBorderBottom", { bg = preview_bg, fg = fg_border_value })
	end
end
local function round(n)
	return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
end
-- Most of the code taken from chroma-js library
-- https://github.com/gka/chroma.js/

function Color.hex2rgb(hex)
	hex = hex:gsub("#", "")
	return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

function Color.rgb2hex(r, g, b)
	r = math.min(math.max(0, round(r)), 255)
	g = math.min(math.max(0, round(g)), 255)
	b = math.min(math.max(0, round(b)), 255)
	return "#" .. ("%02X%02X%02X"):format(r, g, b)
end

local function luminance_x(x)
	x = x / 255
	return x <= 0.03928 and x / 12.92 or math.pow((x + 0.055) / 1.055, 2.4)
end

function Color.rgb2luminance(r, g, b)
	r = luminance_x(r)
	g = luminance_x(g)
	b = luminance_x(b)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

function Color.hex2luminance(hex)
	if not hex or hex == "NONE" then
		return 0
	end
	return Color.rgb2luminance(Color.hex2rgb(hex))
end

local LAB = {
	Kn = 18,

	Xn = 0.950470,
	Yn = 1,
	Zn = 1.088830,

	t0 = 0.137931034,
	t1 = 0.206896552,
	t2 = 0.12841855,
	t3 = 0.008856452,
}

local function is_nan(v)
	return type(v) == "number" and v ~= v
end

local function xyz_rgb(r)
	return 255 * (r <= 0.00304 and 12.92 * r or 1.055 * math.pow(r, 1 / 2.4) - 0.055)
end

local function lab_xyz(t)
	return t > LAB.t1 and t * t * t or LAB.t2 * (t - LAB.t0)
end

local function lab2rgb(l, a, b)
	local x, y, z, r, g, b_

	y = (l + 16) / 116
	x = is_nan(a) and y or y + a / 500
	z = is_nan(b) and y or y - b / 200

	y = LAB.Yn * lab_xyz(y)
	x = LAB.Xn * lab_xyz(x)
	z = LAB.Zn * lab_xyz(z)

	r = xyz_rgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z)
	g = xyz_rgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z)
	b_ = xyz_rgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)

	return r, g, b_
end

local function rgb_xyz(r)
	r = r / 255
	if r <= 0.04045 then
		return r / 12.92
	end
	return math.pow((r + 0.055) / 1.055, 2.4)
end

local function xyz_lab(t)
	if t > LAB.t3 then
		return math.pow(t, 1 / 3)
	end

	return t / LAB.t2 + LAB.t0
end

local function rgb2xyz(r, g, b)
	r = rgb_xyz(r)
	g = rgb_xyz(g)
	b = rgb_xyz(b)

	local x = xyz_lab((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / LAB.Xn)
	local y = xyz_lab((0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / LAB.Yn)
	local z = xyz_lab((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / LAB.Zn)

	return x, y, z
end

local function rgb2lab(r, g, b)
	local x, y, z = rgb2xyz(r, g, b)
	local l = 116 * y - 16
	l = l < 0 and 0 or l
	local a = 500 * (x - y)
	b = 200 * (y - z)
	return l, a, b
end

function Color:darken(amount)
	local lab = self.lab
	local l = lab[1] - (LAB.Kn * amount)
	local r, g, b = lab2rgb(l, lab[2], lab[3])
	return Color.rgb2hex(r, g, b)
end

function Color:brighten(amount)
	return self:darken(-amount)
end

function Color.new(hex)
	if not hex or hex == "NONE" then
		return nil
	end
	local self = { Color.hex2rgb(hex) }
	self.lab = { rgb2lab(unpack(self)) }
	return setmetatable(self, Color)
end

return Color
