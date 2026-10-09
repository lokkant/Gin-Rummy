-- Everything that "takes time" on the table in one place: cards flying to a pile, pauses, timers,
function Animations()
    local self = {}
    self.list = {}

    function self:add(animation)
        table.insert(self.list, animation)
        return animation
    end

    function self:move_card(card, get_target, speed, options)
        options = options or {}

        return self:add({
            tag = options.tag,
            blocking = options.blocking,
            on_finish = options.on_finish,
            step = function(dt)
                local target_x, target_y = get_target()
                card:move_to(dt, speed, target_x, target_y)
                return card.x == target_x and card.y == target_y
            end,
            draw = function()
                card:draw()
            end
        })
    end

    function self:delay(duration, options)
        options = options or {}

        local remaining = duration

        return self:add({
            tag = options.tag,
            blocking = options.blocking,
            on_finish = options.on_finish,
            step = function(dt)
                remaining = remaining - dt
                return remaining <= 0
            end
        })
    end

    function self:wait_for(start, options)
        options = options or {}

        local is_done = false

        local animation = self:add({
            tag = options.tag,
            blocking = options.blocking,
            on_finish = options.on_finish,
            step = function()
                return is_done
            end
        })

        start(function()
            is_done = true
        end)

        return animation
    end

    function self:update(dt)
        local running = {}
        for _, animation in ipairs(self.list) do
            table.insert(running, animation)
        end

        local finished = {}
        for _, animation in ipairs(running) do
            if not animation.removed and animation.step(dt) then
                animation.removed = true
                table.insert(finished, animation)
            end
        end

        local remaining = {}
        for _, animation in ipairs(self.list) do
            if not animation.removed then
                table.insert(remaining, animation)
            end
        end
        self.list = remaining

        -- after the list is consistent again, so on_finish may add animations
        for _, animation in ipairs(finished) do
            if animation.on_finish then
                animation.on_finish()
            end
        end
    end

    function self:draw()
        for _, animation in ipairs(self.list) do
            if animation.draw then
                animation.draw()
            end
        end
    end

    function self:is_busy()
        for _, animation in ipairs(self.list) do
            if animation.blocking then
                return true
            end
        end
        return false
    end

    function self:is_active(tag)
        for _, animation in ipairs(self.list) do
            if animation.tag == tag then
                return true
            end
        end
        return false
    end

    function self:cancel(tag)
        local remaining = {}
        for _, animation in ipairs(self.list) do
            if animation.tag == tag then
                animation.removed = true
            else
                table.insert(remaining, animation)
            end
        end
        self.list = remaining
    end

    return self
end

return Animations
