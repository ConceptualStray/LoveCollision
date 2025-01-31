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
            data = nil -- Only populated if mixed
        }
        
        -- Check each pixel in the cell
        local hasWhite, hasBlack = false, false
        local walkablePixels = {}
        for py = state.currentY, math.min(state.currentY + state.collisionData.cellSize - 1, state.imageData:getHeight() - 1) do
            for px = state.currentX, math.min(state.currentX + state.collisionData.cellSize - 1, state.imageData:getWidth() - 1) do
                local r, g, b, a = state.imageData:getPixel(px, py)
                local isWhite = (r == 1 and g == 1 and b == 1)
                local isBlack = (r == 0 and g == 0 and b == 0)
                
                if isWhite then hasWhite = true end
                if isBlack then hasBlack = true end
                
                -- Store walkable pixel data if the cell is mixed
                if isWhite then
                    table.insert(walkablePixels, {px, py})
                end
            end
        end
        
        -- Determine cell walkability
        if hasWhite and hasBlack then
            cell.isWalkable = MIXED
            cell.data = walkablePixels
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
                    local pixelX = px
                    local pixelY = py
                    love.graphics.setColor(1, 1, 1) -- White for walkable pixels
                    love.graphics.points(pixelX, pixelY)
                end
            end
        end
    end
end

function love.keypressed(key)
    if key == "s" and not collisionState.isProcessing then
        -- Save the collision data to a .lua file
        local outputPath = "collisionTest.lua"
        saveCollisionData(collisionState.collisionData, outputPath)
        print("Collision data saved to " .. outputPath)
    end
end

function saveCollisionData(data, path)
    local serialized = "return {\n"
    serialized = serialized .. string.format("  width = %d,\n", data.width)
    serialized = serialized .. string.format("  height = %d,\n", data.height)
    serialized = serialized .. string.format("  cellSize = %d,\n", data.cellSize)
    serialized = serialized .. "  cells = {\n"
    -- Serialize the 2D grid
    for gridX, row in pairs(data.cells) do
        serialized = serialized .. string.format("    [%d] = {\n", gridX)
        for gridY, cell in pairs(row) do
            serialized = serialized .. string.format("      [%d] = {\n", gridY)
            serialized = serialized .. string.format("	x = %d,\n", cell.x)
            serialized = serialized .. string.format("	y = %d,\n", cell.y)
            serialized = serialized .. string.format("	isWalkable = %d,\n", cell.isWalkable) -- Use integer value
            if cell.isWalkable == MIXED then
                serialized = serialized .. "	data = {\n"
                for _, pixel in ipairs(cell.data) do
                    serialized = serialized .. string.format("	{ %d, %d },\n", pixel[1], pixel[2])
                end
                serialized = serialized .. "	},\n"
            end
            serialized = serialized .. "      },\n"
        end
        serialized = serialized .. "    },\n"
    end
    serialized = serialized .. "  }\n}"
    love.filesystem.write(path, serialized)
end