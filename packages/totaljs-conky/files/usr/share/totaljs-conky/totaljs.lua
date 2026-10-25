-- The widgets of Total.js Developer, drawn with Cairo. Every profile (system, services, compact, clock) is a function that Conky calls
-- after it has drawn its window: conky.config has `lua_load` for this file and `lua_draw_hook_post = 'system'` (or the name of another).
-- What is drawn is decided here, so the profiles can be edited without learning the text of Conky.
require 'cairo'
pcall(require, 'cairo_xlib')

-- the colors of the desktop of Total.js Developer
local COLOR = {
	card = '11161a', line = 'ffffff', text = 'e8edea', muted = '8b949e', green = '6ac043', lime = '9ad959',
	teal = '55c7c2', red = 'e75a5a', track = '2a3239', amber = 'd8b45d'
}

local function rgb(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function color(cr, hex, alpha)
	local r, g, b = rgb(hex)
	cairo_set_source_rgba(cr, r, g, b, alpha or 1)
end

local function value(expression)
	return tonumber(conky_parse(expression)) or 0
end

local function text(cr, string, x, y, size, hex, options)
	options = options or {}
	cairo_select_font_face(cr, options.mono and 'Fira Code' or 'Noto Sans', CAIRO_FONT_SLANT_NORMAL, options.bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
	cairo_set_font_size(cr, size)
	if options.align then
		local extents = cairo_text_extents_t:create()
		cairo_text_extents(cr, string, extents)
		local width = extents.x_advance
		if options.align == 'right' then x = x - width elseif options.align == 'center' then x = x - width / 2 end
	end
	if options.shadow then
		color(cr, '000000', 0.55)
		cairo_move_to(cr, x + 1.5, y + 1.5)
		cairo_show_text(cr, string)
	end
	color(cr, hex, options.alpha)
	cairo_move_to(cr, x, y)
	cairo_show_text(cr, string)
end

local function rounded(cr, x, y, w, h, r)
	cairo_new_sub_path(cr)
	cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
	cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
	cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
	cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
	cairo_close_path(cr)
end

-- the card of a widget: dark, a little transparent, with a fine border and a green mark on the left
local function card(cr, w, h)
	rounded(cr, 0.5, 0.5, w - 1, h - 1, 16)
	color(cr, COLOR.card, 0.72)
	cairo_fill_preserve(cr)
	color(cr, COLOR.line, 0.08)
	cairo_set_line_width(cr, 1)
	cairo_stroke(cr)
	rounded(cr, 0, 18, 4, 34, 2)
	color(cr, COLOR.green)
	cairo_fill(cr)
end

-- the mark of Total.js (a hexagon with the cut) in miniature
local function mark(cr, x, y, size)
	local function hexagon(radius)
		for i = 0, 5 do
			local angle = math.pi / 6 + i * math.pi / 3
			local px, py = x + radius * math.cos(angle), y + radius * math.sin(angle)
			if i == 0 then cairo_move_to(cr, px, py) else cairo_line_to(cr, px, py) end
		end
		cairo_close_path(cr)
	end
	hexagon(size)
	color(cr, COLOR.green)
	cairo_fill(cr)
	hexagon(size * 0.36)
	color(cr, COLOR.card)
	cairo_fill(cr)
end

local function header(cr, w, title, subtitle)
	mark(cr, 34, 38, 12)
	text(cr, title, 54, 38, 16, COLOR.text, { bold = true })
	text(cr, subtitle, 54, 56, 10, COLOR.muted)
	cairo_move_to(cr, 24, 72)
	cairo_line_to(cr, w - 24, 72)
	color(cr, COLOR.line, 0.1)
	cairo_set_line_width(cr, 1)
	cairo_stroke(cr)
end

-- an arc of 270 degrees that fills up with the value (0 to 100)
local function ring(cr, x, y, radius, width, percent, hex)
	local from, sweep = 3 * math.pi / 4, 3 * math.pi / 2
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
	cairo_set_line_width(cr, width)
	color(cr, COLOR.track)
	cairo_arc(cr, x, y, radius, from, from + sweep)
	cairo_stroke(cr)
	percent = math.max(0, math.min(100, percent))
	if percent > 0.5 then
		color(cr, hex)
		cairo_arc(cr, x, y, radius, from, from + sweep * percent / 100)
		cairo_stroke(cr)
	end
end

local function bar(cr, x, y, w, h, percent, hex)
	rounded(cr, x, y, w, h, h / 2)
	color(cr, COLOR.track)
	cairo_fill(cr)
	percent = math.max(0, math.min(100, percent))
	if percent > 1 then
		rounded(cr, x, y, math.max(h, w * percent / 100), h, h / 2)
		color(cr, hex)
		cairo_fill(cr)
	end
end

local function speed(kib)
	if kib >= 1024 then return string.format('%.1f MB/s', kib / 1024) end
	return string.format('%.0f KB/s', kib)
end

local function interface()
	local name = conky_parse('${gw_iface}'):gsub('%s+', '')
	return name ~= '' and name or 'lo'
end

local function draw(callback)
	if conky_window == nil then return end
	local surface = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, conky_window.width, conky_window.height)
	local cr = cairo_create(surface)
	callback(cr, conky_window.width, conky_window.height)
	cairo_destroy(cr)
	cairo_surface_destroy(surface)
end

-- the state of the services, asked to systemd at most once every five seconds (it needs no access to Docker)
local SERVICES = {
	{ 'Docker', 'docker' }, { 'Proxy', 'totaljs-proxy' }, { 'Code', 'totaljs-code' }, { 'Flow', 'totaljs-flow' },
	{ 'PostgreSQL', 'totaljs-postgres' }, { 'Center', 'totaljs-center' }, { 'SSH', 'ssh' }
}
local cache = { time = 0, states = {} }

local function services()
	if os.time() - cache.time >= 5 then
		cache.time = os.time()
		local names = {}
		for _, item in ipairs(SERVICES) do names[#names + 1] = item[2] end
		local handle = io.popen('systemctl is-active ' .. table.concat(names, ' ') .. ' 2>/dev/null')
		if handle then
			local index = 1
			for line in handle:lines() do
				cache.states[index] = line
				index = index + 1
			end
			handle:close()
		end
	end
	return cache.states
end

local top_speed = { down = 512, up = 128 }

function conky_system()
	draw(function(cr, w, h)
		card(cr, w, h)
		header(cr, w, 'Total.js Developer', conky_parse('${nodename}') .. '  ·  up ' .. conky_parse('${uptime_short}'))

		-- the three rings: processor, memory and disk
		local cpu, memory, disk = value('${cpu cpu0}'), value('${memperc}'), value('${fs_used_perc /}')
		local x, y = w / 2, 168
		ring(cr, x, y, 76, 10, cpu, COLOR.green)
		ring(cr, x, y, 58, 10, memory, COLOR.lime)
		ring(cr, x, y, 40, 10, disk, COLOR.teal)
		text(cr, string.format('%d%%', cpu), x, y + 9, 26, COLOR.text, { bold = true, mono = true, align = 'center' })
		text(cr, 'CPU', x, y + 28, 10, COLOR.muted, { align = 'center' })

		-- the legend of the rings
		local legend = { { 'CPU', cpu, COLOR.green }, { 'Memory', memory, COLOR.lime }, { 'Disk', disk, COLOR.teal } }
		local third = (w - 48) / 3
		for index, item in ipairs(legend) do
			local lx = 24 + (index - 1) * third + third / 2
			text(cr, string.format('%d%%', item[2]), lx, 276, 15, item[3], { bold = true, mono = true, align = 'center' })
			text(cr, item[1], lx, 293, 10, COLOR.muted, { align = 'center' })
		end

		-- the network
		local face = interface()
		local down, up = value('${downspeedf ' .. face .. '}'), value('${upspeedf ' .. face .. '}')
		top_speed.down, top_speed.up = math.max(top_speed.down, down), math.max(top_speed.up, up)
		text(cr, 'Network', 24, 330, 11, COLOR.text, { bold = true })
		text(cr, conky_parse('${addr ' .. face .. '}'), w - 24, 330, 11, COLOR.muted, { mono = true, align = 'right' })
		text(cr, 'Down', 24, 354, 10, COLOR.muted)
		text(cr, speed(down), w - 24, 354, 10, COLOR.text, { mono = true, align = 'right' })
		bar(cr, 24, 361, w - 48, 5, down * 100 / top_speed.down, COLOR.green)
		text(cr, 'Up', 24, 385, 10, COLOR.muted)
		text(cr, speed(up), w - 24, 385, 10, COLOR.text, { mono = true, align = 'right' })
		bar(cr, 24, 392, w - 48, 5, up * 100 / top_speed.up, COLOR.lime)

		-- the processes that use the most
		text(cr, 'Processes', 24, 428, 11, COLOR.text, { bold = true })
		for index = 1, 3 do
			local name = conky_parse('${top name ' .. index .. '}'):gsub('^%s+', ''):sub(1, 22)
			text(cr, name, 24, 428 + index * 20, 10, COLOR.muted)
			text(cr, conky_parse('${top cpu ' .. index .. '}'):gsub('%s+', '') .. '%', w - 24, 428 + index * 20, 10, COLOR.text, { mono = true, align = 'right' })
		end
	end)
end

function conky_services()
	draw(function(cr, w, h)
		card(cr, w, h)
		header(cr, w, 'Services', conky_parse('${nodename}') .. '  ·  up ' .. conky_parse('${uptime_short}'))
		local states = services()
		for index, item in ipairs(SERVICES) do
			local y = 78 + index * 30
			local state = states[index] or 'unknown'
			local hex, label = COLOR.muted, '-'
			if state == 'active' then hex, label = COLOR.green, 'running'
			elseif state == 'activating' then hex, label = COLOR.amber, 'starting'
			elseif state == 'inactive' or state == 'failed' then hex, label = COLOR.red, 'stopped' end
			cairo_arc(cr, 34, y - 4, 5, 0, 2 * math.pi)
			color(cr, hex)
			cairo_fill(cr)
			text(cr, item[1], 50, y, 12, COLOR.text)
			text(cr, label, w - 24, y, 11, hex, { mono = true, align = 'right' })
		end
		local y = 78 + (#SERVICES + 1) * 30
		cairo_move_to(cr, 24, y - 14)
		cairo_line_to(cr, w - 24, y - 14)
		color(cr, COLOR.line, 0.1)
		cairo_stroke(cr)
		text(cr, 'https://totaljs.developer', w / 2, y + 6, 10, COLOR.muted, { mono = true, align = 'center' })
	end)
end

function conky_compact()
	draw(function(cr, w, h)
		card(cr, w, h)
		header(cr, w, 'Total.js Developer', conky_parse('${nodename}'))
		local face = interface()
		local rows = { { 'CPU', value('${cpu cpu0}'), COLOR.green }, { 'Memory', value('${memperc}'), COLOR.lime }, { 'Disk', value('${fs_used_perc /}'), COLOR.teal } }
		for index, item in ipairs(rows) do
			local y = 78 + index * 26
			text(cr, item[1], 24, y, 10, COLOR.muted)
			text(cr, string.format('%d%%', item[2]), w - 24, y, 10, COLOR.text, { mono = true, align = 'right' })
			bar(cr, 82, y - 8, w - 82 - 70, 6, item[2], item[3])
		end
		text(cr, conky_parse('${addr ' .. face .. '}'), w / 2, 78 + 4 * 26 - 4, 10, COLOR.muted, { mono = true, align = 'center' })
	end)
end

function conky_clock()
	draw(function(cr, w, h)
		text(cr, conky_parse('${time %H:%M}'), w - 8, 84, 84, COLOR.text, { align = 'right', shadow = true })
		text(cr, conky_parse('${time %A, %d %B}'), w - 10, 116, 17, COLOR.text, { align = 'right', shadow = true, alpha = 0.85 })
		local states, running = services(), 0
		for index = 1, #SERVICES do
			if states[index] == 'active' then running = running + 1 end
		end
		local hex = running == #SERVICES and COLOR.green or COLOR.amber
		cairo_arc(cr, w - 14, 146, 4.5, 0, 2 * math.pi)
		color(cr, hex)
		cairo_fill(cr)
		text(cr, string.format('Total.js Developer · %d/%d services', running, #SERVICES), w - 28, 150, 11, COLOR.text, { align = 'right', shadow = true, alpha = 0.85 })
	end)
end
