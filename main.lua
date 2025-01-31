eDebug = false
if arg[2] == "debug" then
    eDebug = true
    require("lldebugger").start()
end

-- Constants for walkability states
local NON_WALKABLE = 0
local WALKABLE = 1
local MIXED = 2

function love.load()
    -- Load the image data
    local imagePath = "collisionTest.jpg" -- Replace with your image path
    local imageData = love.image.newImageData(imagePath)

    -- Image dimensions
    local width, height = imageData:getWidth(), imageData:getHeight()
    local cellSize = 32

    -- Collision data structure
    local collisionData = {
        width = width,
        height = height,
        cellSize = cellSize,
        cells = {} -- 2D grid: cells[gridX][gridY] = cell data
    }

    -- State for incremental processing
    local state = {
        imageData = imageData,
        collisionData = collisionData,
        currentX = 0,
        currentY = 0,
        isProcessing = true,
        progress = 0
    }

    -- Save state to global for access in update/draw
    collisionState = state

    -- Set up debug font
    love.graphics.setNewFont(12)
end

function love.update(dt)
    local state = collisionState
    if not state.isProcessing then return end

    -- Process a chunk of pixels (e.g., 32x32 cells per frame)
    local chunkSize = 32 -- Number of cells to process per frame
    local cellsProcessed = 0
    while cellsProcessed < chunkSize and state.isProcessing do
        -- Get current grid coordinates
        local gridX = math.floor(state.currentX / state.collisionData.cellSize) + 1
        local gridY = math.floor(state.currentY / state.collisionData.cellSize) + 1

        -- Initialize the grid row if it doesn't exist
        if not state.collisionData.cells[gridX] then
            state.collisionData.cells[gridX] = {}
        end

        -- Create the cell
        local cell = {
            x = state.currentX,
            y = state.currentY,
            isWalkable = WALKABLE, -- Assume walkable by default
            data = {} -- Store walkable pixels if the cell is mixed
        }

        -- Check each pixel in the cell
        local hasWhite, hasBlack = false, false
        for py = state.currentY, math.min(state.currentY + state.collisionData.cellSize - 1, state.imageData:getHeight() - 1) do
            for px = state.currentX, math.min(state.currentX + state.collisionData.cellSize - 1, state.imageData:getWidth() - 1) do
                local r, g, b, a = state.imageData:getPixel(px, py)
                local isWhite = (r == 1 and g == 1 and b == 1)
                local isBlack = (r == 0 and g == 0 and b == 0)

                if isWhite then hasWhite = true end
                if isBlack then hasBlack = true end

                -- Store walkable pixel data if the cell is mixed
                if isWhite then
                    table.insert(cell.data, {px, py})
                end
            end
        end

        -- Determine cell walkability
        if hasWhite and hasBlack then
            cell.isWalkable = MIXED
        elseif hasBlack then
            cell.isWalkable = NON_WALKABLE
        else
            cell.isWalkable = WALKABLE
        end

        -- Add the cell to the collision data
        state.collisionData.cells[gridX][gridY] = cell

        -- Move to the next cell
        state.currentX = state.currentX + state.collisionData.cellSize
        if state.currentX >= state.imageData:getWidth() then
            state.currentX = 0
            state.currentY = state.currentY + state.collisionData.cellSize
            if state.currentY >= state.imageData:getHeight() then
                state.isProcessing = false
                print("Processing complete!")
                break
            end
        end

        cellsProcessed = cellsProcessed + 1
    end

    -- Update progress
    state.progress = (state.currentY * state.collisionData.width + state.currentX) / (state.collisionData.width * state.collisionData.height)
end

function love.draw()
    local state = collisionState

    -- Draw the grid and pixel data for debugging
    local cellSize = state.collisionData.cellSize
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local scaleX = windowWidth / state.collisionData.width
    local scaleY = windowHeight / state.collisionData.height
    local scale = math.min(scaleX, scaleY)

    love.graphics.scale(scale, scale)

    for gridX, row in pairs(state.collisionData.cells) do
        for gridY, cell in pairs(row) do
            local x = (gridX - 1) * cellSize
            local y = (gridY - 1) * cellSize

            -- Draw cell background based on walkability
            if cell.isWalkable == NON_WALKABLE then
                love.graphics.setColor(1, 0, 0) -- Red for non-walkable
            elseif cell.isWalkable == MIXED then
                love.graphics.setColor(1, 1, 0) -- Yellow for mixed
            else
                love.graphics.setColor(0, 1, 0) -- Green for walkable
            end
            love.graphics.rectangle("fill", x, y, cellSize, cellSize)

            -- Draw individual walkable pixels if the cell is mixed
            if cell.isWalkable == MIXED then
                for _, pixel in ipairs(cell.data) do
                    local px, py = pixel[1], pixel[2]
                    love.graphics.setColor(1, 1, 1) -- White for walkable pixels
                    love.graphics.points(px, py)
                end
            end
        end
    end

    -- Draw debug information
    love.graphics.setColor(1, 1, 1) -- White
    local debugText = string.format(
        "Progress: %.2f%%\nCells Processed: %d",
        state.progress * 100,
        #state.collisionData.cells * #state.collisionData.cells[1]
    )
    love.graphics.print(debugText, 10, 10)
end

function love.keypressed(key)
    -- Save the collision data to a custom text file
    local outputPath = "collision_data.bin"
    saveCollisionData(collisionState.collisionData, outputPath)
    print("Collision data saved to " .. outputPath)
end

function saveCollisionData(data, path)
    local file = io.open(path, "w")
    if not file then
        print("Failed to open file for writing: " .. path)
        return
    end

    for gridX, row in pairs(data.cells) do
        for gridY, cell in pairs(row) do
            -- Write the custom format: <grid_x>_<grid_y>_<binary_pixel_data>
            local binaryString = ""
            for py = cell.y, cell.y + data.cellSize - 1 do
                for px = cell.x, cell.x + data.cellSize - 1 do
                    local r, g, b, a = state.imageData:getPixel(px, py)
                    local isWhite = (r == 1 and g == 1 and b == 1)
                    binaryString = binaryString .. (isWhite and "1" or "0")
                end
            end
            local line = string.format("%d_%d_%s\n", gridX - 1, gridY - 1, binaryString)
            file:write(line)
        end
    end

    file:close()
end

local love_errorhandler = love.errorhandler

function love.errorhandler(msg)
    if lldebugger then
        error(msg, 2)
    else
        return love_errorhandler(msg)
    end
end