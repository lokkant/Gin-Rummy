-- A simple vertical settings form (client side) for the host screens: rows with a label on the left and a
-- control on the right - a number field, a text field, an ON/OFF switch or a "choice" button that cycles
-- through a list - plus section headers. The form scrolls with the mouse wheel when the rows do not fit.
-- Used by scenes/host_setup.lua and scenes/config_editor.lua. A row is a table:
--   {kind = "header", label}
--   {kind = "number", key, label, text, min, max, integer}   text is what is typed
--   {kind = "text", key, label, text, max_length, allowed}    allowed: Lua pattern of the characters accepted
--   {kind = "bool", key, label, value}
--   {kind = "choice", key, label, options (list of strings), index, on_change (optional function(row))}

local love = require "love"
local ui = require "ui"

local form = {}

-- Height of a row and the gap kept around its control, in pixels.
local ROW_HEIGHT = 40
local CONTROL_PADDING = 4
-- Share of the form's width taken by the controls (the labels get the rest).
local CONTROL_SHARE = 0.34
-- Longest text a number field accepts.
local MAX_NUMBER_LENGTH = 12
-- Seconds of one blink of the caret.
local CARET_PERIOD = 1.0

local FIELD_COLOR = {0.2, 0.2, 0.2}
local FIELD_FOCUS_COLOR = {0.28, 0.28, 0.38}
local FIELD_BORDER_COLOR = {0.8, 0.8, 0.8}
local BAD_COLOR = {0.9, 0.3, 0.3}
local ON_COLOR = {0.3, 0.6, 0.3, 1}
local OFF_COLOR = {0.45, 0.3, 0.3, 1}
local CHOICE_COLOR = {0.25, 0.4, 0.65, 1}
local HEADER_COLOR = {1, 0.85, 0.4}

-- Creates a form from a list of rows. fonts = {label, field}: the fonts of the labels and of the controls.
function form.new(rows, fonts)
    return {rows = rows, fonts = fonts, focus = nil, fresh = false, scroll = 0,
            area = {x = 0, y = 0, w = 100, h = 100}}
end

-- Sets the rectangle {x, y, w, h} the form occupies on the screen (call again after a resize).
function form.set_area(self, area)
    self.area = area
    form.clamp_scroll(self)
end

-- Total height of all rows.
local function get_content_height(self)
    return #self.rows * ROW_HEIGHT
end

-- Keeps the scroll position inside the content.
function form.clamp_scroll(self)
    local max_scroll = math.max(0, get_content_height(self) - self.area.h)
    self.scroll = math.max(0, math.min(max_scroll, self.scroll))
end

-- Returns the rectangle of row i's control on the screen.
local function get_control_rect(self, i)
    local area = self.area
    local width = area.w * CONTROL_SHARE
    local y = area.y + (i - 1) * ROW_HEIGHT - self.scroll

    return {x = area.x + area.w - width, y = y + CONTROL_PADDING, w = width,
            h = ROW_HEIGHT - 2 * CONTROL_PADDING}
end

-- Returns the number a number row holds, or nil and a message when the text is not a usable value.
local function read_number(row)
    local value = tonumber(row.text)
    if value == nil then return nil, row.label .. ": type a number" end

    if row.integer and value ~= math.floor(value) then
        return nil, row.label .. ": must be a whole number"
    end

    if (row.min and value < row.min) or (row.max and value > row.max) then
        return nil, string.format("%s: must be between %s and %s", row.label, row.min, row.max)
    end

    return value
end

-- Returns the row with the given key, or nil.
function form.find_row(self, key)
    for _, row in ipairs(self.rows) do
        if row.key == key then return row end
    end
    return nil
end

-- Returns the value of the row with this key: a number (nil when the text is not valid), a boolean, the
-- text, or for a choice the chosen option.
function form.get_value(self, key)
    local row = form.find_row(self, key)
    if row == nil then return nil end

    if row.kind == "number" then return (read_number(row)) end
    if row.kind == "bool" then return row.value end
    if row.kind == "choice" then return row.options[row.index] end
    return row.text
