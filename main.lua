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
	FILE_BUFFER =''
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
                local isWhite = not(r == 0 and g == 0 and b == 0)
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


        -- Append the cell data to the FILE_BUFFER
        if cell.isWalkable == NON_WALKABLE then
            FILE_BUFFER=FILE_BUFFER .. string.format("%d,%d,%d\n", gridX - 1, gridY - 1, NON_WALKABLE)
        elseif cell.isWalkable == WALKABLE then
           FILE_BUFFER=FILE_BUFFER .. string.format("%d,%d,%d\n", gridX - 1, gridY - 1, WALKABLE)
        else
            -- For mixed cells, collect pixel data and perform run-length encoding
            local pixels = {}
            for py = cell.y, cell.y + state.collisionData.cellSize - 1 do
                for px = cell.x, cell.x + state.collisionData.cellSize - 1 do
                    local clampedX = math.min(math.max(px, 0), state.imageData:getWidth() - 1)
                    local clampedY = math.min(math.max(py, 0), state.imageData:getHeight() - 1)
                    local r, g, b, a = state.imageData:getPixel(clampedX, clampedY)
                    local isWhite = (r == 1 and g == 1 and b == 1)
                    table.insert(pixels, isWhite and 1 or 0)
                end
            end
            local encodedPixels = runLengthEncode(pixels)
            FILE_BUFFER=FILE_BUFFER .. string.format("%d,%d,%s\n", gridX - 1, gridY - 1, encodedPixels)
        end

        -- Move to the next cell
        state.currentX = state.currentX + state.collisionData.cellSize
        if state.currentX >= state.imageData:getWidth() then
            state.currentX = 0
            state.currentY = state.currentY + state.collisionData.cellSize
            if state.currentY >= state.imageData:getHeight() then
                state.isProcessing = false
                state.status = "Saving collision data..."
                saveCollisionData(FILE_BUFFER, state.outputFilePath)
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
    if state.outputFilePath then
        -- Read the collision data from the file
        local file = io.open(state.outputFilePath, "r")
        if not file then
            love.graphics.setColor(1, 0, 0) -- Red for error
            love.graphics.print("Failed to open collision data file: " .. state.outputFilePath, 10, 10)
            return
        end

        -- Parse the file contents
        local collisionData = {}
        for line in file:lines() do
            local gridX, gridY, value = line:match("(%d+),(%d+),(.+)")
            if gridX and gridY and value then
                gridX = tonumber(gridX)
                gridY = tonumber(gridY)
                if not collisionData[gridX] then
                    collisionData[gridX] = {}
                end
                collisionData[gridX][gridY] = value
            end
        end
        file:close()

        -- Draw the grid based on the parsed collision data
        local cellSize = state.collisionData.cellSize
        local windowWidth, windowHeight = love.graphics.getDimensions()
        local scaleX = windowWidth / state.collisionData.width
        local scaleY = windowHeight / state.collisionData.height
        local scale = math.min(scaleX, scaleY)

        love.graphics.scale(scale, scale)

        for gridX, row in pairs(collisionData) do
            for gridY, value in pairs(row) do
                local x = (gridX) * cellSize
                local y = (gridY) * cellSize

                -- Determine cell color based on the value
                if value == tostring(NON_WALKABLE) then
                    love.graphics.setColor(1, 0, 0) -- Red for non-walkable
                    love.graphics.rectangle("fill", x, y, cellSize, cellSize)
                elseif value == tostring(WALKABLE) then
                    love.graphics.setColor(0, 1, 0) -- Green for walkable
                    love.graphics.rectangle("fill", x, y, cellSize, cellSize)
                else
                    -- For mixed cells, parse the run-length encoded pixel data
                    love.graphics.setColor(1, 1, 0) -- Yellow for mixed cell background
                    love.graphics.rectangle("fill", x, y, cellSize, cellSize)

                    -- Parse the run-length encoded pixel data
                    local pixels = {}
                    for part in value:gmatch("[^,]+") do
                        local count, pixelValue = part:match("(%d+)x(%d+)")
                        if count and pixelValue then
                            count = tonumber(count)
                            pixelValue = tonumber(pixelValue)
                            for i = 1, count do
                                table.insert(pixels, pixelValue)
                            end
                        end
                    end

                    -- Render each pixel in the cell
                    for i, pixelValue in ipairs(pixels) do
                        local px = x + ((i - 1) % cellSize)
                        local py = y + math.floor((i - 1) / cellSize)
                        if pixelValue == 1 then
                            love.graphics.setColor(1, 1, 1) -- White for walkable pixels
                            love.graphics.points(px, py)
                        else
                            love.graphics.setColor(0, 0, 0) -- Black for non-walkable pixels
                            love.graphics.points(px, py)
                        end
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
            #collisionData * (collisionData[1] and #collisionData[1] or 0)
        )
        love.graphics.print(debugText, 10, 10)
    else
        -- Display a message if no image is loaded
        love.graphics.setColor(1, 1, 1) -- White
        love.graphics.print(sanitizeUTF8(state.status), 10, 10)
    end
end

-- Helper function to perform run-length encoding
function runLengthEncode(pixels)
    local encoded = {}
    local count = 1
    local current = pixels[1]

    for i = 2, #pixels do
        if pixels[i] == current then
            count = count + 1
        else
            table.insert(encoded, string.format("%dx%d", count, current))
            current = pixels[i]
            count = 1
        end
    end

    table.insert(encoded, string.format("%dx%d", count, current))
    return table.concat(encoded, ",")
end

function saveCollisionData(buffer, path)
    local file = io.open(path, "w+")
    if not file then
        state.status = "Failed to save collision data: " .. path
        return
    end


	file:write(FILE_BUFFER)

    file:close()
	FILE_BUFFER =''
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