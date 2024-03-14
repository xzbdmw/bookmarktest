local M = {}
local bookmarks = {}
local navic = require("nvim-navic") -- Require the navic module for LSP navigation

-- Creates an auto-command to attach navic to LSP clients as they attach to buffers
function M.create_navic_attacher()
	vim.api.nvim_create_autocmd("LspAttach", {
		desc = "Navic Attacher", -- Description for the auto-command
		callback = function(a)
			print("Attaching navic")
			local client = vim.lsp.get_client_by_id(a.data.client_id)
			if client.server_capabilities["documentSymbolProvider"] then
				navic.attach(client, a.buf) -- Attach navic if the LSP client supports document symbols
			end
		end,
	})
end

-- Sets virtual text in the status column for the current line
local function set_status_column_text()
	local bufnr = vim.api.nvim_get_current_buf() -- Get the current buffer number
	local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- Get the current line number, Lua indexes start at 1 but API expects 0
	local ns_id = vim.api.nvim_create_namespace("status_column") -- Create a namespace, reuse the ID if already created

	-- Set virtual text for the current line
	local id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
		virt_text = { { "W", "Comment" } }, -- Text and style to display, "Comment" is a highlight group
		virt_text_pos = "eol", -- Position the virtual text at the end of the line to simulate a status column
		hl_mode = "combine", -- Allow combining with existing highlight groups
	})
	return id
end

-- Adds a bookmark
local function add_mark(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local line_nr = vim.api.nvim_win_get_cursor(0)[1]
	local line_content = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] -- Get the content of the current line
	local data = navic.get_data()
	local mark_name = ""

	-- Sequentially concatenate the context list using a for loop
	for _, context in ipairs(data) do
		mark_name = mark_name .. context.icon .. (context.name or "") .. "-> "
	end
	local ext_id = set_status_column_text()
	mark_name = mark_name:sub(1, -4) -- Remove the last " > "
	table.insert(bookmarks, {
		ext_id = ext_id,
		name = mark_name,
		line_content = line_content, -- Save the current line content
		line = line_nr,
		bufnr = bufnr,
		path = vim.api.nvim_buf_get_name(bufnr),
	})
	print(vim.inspect(bookmarks))
end

-- Prints all extmarks in the current buffer
local function print_all_extmarks()
	local bufnr = vim.api.nvim_get_current_buf() -- Get the ID of the current buffer

	local ns_id = vim.api.nvim_create_namespace("status_column") -- Get or create the ID of the namespace

	-- Retrieve all extmarks in the specified namespace for the current buffer
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { 0, 0 }, { -1, -1 }, {})

	-- Iterate and print information of extmarks
	for _, mark in ipairs(extmarks) do
		local id, row, col = unpack(mark)
		print(string.format("ExtMark ID: %s, Row: %s, Col: %s", id, row, col))
	end
end

local function update_bookmarks_position(bufnr, ns_id)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	ns_id = ns_id or vim.api.nvim_create_namespace("status_column") -- 请确保这与设置extmark时使用的是同一个命名空间ID

	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { 0, 0 }, { -1, -1 }, {})
	for _, mark in ipairs(bookmarks) do
		for _, extmark in ipairs(extmarks) do
			local extmark_id, extmark_row, _ = unpack(extmark)
			if mark.ext_id == extmark_id then
				mark.line = extmark_row + 1
				break
			end
		end
	end

	print(vim.inspect(bookmarks))
end

local function open_bookmarks_window()
	local bufnr = vim.api.nvim_get_current_buf()
	local ns_id = vim.api.nvim_create_namespace("status_column")
	update_bookmarks_position(bufnr, ns_id)

	local lines = {}

	for _, mark in ipairs(bookmarks) do
		mark.line_content = mark.line_content:gsub("^%s+", "")
		local truncated_line_content = mark.line_content
		if #truncated_line_content > 40 then
			truncated_line_content = truncated_line_content:sub(1, 37) .. "..."
		end

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
	local line_nr = vim.fn.line(".")
	local mark = bookmarks[line_nr]
	if mark then
		vim.api.nvim_win_close(0, true)
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