end

-- Puts a value into the row with this key (a number is shown as text).
function form.set_value(self, key, value)
    local row = form.find_row(self, key)
    if row == nil then return end

    if row.kind == "number" then
        row.text = value == math.floor(value) and string.format("%d", value) or string.format("%.10g", value)
    elseif row.kind == "bool" then
        row.value = value
    elseif row.kind == "choice" then
        row.index = value
    else
        row.text = value
    end
end

-- Reads every number and switch of the form into a table key -> value. Returns nil and a message for the
-- player when a number is not valid (the first bad field gets the focus).
function form.read_values(self)
    local values = {}

    for i, row in ipairs(self.rows) do
        if row.kind == "number" then
            local value, problem = read_number(row)
            if value == nil then
                form.focus_row(self, i)
                return nil, problem
            end
            values[row.key] = value
        elseif row.kind == "bool" then
            values[row.key] = row.value
        end
    end

    return values
end

-- Gives the focus to row i if it has a text control, and scrolls it into view.
function form.focus_row(self, i)
    local row = self.rows[i]

    if row ~= nil and (row.kind == "number" or row.kind == "text") then
        self.focus = i
        self.fresh = true

        local top = (i - 1) * ROW_HEIGHT
        if top < self.scroll then
            self.scroll = top
        elseif top + ROW_HEIGHT > self.scroll + self.area.h then
            self.scroll = top + ROW_HEIGHT - self.area.h
        end
        form.clamp_scroll(self)
    else
        self.focus = nil
    end
end

