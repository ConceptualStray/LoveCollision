eDebug = false
if arg[2] == "debug" then
    eDebug = true
    require("lldebugger").start()
end

-- Constants for walkability states
local NON_WALKABLE = 0
local WALKABLE = 1
local MIXED = 2

-- State for the application
local state = {
    imageData = nil,
    collisionData = nil,
    currentX = 0,
    currentY = 0,
    isProcessing = false,
    progress = 0,
    status = "Drag and drop a JPG file to process", -- Initial status message
    outputFilePath = nil -- Path to save the collision data
}

function love.load()
    -- Set up debug font
    love.graphics.setNewFont(12)
end

function love.filedropped(file)
    -- Reset state when a new file is dropped
    state.imageData = nil
    state.collisionData = nil
    state.currentX = 0
    state.currentY = 0
    state.isProcessing = false
    state.progress = 0
    state.status = "Loading image..."
    state.outputFilePath = nil

    -- Load the dropped image file
    local success, err = pcall(function()
        -- Read the file data
        local fileData = file:read()
        local filePath = file:getFilename()

        -- Use love.filesystem.newFileData to create a FileData object
        local imageFileData = love.filesystem.newFileData(fileData, filePath)

        -- Load the image data
        local imageData = love.image.newImageData(imageFileData)
        state.imageData = imageData

        -- Initialize collision data
        local width, height = imageData:getWidth(), imageData:getHeight()
        local cellSize = 32
        state.collisionData = {
            width = width,
            height = height,
            cellSize = cellSize,
            cells = {} -- 2D grid: cells[gridX][gridY] = cell data
        }

        -- Generate the output file path
        local baseName = filePath:match("(.+)%..+$") -- Remove the file extension
        state.outputFilePath = baseName .. ".bin"

        -- Start processing
        state.isProcessing = true
        state.status = "Processing..."
    end)

    if not success then
        state.status = "Failed to load image: " .. tostring(err)
    end
end

function love.update(dt)
    if not state.isProcessing or not state.imageData then return end

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
                state.status = "Saving collision data..."
                saveCollisionData(state.collisionData, state.outputFilePath)
                state.status = "Complete! Collision data saved to " .. state.outputFilePath
                break
            end
        end

        cellsProcessed = cellsProcessed + 1
    end

    -- Update progress
    state.progress = (state.currentY * state.collisionData.width + state.currentX) / (state.collisionData.width * state.collisionData.height)
end

function love.draw()
    -- Draw the grid and pixel data for debugging
    if state.imageData then
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
            "Status: %s\nProgress: %.2f%%\nCells Processed: %d",
            sanitizeUTF8(state.status),
            state.progress * 100,
            #state.collisionData.cells * #state.collisionData.cells[1]
        )
        love.graphics.print(debugText, 10, 10)
    else
        -- Display a message if no image is loaded
        love.graphics.setColor(1, 1, 1) -- White
        love.graphics.print(sanitizeUTF8(state.status), 10, 10)
    end
end

function saveCollisionData(data, path)
    local file = io.open(path, "w")
    if not file then
        state.status = "Failed to save collision data: " .. path
        return
    end

    for gridX, row in pairs(data.cells) do
        for gridY, cell in pairs(row) do
            -- Write the custom format: <grid_x>_<grid_y>_<binary_pixel_data>
            local binaryString = ""
            for py = cell.y, cell.y + data.cellSize - 1 do
                for px = cell.x, cell.x + data.cellSize - 1 do
                    -- Clamp pixel coordinates to the image bounds
                    local clampedX = math.min(math.max(px, 0), state.imageData:getWidth() - 1)
                    local clampedY = math.min(math.max(py, 0), state.imageData:getHeight() - 1)

                    -- Get the pixel color
                    local r, g, b, a = state.imageData:getPixel(clampedX, clampedY)
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

-- Helper function to sanitize UTF-8 strings
function sanitizeUTF8(str)
    if not str then return "" end
    -- Remove invalid UTF-8 characters
    return str:gsub("[\128-\255]", "?")
end

local love_errorhandler = love.errorhandler

function love.errorhandler(msg)
    if lldebugger then
        error(msg, 2)
    else
        return love_errorhandler(msg)
    end
end