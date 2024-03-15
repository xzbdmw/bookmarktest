local fn, api = vim.fn, vim.api
-- local ts_utils = require("nvim-treesitter-ts_utils")
local ns = api.nvim_create_namespace("nvim-treesitter-context")

-- Don't access directly, use get_bufs()
local gutter_bufnr --- @type integer?
local context_bufnr --- @type integer?
local context_bufnrs = {}
local gutter_winid --- @type integer?
local context_winid --- @type integer?
local context_winids = {}

--- @param buf integer?
--- @return integer buf
local function create_buf()
	local buf = vim.api.nvim_create_buf(true, false)
	-- if buf and api.nvim_buf_is_valid(buf) then
	-- 	return buf
	-- end

	-- buf = api.nvim_create_buf(false, true)

	vim.bo[buf].undolevels = -1
	vim.bo[buf].bufhidden = "wipe"

	return buf
end

--- @return integer gutter_bufnr
--- @return integer context_bufnr
local function get_bufs()
	context_bufnr = create_buf()
	-- table.insert(context_bufnrs, context_bufnr)
	-- gutter_bufnr = create_buf(gutter_bufnr)

	return gutter_bufnr, context_bufnr
end
-- local config = require("treesitter-context.config")
-- local util = require("treesitter-context.util")
-- local cache = require("treesitter-context.cache")
local get_lang = vim.treesitter.language.get_lang or require("nvim-treesitter.parsers").ft_to_lang

--- @diagnostic disable-next-line:deprecated
local get_query = vim.treesitter.query.get or vim.treesitter.query.get_query