-- Moves the focus to the next (step = 1) or previous (step = -1) text control.
local function move_focus(self, step)
    local start = self.focus or (step > 0 and 0 or #self.rows + 1)

    for i = start + step, step > 0 and #self.rows or 1, step do
        local row = self.rows[i]
        if row.kind == "number" or row.kind == "text" then
            form.focus_row(self, i)
            return
        end
    end
end

-- Cycles a choice row (step = 1 forward, -1 backward) and tells its on_change.
local function cycle_choice(row, step)
    row.index = (row.index - 1 + step) % #row.options + 1

    if row.on_change then row.on_change(row) end
end

-- Left click: focuses a field, flips a switch, cycles a choice (a right click cycles backwards). Returns
-- true when the click was on the form's area.
function form.mousepressed(self, x, y, button)
    local area = self.area
    if x < area.x or x > area.x + area.w or y < area.y or y > area.y + area.h then return false end
    if button ~= 1 and button ~= 2 then return true end

    for i, row in ipairs(self.rows) do
        local rect = get_control_rect(self, i)

        if row.kind ~= "header" and ui.point_in_rect(x, y, rect) then
            if row.kind == "bool" and button == 1 then
                row.value = not row.value
                self.focus = nil
            elseif row.kind == "choice" then
                cycle_choice(row, button == 1 and 1 or -1)
                self.focus = nil
            elseif button == 1 then
                form.focus_row(self, i)
            end

            return true
        end
    end

    self.focus = nil
    return true
end

-- Typed text goes into the focused field; the first character typed after the focus arrived replaces the
-- old text.
function form.textinput(self, t)
    local row = self.focus and self.rows[self.focus]
    if row == nil then return end

    local allowed = row.kind == "number" and "[%d%.%-]" or row.allowed or "."
    local accepted = {}
    for character in t:gmatch(".") do
        if character:match(allowed) then table.insert(accepted, character) end
    end
    if #accepted == 0 then return end

    local limit = row.kind == "number" and MAX_NUMBER_LENGTH or row.max_length or 40
    local text = self.fresh and "" or row.text
    self.fresh = false

    row.text = string.sub(text .. table.concat(accepted), 1, limit)
end

-- Backspace edits the focused field (Ctrl+Backspace clears it), Tab / Down / Enter go to the next field and
-- Shift+Tab / Up to the previous one, Ctrl+V pastes. Returns true when the key was used.
function form.keypressed(self, key)
    local row = self.focus and self.rows[self.focus]
    local ctrl_down = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    local shift_down = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")

    if key == "tab" then
        move_focus(self, shift_down and -1 or 1)
        return true
    elseif key == "down" or key == "return" or key == "kpenter" then
        if row == nil and key ~= "down" then return false end
        move_focus(self, 1)
        return true
    elseif key == "up" then
        move_focus(self, -1)
        return true
    end

    if row == nil then return false end

    if key == "backspace" then
        if ctrl_down or self.fresh then
            row.text = ""
        else
            row.text = string.sub(row.text, 1, #row.text - 1)
        end
        self.fresh = false
        return true
    elseif key == "v" and ctrl_down then
        form.textinput(self, love.system.getClipboardText() or "")
        return true
    end

    return false
end

-- Mouse wheel scrolls the rows (dy > 0 = up).
function form.wheelmoved(self, dy)
    self.scroll = self.scroll - dy * ROW_HEIGHT
    form.clamp_scroll(self)
end

-- Draws one control into its rectangle.
local function draw_control(self, i, row, rect)
    love.graphics.setFont(self.fonts.field)

    if row.kind == "bool" then
        ui.draw_button(rect, row.value and "ON" or "OFF", row.value and ON_COLOR or OFF_COLOR)
    elseif row.kind == "choice" then
        ui.draw_button(rect, row.options[row.index], CHOICE_COLOR)
    else
        local is_focused = self.focus == i
        local is_bad = row.kind == "number" and read_number(row) == nil

        love.graphics.setColor(is_focused and FIELD_FOCUS_COLOR or FIELD_COLOR)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(is_bad and BAD_COLOR or FIELD_BORDER_COLOR)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)

        -- the caret blinks, and is hidden while the next keystroke would replace the whole text
        local blink_on = love.timer.getTime() % CARET_PERIOD < CARET_PERIOD / 2
        local caret_visible = is_focused and not self.fresh and blink_on
        local text_y = rect.y + rect.h / 2 - self.fonts.field:getHeight() / 2

        love.graphics.setColor(is_bad and BAD_COLOR or {1, 1, 1})
        love.graphics.printf(row.text .. (caret_visible and "|" or ""), rect.x + 6, text_y, rect.w - 12,
                             "right")
    end
end

-- Draws the visible rows, clipped to the form's area, and a thin scroll bar when the rows do not fit.
function form.draw(self)
    local area = self.area
    love.graphics.setScissor(area.x, area.y, area.w, area.h)

    for i, row in ipairs(self.rows) do
        local rect = get_control_rect(self, i)
        local row_y = rect.y - CONTROL_PADDING

        if row_y + ROW_HEIGHT >= area.y and row_y <= area.y + area.h then
            local text_y = row_y + ROW_HEIGHT / 2 - self.fonts.label:getHeight() / 2
            love.graphics.setFont(self.fonts.label)

            if row.kind == "header" then
                -- section titles sit a little lower, closer to the rows they introduce
                love.graphics.setColor(HEADER_COLOR)
                love.graphics.printf(row.label, area.x, text_y + 6, area.w, "left")
            else
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.printf(row.label, area.x, text_y, area.w - rect.w - 12, "left")
                draw_control(self, i, row, rect)
            end
        end
    end

    local content = get_content_height(self)
    if content > area.h then
        local bar_height = area.h * area.h / content
        local bar_y = area.y + (area.h - bar_height) * self.scroll / (content - area.h)

        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.rectangle("fill", area.x + area.w + 6, bar_y, 4, bar_height)
    end

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
end

-- Height of one row in pixels (for the scenes that size the form to its rows).
form.ROW_HEIGHT = ROW_HEIGHT

return form
