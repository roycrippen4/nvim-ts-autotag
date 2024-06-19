--- PREAMBLE:
---
--- This is a possible new strategy for the autotag plugin.
--- This implemnetation is incomplete and is just a proof of concept.
--- It has been taken from my personal config and is not ready for production.
--- It is also specific to svelte files only at the moment, but should be easy to adapt to other filetypes.
---
--- The core idea is to use the treesitter API to get the root node of the file and then walk the tree to get all the elements.
--- We can use the element nodes to get the start and end tags of each element node.
--- Then we can build a list of all the start and end tag positions with their text.
--- We can then use the `TextChanged` autocmd to discover the changes to the AST.
--- We should be able to compare the current tag positions with the new tag positions to determine if a tag has been changed.
--- We can then update the buffer text with the stored positions if a tag has been changed and needs to be updated.
--- This is a very naive implementation and will not work in all cases, but may serve as a starting point moving forward.
---
--- I plan on attempting to integrate this into the plugin when I have the free time to work on this.
--- But with all things open source, that time will likely be few and far between.

--- @class Tag
--- @field text string
--- @field pos integer[]

--- @class TagPosition
--- @field start_tag Tag
--- @field end_tag Tag

local autotag_group = vim.api.nvim_create_augroup('autotag_group', { clear = true })

--- Gets the root node of the current buffer.
--- This is a really poor implemnetation, imo.
--- But it does work.
--- @return TSNode|nil
local function get_root()
  local node = vim.treesitter.get_node({ bufnr = 0, { 0, 0 }, 'svelte' })

  if not node then
    return
  end

  local root = node:parent()

  while root do
    if not root:parent() then
      break
    end

    root = root:parent()
  end

  return root
end

--- Recursively walks the tree and collects all the element nodes
--- @param node TSNode The current node to walk
--- @param elements TSNode[] The list of elements to collect
--- @return TSNode[]
local function walk_tree(node, elements)
  for child in node:iter_children() do
    if child:type() == 'element' then
      table.insert(elements, child)
    end
    walk_tree(child, elements)
  end

  return elements
end

--- Collects all the element nodes from the root node
--- @param root TSNode The root node of the tree
--- @return TSNode[]
local function get_elements(root)
  --- @type TSNode[]
  local elements = {}

  return walk_tree(root, elements)
end

--- Takes a given node and returns the pos and text of the start and end tags
--- @param node TSNode The element node to get the tag info from
--- @return TagPosition
local function get_tag_info(node)
  local position = {}

  for child in node:iter_children() do
    if child:type() == 'start_tag' then
      local start_tag_name_node = child:child(1)
      assert(start_tag_name_node)

      local a, b, c, d = vim.treesitter.get_node_range(start_tag_name_node)
      position.start_tag = {
        text = vim.treesitter.get_node_text(start_tag_name_node, 0),
        pos = { a, b, c, d },
      }
    end

    if child:type() == 'end_tag' then
      local end_tag_name_node = child:child(1)
      assert(end_tag_name_node)

      local start_row, start_col, end_row, end_col = vim.treesitter.get_node_range(end_tag_name_node)
      position.end_tag = {
        text = vim.treesitter.get_node_text(end_tag_name_node, 0),
        pos = { start_row, start_col, end_row, end_col },
      }
    end
  end

  return position
end

--- Gets all tag positions from a list of element nodes
--- @param elements TSNode[] The list of element nodes to get the tag positions from
--- @return TagPosition[]
local function get_all_tag_positions(elements)
  --- @type TagPosition[]
  local positions = {}

  for _, element in ipairs(elements) do
    local pos = get_tag_info(element)

    if not vim.tbl_isempty(pos) then
      table.insert(positions, pos)
    end
  end

  return positions
end

--- This is the table that will hold the current tag positions
--- @type TagPosition[]
---@diagnostic disable-next-line
local positions = {}

--- This function will be called when the `TextChanged` autocmd is triggered.
--- It should interrogate the two tables to determine if a tag has been changed and react accordingly.
--- @param new_positions TagPosition[] The new tag positions to compare with the current positions
--- @return TagPosition[]
local function update_on_change(new_positions)
  for _, new_pos in ipairs(new_positions) do
    if new_pos.start_tag.text ~= new_pos.end_tag.text then
      print(vim.inspect(new_pos))
    end
  end
  return new_positions
end

-- Builds the initial tag positions
vim.api.nvim_create_autocmd('FileType', {
  group = autotag_group,
  pattern = 'svelte',
  callback = function()
    local root = get_root()

    if not root then
      return
    end

    ---@diagnostic disable-next-line
    positions = get_all_tag_positions(get_elements(root))
  end,
})

-- Builds the new tag positions on change
vim.api.nvim_create_autocmd('TextChanged', {
  group = autotag_group,
  pattern = '*.svelte',
  callback = function()
    local root = get_root()

    if not root then
      return
    end

    local new = get_all_tag_positions(get_elements(root))
    update_on_change(new)
  end,
})
