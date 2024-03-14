local M = {}
local bookmarks = {}
local navic = require("nvim-navic")

function M.create_navic_attacher()
	vim.api.nvim_create_autocmd("LspAttach", {
		desc = "Navic Attacher",
		-- group = vim.api.nvim_create_augroup(GROUP_NAVIC_ATTACHER, {}),
		callback = function(a)
			print("I'm attach navic")
			local client = vim.lsp.get_client_by_id(a.data.client_id)
			if client.server_capabilities["documentSymbolProvider"] then
				navic.attach(client, a.buf)
			end
		end,
	})
end

local function set_status_column_text()
	local bufnr = vim.api.nvim_get_current_buf() -- 获取当前缓冲区编号
	local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 获取当前行号，Lua索引从1开始但API期望从0开始
	local ns_id = vim.api.nvim_create_namespace("status_column") -- 创建一个命名空间，如果已经创建可以重用ID

	-- 为当前行设置虚拟文本
	local id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
		virt_text = { { "W", "Comment" } }, -- 显示的文本和样式，"Comment"是高亮组，可根据主题和偏好调整
		virt_text_pos = "eol", -- 将虚拟文本设置在行末尾，模拟状态栏效果
		hl_mode = "combine", -- 允许与现有高亮组合
	})
	return id
end

local function add_mark(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local line_nr = vim.api.nvim_win_get_cursor(0)[1]
	local line_content = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] -- 获取当前行内容
	local data = navic.get_data()
	local mark_name = ""

	-- 使用for循环顺序拼接contexts列表
	for _, context in ipairs(data) do
		mark_name = mark_name .. context.icon .. (context.name or "") .. "-> "
	end
	local ext_id = set_status_column_text()
	mark_name = mark_name:sub(1, -4) -- 移除最后的" > "
	table.insert(bookmarks, {
		ext_id = ext_id,
		name = mark_name,
		line_content = line_content, -- 保存当前行内容
		line = line_nr,
		bufnr = bufnr,
		path = vim.api.nvim_buf_get_name(bufnr),
	})
	print(vim.inspect(bookmarks))
end

local function print_all_extmarks()
	local bufnr = vim.api.nvim_get_current_buf() -- 获取当前缓冲区的ID

	local ns_id = vim.api.nvim_create_namespace("status_column") -- 获取或创建命名空间的ID

	-- 获取当前缓冲区在指定命名空间下的所有扩展标记
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { 0, 0 }, { -1, -1 }, {})

	-- 遍历并打印扩展标记的信息
	for _, mark in ipairs(extmarks) do
		local id, row, col = unpack(mark)
		print(string.format("ExtMark ID: %s, Row: %s, Col: %s", id, row, col))
	end
end

local function update_bookmarks_position(bufnr, ns_id)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	ns_id = ns_id or vim.api.nvim_create_namespace("status_column") -- 请确保这与设置extmark时使用的是同一个命名空间ID

	-- 获取该命名空间下的所有extmark
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { 0, 0 }, { -1, -1 }, {})
	for _, mark in ipairs(bookmarks) do
		for _, extmark in ipairs(extmarks) do
			local extmark_id, extmark_row, _ = unpack(extmark)
			if mark.ext_id == extmark_id then
				-- 更新书签的行号
				mark.line = extmark_row + 1 -- 转换为用户习惯的行号（从1开始）
				break
			end
		end
	end

	-- 更新完毕后可以重新打印或显示更新后的书签信息
	print(vim.inspect(bookmarks))
end

local function open_bookmarks_window()
	local bufnr = vim.api.nvim_get_current_buf()
	local ns_id = vim.api.nvim_create_namespace("status_column") -- 确保与设置extmark时的命名空间ID相同
	update_bookmarks_position(bufnr, ns_id)

	local lines = {}

	for _, mark in ipairs(bookmarks) do
		mark.line_content = mark.line_content:gsub("^%s+", "")
		-- 检查并截断line_content以保持最大长度为60
		local truncated_line_content = mark.line_content
		if #truncated_line_content > 40 then
			truncated_line_content = truncated_line_content:sub(1, 37) .. "..."
		end

		-- 使用截断后的line_content构建要插入的字符串
		table.insert(lines, string.format("%s - => %d | %s", truncated_line_content, mark.line, mark.name))
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local width = vim.api.nvim_get_option("columns")
	local height = vim.api.nvim_get_option("lines")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",

		width = math.floor(width * 0.7),

		col = math.floor(width * 0.15),
		height = math.floor(height * 0.7),
		row = math.floor(height * 0.15),
	})

	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "<cmd>lua Jump_to_mark()<CR>", { noremap = true, silent = true })
	print_all_extmarks()
	vim.api.nvim_buf_set_keymap(
		buf,
		"n",
		"q",
		"<cmd>lua vim.api.nvim_win_close(0, true)<CR>",
		{ noremap = true, silent = true }
	)
end

function Jump_to_mark()
	local line_nr = vim.fn.line(".") -- 获取当前行号
	local mark = bookmarks[line_nr] -- 假设每一行对应一个标记
	if mark then
		vim.api.nvim_win_close(0, true)
		-- vim.api.nvim_set_current_buf(mark.bufnr)
		vim.api.nvim_win_set_cursor(0, { mark.line, 0 })
	end
end

function M.setup()
	M.create_navic_attacher()
end

function A()
	function B()
		function C()
			print("c")
			print("b")
		end
	end
end

vim.keymap.set("n", "mm", function()
	add_mark(0)
end)

vim.keymap.set("n", "<leader>pp", function()
	local data = navic.get_data()
	-- __AUTO_GENERATED_PRINT_VAR_START__
	print([==[function data:]==], vim.inspect(data)) -- __AUTO_GENERATED_PRINT_VAR_END__
end)

vim.keymap.set("n", "ml", function()
	open_bookmarks_window()
end)
vim.keymap.set("n", "<leader>mp", function()
	print_all_extmarks()
end)
return M
