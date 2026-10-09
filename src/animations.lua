-- A small scheduler for everything that "takes time" on the table: cards flying to a pile, pauses, timers
-- and waiting for an outside event. Global constructor-style class: Animations() returns an independent
-- list; the game scene keeps one in state.animations and client/messages.lua fills it.
-- An animation is a table {tag, blocking, on_finish, step(dt) -> done, draw, card}. `blocking` animations
-- hold back the processing of server messages (is_busy), `tag` names a group for is_active / cancel.

-- Creates a scheduler with an empty animation list.
function Animations()
    local self = {}
    self.list = {}

    -- Registers an animation table and returns it.
    function self:add(animation)
        table.insert(self.list, animation)
        return animation
    end

    -- Flies `card` towards the point returned by get_target() at `speed` pixels per second; get_target is
    -- called every frame, so the target may move. Finished when the card has arrived. The animation draws
    -- the card itself (the card is no longer in a hand). options: tag, blocking, on_finish (all optional).
    function self:move_card(card, get_target, speed, options)
        options = options or {}

        return self:add({
            tag = options.tag,
            blocking = options.blocking,
            on_finish = options.on_finish,
            card = card,
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

    -- A pause of `duration` seconds. options as in move_card.
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

    -- A pause without a timer: it ends when the function passed to `start` calls the `done` callback it
    -- receives. start(done) runs immediately. options as in move_card.
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

    -- Advances every animation by dt, drops the finished ones and then calls their on_finish.
    -- The list is copied before stepping so that animations added or cancelled meanwhile (cancel replaces
    -- self.list) cannot disturb the loop; cancelled ones are flagged `removed` and skipped.
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

    -- Draws the animations that have a draw function (flying cards), in the order they were added.
    function self:draw()
        for _, animation in ipairs(self.list) do
            if animation.draw then
                animation.draw()
            end
        end
    end

    -- Calls fn(card) for every card that is currently flying (used to rescale cards after a window resize).
    function self:each_card(fn)
        for _, animation in ipairs(self.list) do
            if animation.card then
                fn(animation.card)
            end
        end
    end

    -- True while any blocking animation is running; the message queue waits in the meantime.
    function self:is_busy()
        for _, animation in ipairs(self.list) do
            if animation.blocking then
                return true
            end
        end
        return false
    end

    -- True if an animation with this tag is running.
    function self:is_active(tag)
        for _, animation in ipairs(self.list) do
            if animation.tag == tag then
                return true
            end
        end
        return false
    end

    -- Removes every animation with this tag; their on_finish is NOT called.
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