--- @param langtree LanguageTree
--- @param range Range4
--- @return TSNode[]?
local function get_parent_nodes(langtree, range)
	local tree = langtree:tree_for_range(range, { ignore_injections = true })
	if tree == nil then
		return
	end

	local n = tree:root():named_descendant_for_range(unpack(range))

	local ret = {} --- @type TSNode[]
	while n do
		ret[#ret + 1] = n
		n = n:parent()
	end
	return ret
end

--- @param winid integer
--- @return integer
local function calc_max_lines(winid)
	-- local max_lines = config.max_lines == 0 and -1 or config.max_lines
	local max_lines = 5
	local wintop = fn.line("w0", winid)
	local cursor = fn.line(".", winid)
	local max_from_cursor = cursor - wintop

	-- if config.separator and max_from_cursor > 0 then
	-- 	max_from_cursor = max_from_cursor - 1 -- separator takes 1 line
	-- end

	if max_lines ~= -1 then
		max_lines = math.min(max_lines, max_from_cursor)
	else
		max_lines = max_from_cursor
	end

	return max_lines
end

---@param node TSNode
---@return string
local function hash_node(node)
	return table.concat({
		node:id(),
		node:symbol(),
		node:child_count(),
		node:type(),
		node:range(),
	}, ",")
end

--- Run the context query on a node and return the range if it is a valid
--- context node.
--- @param node TSNode
--- @param query Query
--- @return Range4?
local context_range = require("cache").memoize(function(node, query)
	local bufnr = api.nvim_get_current_buf()
	local range = { node:range() } --- @type Range4
	-- __AUTO_GENERATED_PRINT_VAR_START__
	print([==[function range:]==], vim.inspect(range)) -- __AUTO_GENERATED_PRINT_VAR_END__
	range[3] = range[1]
	range[4] = -1

	-- max_start_depth depth is only supported in nvim 0.10. It is ignored on
	-- versions 0.9 or less. It is only needed to improve performance
	for _, match in query:iter_matches(node, bufnr, 0, -1, { max_start_depth = 0 }) do
		local r = false

		for id, node0 in pairs(match) do
			local srow, scol, erow, ecol = node0:range()

			local name = query.captures[id] -- name of the capture in the query
			if not r and name == "context" then
				r = node == node0
			elseif name == "context.start" then
				range[1] = srow
				range[2] = scol
			elseif name == "context.final" then
				range[3] = erow
				range[4] = ecol
			elseif name == "context.end" then
				range[3] = srow
				range[4] = scol
			end
		end

		if r then
			-- __AUTO_GENERATED_PRINT_VAR_START__
			print([==[returned range:]==], vim.inspect(range)) -- __AUTO_GENERATED_PRINT_VAR_END__
			return range
		end
	end
end, hash_node)

--- Run the context query on a node and return the range if it is a valid
--- context node.
--- @param node TSNode
--- @param query Query
--- @return Range4?
local context_current_range = require("cache").memoize(function(node, query)
	local bufnr = api.nvim_get_current_buf()
	local range = { node:range() } --- @type Range4
	-- __AUTO_GENERATED_PRINT_VAR_START__
	print([==[function range:]==], vim.inspect(range)) -- __AUTO_GENERATED_PRINT_VAR_END__
	range[3] = range[1]
	range[4] = -1

	return range
end, hash_node)
---@param lang string
---@return Query?
local function get_context_query(lang)
	local ok, query = pcall(get_query, lang, "context")

	if not ok then
		vim.notify_once(
			string.format("Unable to load context query for %s:\n%s", lang, query),
			vim.log.levels.ERROR,
			{ title = "nvim-treesitter-context" }
		)
		return
	end

	return query
end

--- @param r Range4
--- @return integer
local function get_range_height(r)
	return r[3] - r[1] + (r[4] == 0 and 0 or 1)
end

---@param context_ranges Range4[]
---@param context_lines string[][]
---@param trim integer
---@param top boolean
local function trim_contexts(context_ranges, context_lines, trim, top)
	while trim > 0 do
		local idx = top and 1 or #context_ranges
		local context_to_trim = context_ranges[idx]

		local height = get_range_height(context_to_trim)

		if height <= trim then
			table.remove(context_ranges, idx)
			table.remove(context_lines, idx)
		else
			context_to_trim[3] = context_to_trim[3] - trim
			context_to_trim[4] = -1
			local context_lines_to_trim = context_lines[idx]
			for _ = 1, trim do
				context_lines_to_trim[#context_lines_to_trim] = nil
			end
		end
		trim = math.max(0, trim - height)
	end
end

--- @param range Range4
--- @return Range4, string[]
local function get_text_for_range(range)
	local start_row, end_row, end_col = range[1], range[3], range[4]

	if end_col == 0 then
		end_row = end_row - 1
		end_col = -1
	end

	local lines = api.nvim_buf_get_text(0, start_row, 0, end_row, -1, {})

	-- Strip any empty lines from the node
	while #lines > 0 do
		local last_line_of_node = lines[#lines]:sub(1, end_col)
		if last_line_of_node:match("%S") then
			break
		end
		lines[#lines] = nil
		end_col = -1
		end_row = end_row - 1
	end

	return { start_row, 0, end_row, -1 }, lines
end

local M = {}

---@param bufnr integer
---@param row integer
---@param col integer
---@return LanguageTree[]
local function get_parent_langtrees(bufnr, range)
	local root_tree = vim.treesitter.get_parser(bufnr)
	if not root_tree then
		return {}
	end

	local parent_langtrees = { root_tree }

	while true do
		local child_langtree = nil

		for _, langtree in pairs(parent_langtrees[#parent_langtrees]:children()) do
			if langtree:contains(range) then
				child_langtree = langtree
				break
			end
		end

		if child_langtree == nil then
			break
		end
		parent_langtrees[#parent_langtrees + 1] = child_langtree
	end

	return parent_langtrees
end

--- @param bufnr integer
--- @param winid integer
--- @return Range4[]?, string[]?
function M.get(bufnr, winid)
	local max_lines = calc_max_lines(winid)

	if max_lines == 0 then
		return
	end

	local gbufnr, ctx_bufnr = get_bufs()
	if not pcall(vim.treesitter.get_parser, bufnr) then
		return
	end

	local top_row = fn.line("w0", winid) - 1

	--- @type integer, integer
	local row, col

	local c = api.nvim_win_get_cursor(winid)
	row, col = c[1] - 1, c[2]

	local context_ranges = {} --- @type Range4[]
	local context_lines = {} --- @type string[][]
	local contexts_height = 0

	for offset = 0, max_lines do
		local node_row = row + offset
		local col0 = offset == 0 and col or 0
		local line_range = { node_row, col0, node_row, col0 + 1 }

		context_ranges = {}
		context_lines = {}
		contexts_height = 0

		local parent_trees = get_parent_langtrees(bufnr, line_range)
		for i = 1, #parent_trees, 1 do
			local langtree = parent_trees[i]
			local query = get_context_query(langtree:lang())
			if not query then
				return
			end

			local parents = get_parent_nodes(langtree, line_range)
			-- __AUTO_GENERATED_PRINT_VAR_START__
			print([==[M.get#for#for parents:]==], vim.inspect(parents)) -- __AUTO_GENERATED_PRINT_VAR_END__
			local node = vim.treesitter.get_node()
			-- __AUTO_GENERATED_PRINT_VAR_START__
			print([==[M.get#for#for node:]==], vim.inspect(node)) -- __AUTO_GENERATED_PRINT_VAR_END__
			table.insert(parents, 1, node)

			-- __AUTO_GENERATED_PRINT_VAR_START__
			print([==[M.get#for#for parents:]==], vim.inspect(parents)) -- __AUTO_GENERATED_PRINT_VAR_END__
			if parents == nil then
				return
			end

			for j = #parents, 2, -1 do
				local parent = parents[j]
				-- __AUTO_GENERATED_PRINT_VAR_START__
				print([==[M.get#for#for#for parent:]==], vim.inspect(parent)) -- __AUTO_GENERATED_PRINT_VAR_END__
				local parent_start_row = parent:range()
				-- __AUTO_GENERATED_PRINT_VAR_START__
				print([==[M.get#for#for#for parent_start_row:]==], vim.inspect(parent_start_row)) -- __AUTO_GENERATED_PRINT_VAR_END__

				local contexts_end_row = top_row + math.min(max_lines, contexts_height)
				-- __AUTO_GENERATED_PRINT_VAR_START__
				print([==[M.get#for#for#for contexts_end_row:]==], vim.inspect(contexts_end_row)) -- __AUTO_GENERATED_PRINT_VAR_END__
				-- Only process the parent if it is not in view.
				local range0 = context_range(parent, query)
				if range0 then
					local range, lines = get_text_for_range(range0)
					-- __AUTO_GENERATED_PRINT_VAR_START__
					print([==[M.get#for#for#for#if range:]==], vim.inspect(range)) -- __AUTO_GENERATED_PRINT_VAR_END__
					-- __AUTO_GENERATED_PRINT_VAR_START__
					print([==[Bookmark : M.get#for#for#for#if lines:]==], vim.inspect(lines)) -- __AUTO_GENERATED_PRINT_VAR_END__

					local last_context = context_ranges[#context_ranges]
					if last_context and parent_start_row == last_context[1] then
						contexts_height = contexts_height - get_range_height(last_context)
						context_ranges[#context_ranges] = nil
						context_lines[#context_lines] = nil
					end

					contexts_height = contexts_height + get_range_height(range)
					context_ranges[#context_ranges + 1] = range
					context_lines[#context_lines + 1] = lines
				end
			end

			local parent = parents[1]
			-- __AUTO_GENERATED_PRINT_VAR_START__
			print([==[M.get#for#for#for parent:]==], vim.inspect(parent)) -- __AUTO_GENERATED_PRINT_VAR_END__
			local parent_start_row = parent:range()
			-- __AUTO_GENERATED_PRINT_VAR_START__
			print([==[M.get#for#for#for parent_start_row:]==], vim.inspect(parent_start_row)) -- __AUTO_GENERATED_PRINT_VAR_END__

			local contexts_end_row = top_row + math.min(max_lines, contexts_height)
			-- __AUTO_GENERATED_PRINT_VAR_START__
			print([==[M.get#for#for#for contexts_end_row:]==], vim.inspect(contexts_end_row)) -- __AUTO_GENERATED_PRINT_VAR_END__
			-- Only process the parent if it is not in view.
			local range0 = context_current_range(parent, query)
			if range0 then
				local range, lines = get_text_for_range(range0)
				-- __AUTO_GENERATED_PRINT_VAR_START__
				print([==[M.get#for#for#for#if range:]==], vim.inspect(range)) -- __AUTO_GENERATED_PRINT_VAR_END__
				-- __AUTO_GENERATED_PRINT_VAR_START__
				print([==[Bookmark : M.get#for#for#for#if lines:]==], vim.inspect(lines)) -- __AUTO_GENERATED_PRINT_VAR_END__

				local last_context = context_ranges[#context_ranges]
				if last_context and parent_start_row == last_context[1] then
					contexts_height = contexts_height - get_range_height(last_context)
					context_ranges[#context_ranges] = nil
					context_lines[#context_lines] = nil
				end

				contexts_height = contexts_height + get_range_height(range)
				context_ranges[#context_ranges + 1] = range
				context_lines[#context_lines + 1] = lines
			end
		end

		local contexts_end_row = top_row + math.min(max_lines, contexts_height)

		if node_row >= contexts_end_row then
			break
		end
	end

	local trim = contexts_height - max_lines
	if trim > 0 then
		trim_contexts(context_ranges, context_lines, trim, true)
	end

	return context_ranges, vim.tbl_flatten(context_lines), ctx_bufnr
end

--- @param contexts Range4[]
--- @return integer start_row, integer end_row
local function get_contexts_range(contexts)
	--- @type integer, integer
	local srow, erow
	for i, context in ipairs(contexts) do
		local csrow, cerow = context[1], context[3]
		if i == 1 or csrow < srow then
			srow = csrow
		end

		if i == 1 or cerow > erow then
			erow = cerow
		end
	end
	return srow, erow
end

---@param bufnr integer
---@param row integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
local function add_extmark(bufnr, row, col, opts)
	local ok, err = pcall(api.nvim_buf_set_extmark, bufnr, ns, row, col, opts)
	if not ok then
		local range = vim.inspect({ row, col, opts.end_row, opts.end_col }) --- @type string
		error(string.format("Could not apply exmtark to %s: %s", range, err))
	end
end

local function get_hl_value(name, attr)
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

--- @param query vim.treesitter.Query
--- @param capture integer
--- @return integer
local hl_from_capture = require("cache").memoize(function(query, capture, lang)
	local name = query.captures[capture]
	local hl = 0
	if not vim.startswith(name, "_") then
		hl = api.nvim_get_hl_id_by_name("@" .. name .. "." .. lang)
	end
	return hl
end, function(_, capture, lang)
	return lang .. tostring(capture)
end)

--- @param query vim.treesitter.Query
--- @param capture integer
--- @return integer
local hl_from_capture_darken = require("cache").memoize(function(query, capture, lang)
	local name = query.captures[capture]
	-- local hl = 0
	-- if not vim.startswith(name, "_") then
	-- 	hl = api.nvim_get_hl_id_by_name("@" .. name .. "." .. lang)
	-- end
	local hl_name = "@" .. name .. "." .. lang
	-- __AUTO_GENERATED_PRINT_VAR_START__
	print([==[function hl_name:]==], vim.inspect(hl_name)) -- __AUTO_GENERATED_PRINT_VAR_END__
	local fg_normal_value = get_hl_value(hl_name, "fg")
	-- __AUTO_GENERATED_PRINT_VAR_START__
	print([==[function fg_normal_value:]==], vim.inspect(fg_normal_value)) -- __AUTO_GENERATED_PRINT_VAR_END__
	local fg_normal = Color.new(fg_normal_value)
	if fg_normal then
		local list_filepath = fg_normal:darken(1.4)
		local new_hl_name = hl_name .. "Darkened" -- 新高亮组的名称
		vim.api.nvim_set_hl(0, new_hl_name, { fg = list_filepath })

		local new_hl_id = vim.api.nvim_get_hl_id_by_name(new_hl_name)
		print("New highlight group ID: " .. new_hl_id)

		return new_hl_id
	else
		return api.nvim_get_hl_id_by_name("@" .. name .. "." .. lang)
	end
end, function(_, capture, lang)
	return lang .. tostring(capture)
end)

local function highlight_contexts(bufnr, ctx_bufnr, contexts)
	vim.api.nvim_buf_clear_namespace(ctx_bufnr, ns, 0, -1)

	-- copy_option("tabstop", bufnr, ctx_bufnr)

	local parser = vim.treesitter.get_parser(bufnr)
	local srow, erow = get_contexts_range(contexts)
	parser:parse({ srow, erow })

	parser:for_each_tree(function(tstree, ltree)
		local lang = ltree:lang()
		local query = vim.treesitter.query.get(lang, "highlights")

		if not query then
			return
		end

		local p = 0
		local offset = 0
		for i, context in ipairs(contexts) do
			local start_row, end_row, end_col = context[1], context[3], context[4]

			for capture, node, metadata in query:iter_captures(tstree:root(), bufnr, start_row, end_row + 1) do
				local range = vim.treesitter.get_range(node, bufnr, metadata[capture])
				local nsrow, nscol, nerow, necol = range[1], range[2], range[4], range[5]

				if nerow > end_row or (nerow == end_row and necol > end_col and end_col ~= -1) then
					break
				end

				if nsrow >= start_row then
					local msrow = offset + (nsrow - start_row)
					local merow = offset + (nerow - start_row)
					local priority = tonumber(metadata.priority) or vim.highlight.priorities.treesitter

					if i ~= #contexts then
						add_extmark(ctx_bufnr, msrow, nscol, {
							end_row = merow,
							end_col = necol,
							priority = priority + p,
							---@diagnostic disable-next-line: param-type-mismatch
							hl_group = hl_from_capture_darken(query, capture, lang),
							conceal = metadata.conceal,
						})
					else
						add_extmark(ctx_bufnr, msrow, nscol, {
							end_row = merow,
							end_col = necol,
							priority = priority + p,
							---@diagnostic disable-next-line: param-type-mismatch
							hl_group = hl_from_capture(query, capture, lang),
							conceal = metadata.conceal,
						})
					end

					-- TODO(lewis6991): Extmarks of equal priority appear to apply
					-- highlights differently between ephemeral and non-ephemeral:
					-- - ephemeral:  give priority to the last mark applied
					-- - non-ephemeral: give priority to the first mark applied
					--
					-- In order the match the behaviour of main highlighter which uses
					-- ephemeral marks, make sure increase the priority as we apply marks.
					p = p + 1
				end
			end
			offset = offset + get_range_height(context)
		end
	end)
end

--- @param bufnr integer
--- @param winid integer?
--- @param width integer
--- @param height integer
--- @param col integer
--- @param ty string
--- @param hl string
--- @return integer
local function display_window(bufnr, width, height, row, col, ty, hl)
	-- if not winid or not api.nvim_win_is_valid(winid) then
	-- local sep = config.separator and { config.separator, "TreesitterContextSeparator" } or nil
	winid = api.nvim_open_win(bufnr, false, {
		relative = "editor",
		width = math.floor(width * 0.7),
		height = height,
		row = row,
		col = col,
		focusable = true,
		style = "minimal",
		-- border = { " ", " ", "", " ", " ", " ", " ", " " },
		border = "rounded",
		-- noautocmd = true,
		zindex = 30,
		-- border = sep and { "", "", "", "", sep, sep, sep, "" } or nil,
	})
	vim.w[winid][ty] = true
	vim.wo[winid].wrap = false
	vim.wo[winid].foldenable = false
	vim.wo[winid].winhl = "NormalFloat:" .. hl
	-- else
	-- api.nvim_win_set_config(winid, {
	-- 	win = api.nvim_get_current_win(),
	-- 	relative = "win",
	-- 	width = width,
	-- 	height = height,
	-- 	row = 0,
	-- 	col = col,
	-- })
	-- end
	return winid
end

--- @param bufnr integer
--- @param lines string[]
--- @return boolean
local function set_lines(bufnr, lines)
	local clines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	-- local redraw = false
	-- if #clines ~= #lines then
	-- 	redraw = true
	-- else
	-- 	for i, l in ipairs(clines) do
	-- 		if l ~= lines[i] then
	-- 			redraw = true
	-- 			break
	-- 		end
	-- 	end
	-- end
	--
	-- if redraw then
	api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modified = false
	-- end

	return true
end
local row = 4
--- @param bufnr integer
--- @param ctx_bufnr integer
--- @param winid integer
--- @param ctx_ranges Range4[]
--- @param ctx_lines string[]
--- @param cursorlinenr integer
function M.open(bufnr, ctx_bufnr, winid, ctx_ranges, ctx_lines, cursorlinenr)
	-- local gutter_width = get_gutter_width(winid)
	local win_width = math.max(1, api.nvim_win_get_width(winid))
	local win_height = #ctx_lines
	--
	-- local gbufnr, ctx_bufnr = get_bufs()
	--
	-- if config.line_numbers and (vim.wo[winid].number or vim.wo[winid].relativenumber) then
	-- 	gutter_winid = display_window(
	-- 		gbufnr,
	-- 		gutter_winid,
	-- 		gutter_width,
	-- 		win_height,
	-- 		0,
	-- 		"treesitter_context_line_number",
	-- 		"TreesitterContextLineNumber"
	-- 	)
	-- 	render_lno(winid, gbufnr, ctx_ranges, gutter_width)
	-- else
	-- 	win_close(gutter_winid)
	-- end

	context_winid = display_window(ctx_bufnr, win_width, win_height, row, 45, "treesitter_context", "TreesitterContext")

	row = row + #ctx_lines + 2
	table.insert(context_winids, context_winid)
	vim.keymap.set("n", "<CR>", function()
		Jump_to_mark(cursorlinenr)
	end, { buffer = ctx_bufnr })
	-- vim.api.nvim_set_current_win(context_winid)
	-- vim.api.nvim_buf_set_keymap(
	-- 	ctx_bufnr,
	-- 	"n",
	-- 	"<CR>",
	-- 	"<cmd>lua Jump_to_mark(cursorlinenr)<CR>",
	-- 	{ noremap = true, silent = true }
	-- )
	vim.api.nvim_buf_set_keymap(
		ctx_bufnr,
		"n",
		"q",
		"<cmd>lua vim.api.nvim_win_hide(0)<CR>",
		{ noremap = true, silent = true }
	)
	if not set_lines(ctx_bufnr, ctx_lines) then
		-- Context didn't change, can return here
		return
	end

	highlight_contexts(bufnr, ctx_bufnr, ctx_ranges)
	-- highlight_bottom(ctx_bufnr, win_height - 1, "TreesitterContextBottom")
	-- horizontal_scroll_contexts()
end
return M
